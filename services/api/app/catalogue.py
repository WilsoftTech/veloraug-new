"""Keeping TMDB's details fresh: the Refresher, and the rules for copies.

Viewers read the catalogue through app/viewer.py. The rules for TMDB
copies, from docs/step-06a-catalogue-plan.md, apply to sources from TMDB:

- A copy older than SERVE_FOR is never served. TMDB's terms allow 6 months.
- A copy older than REFRESH_AFTER is served, then refreshed in the background.
- A published edition with no copy, or only an expired one, is left out of
  lists, and its page answers 503 until the background fetch succeeds.

Typed-in details never expire.
"""

import logging
import threading
import time
from collections.abc import Callable, Iterable
from datetime import timedelta

import psycopg

from app.db import Database
from app.tmdb import (
    DEFAULT_IMAGES,
    ImageConfig,
    MovieDetails,
    TmdbClient,
    TmdbError,
    TmdbNotFound,
    TmdbRefused,
    TmdbUnavailable,
)

REFRESH_AFTER = timedelta(days=7)
SERVE_FOR = timedelta(days=150)
# After a failed fetch, the same movie isn't tried again for this long.
RETRY_AFTER_FAILURE_SECONDS = 15 * 60
# TMDB's image settings rarely change.
IMAGE_CONFIG_EVERY_SECONDS = 24 * 60 * 60
# How often a list request may look for missing or old copies.
SWEEP_EVERY_SECONDS = 5 * 60
# Fetches per background run, to stay well inside TMDB's rate limit.
MAX_FETCHES_PER_RUN = 10

logger = logging.getLogger("veloraug.catalogue")


# A source is named by its kind and TMDB ID: TMDB numbers movies and series
# separately.
SourceKey = tuple[str, int]


def needing_refresh(conn: psycopg.Connection, limit: int) -> list[SourceKey]:
    """Published sources from TMDB whose copy is missing or old, oldest
    first. Row-level security shows the API's role only sources of
    published editions."""
    rows = conn.execute(
        """
        select s.kind, s.tmdb_id from public.sources s
        where s.details_from = 'tmdb'
          and (s.fetched_at is null or s.fetched_at < now() - %(refresh_after)s)
        order by s.fetched_at nulls first
        limit %(limit)s
        """,
        {"refresh_after": REFRESH_AFTER, "limit": limit},
    ).fetchall()
    return [(kind, tmdb_id) for kind, tmdb_id in rows]


def save_details(
    conn: psycopg.Connection, details: MovieDetails, kind: str = "movie"
) -> int:
    """Replaces a source's TMDB copy, dated now. Returns how many
    sources changed: 0 if there is none, or the role can't see it. The
    owner's script and the admin routes use this too."""
    return conn.execute(
        """
        update public.sources set
          title = %s, original_title = %s, overview = %s, release_date = %s,
          runtime_minutes = %s, genres = %s, poster_path = %s,
          backdrop_path = %s, tmdb_rating = %s, tmdb_vote_count = %s,
          fetched_at = now(), rating_updated_at = now()
        where kind = %s and tmdb_id = %s
        """,
        (
            details.title,
            details.original_title,
            details.overview,
            details.release_date,
            details.runtime_minutes,
            list(details.genres),
            details.poster_path,
            details.backdrop_path,
            details.rating,
            details.vote_count,
            kind,
            details.tmdb_id,
        ),
    ).rowcount


class Refresher:
    """Fetches TMDB copies in the background, after a response is sent.

    At most one fetch per movie at a time, a pause after a failure, and a
    pause for everything when TMDB asks for one. TMDB failures are logged by
    TMDB ID and status only, never with the token.
    """

    def __init__(
        self,
        database: Database,
        client: TmdbClient,
        *,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._database = database
        self._client = client
        self._clock = clock
        self._lock = threading.Lock()
        self._in_flight: set[SourceKey] = set()
        self._failed_at: dict[SourceKey, float] = {}
        self._paused_until = 0.0
        self._last_sweep: float | None = None
        self._images = DEFAULT_IMAGES
        self._images_at: float | None = None
        self._token_refused = False

    @property
    def images(self) -> ImageConfig:
        return self._images

    def close(self) -> None:
        self._client.close()

    def sweep_due(self) -> bool:
        """True at most once per SWEEP_EVERY_SECONDS, for a list request."""
        now = self._clock()
        with self._lock:
            if (
                self._last_sweep is not None
                and now - self._last_sweep < SWEEP_EVERY_SECONDS
            ):
                return False
            self._last_sweep = now
            return True

    def sweep(self) -> None:
        """Refreshes published movies with missing or old copies."""
        try:
            with self._database.anonymous() as conn:
                keys = needing_refresh(conn, MAX_FETCHES_PER_RUN)
        except Exception as error:
            logger.warning(
                "Couldn't look for old TMDB copies: %s", type(error).__name__
            )
            return
        self.refresh(keys)

    def refresh(self, keys: Iterable[SourceKey | int]) -> None:
        """Refreshes these sources. A bare number is a movie's TMDB ID."""
        self._refresh_images()
        named = [key if isinstance(key, tuple) else ("movie", key) for key in keys]
        for key in list(dict.fromkeys(named))[:MAX_FETCHES_PER_RUN]:
            if not self._claim(key):
                continue
            try:
                self._refresh_one(key)
            finally:
                with self._lock:
                    self._in_flight.discard(key)

    def _claim(self, key: SourceKey) -> bool:
        now = self._clock()
        with self._lock:
            if self._token_refused or now < self._paused_until:
                return False
            if key in self._in_flight:
                return False
            failed = self._failed_at.get(key)
            if failed is not None and now - failed < RETRY_AFTER_FAILURE_SECONDS:
                return False
            self._in_flight.add(key)
            return True

    def _refresh_one(self, key: SourceKey) -> None:
        kind, tmdb_id = key
        try:
            details = self._client.details(kind, tmdb_id)
        except TmdbError as error:
            self._failed(key, error)
            return
        try:
            with self._database.anonymous() as conn:
                if not save_details(conn, details, kind):
                    # The movie was unpublished meanwhile, so row-level
                    # security hides its source.
                    raise LookupError("no published source")
        except Exception as error:
            logger.warning(
                "Couldn't save TMDB %s %s: %s", kind, tmdb_id, type(error).__name__
            )
            with self._lock:
                self._failed_at[key] = self._clock()
            return
        with self._lock:
            self._failed_at.pop(key, None)
        logger.info("Refreshed TMDB %s %s", kind, tmdb_id)

    def _failed(self, key: SourceKey, error: TmdbError) -> None:
        kind, tmdb_id = key
        now = self._clock()
        with self._lock:
            self._failed_at[key] = now
            if isinstance(error, TmdbRefused):
                self._token_refused = True
            elif isinstance(error, TmdbUnavailable) and error.retry_after is not None:
                self._paused_until = now + min(error.retry_after, 300)
        if isinstance(error, TmdbRefused):
            logger.error("TMDB refused the token. Refreshing has stopped")
        elif isinstance(error, TmdbNotFound):
            # Kept until it ages out. The owner should check the movie.
            logger.warning("TMDB has no %s %s. Its copy is kept for now", kind, tmdb_id)
        else:
            logger.warning("Couldn't refresh TMDB %s %s: %s", kind, tmdb_id, error)

    def _refresh_images(self) -> None:
        now = self._clock()
        with self._lock:
            if (
                self._token_refused
                or now < self._paused_until
                or (
                    self._images_at is not None
                    and now - self._images_at < IMAGE_CONFIG_EVERY_SECONDS
                )
            ):
                return
            self._images_at = now
        try:
            images = self._client.image_config()
        except TmdbError as error:
            logger.warning("Couldn't fetch TMDB's image settings: %s", error)
            return
        with self._lock:
            self._images = images
