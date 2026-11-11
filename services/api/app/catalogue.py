"""The catalogue: published movies, with the API's copy of their TMDB details.

Reads run in Database.anonymous(), where row-level security shows the API's
role published movies only. The rules from docs/step-06a-catalogue-plan.md:

- A copy older than SERVE_FOR is never served. TMDB's terms allow 6 months.
- A copy older than REFRESH_AFTER is served, then refreshed in the background.
- A published movie with no copy, or only an expired one, is left out of
  lists, and its detail answers 503 until the background fetch succeeds.
"""

import logging
import threading
import time
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from datetime import date, timedelta
from uuid import UUID

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


@dataclass(frozen=True)
class MovieRow:
    id: UUID
    tmdb_id: int
    title: str
    original_title: str | None
    overview: str | None
    release_date: date | None
    runtime_minutes: int | None
    genres: tuple[str, ...]
    poster_path: str | None
    backdrop_path: str | None
    stale: bool

    @property
    def year(self) -> int | None:
        return self.release_date.year if self.release_date else None


_COLUMNS = """
    m.id, m.tmdb_id, d.title, d.original_title, d.overview, d.release_date,
    d.runtime_minutes, d.genres, d.poster_path, d.backdrop_path,
    d.fetched_at < now() - %(refresh_after)s as stale
"""

_AGES = {"refresh_after": REFRESH_AFTER, "serve_for": SERVE_FOR}


def _row(values: tuple) -> MovieRow:
    *head, genres, poster, backdrop, stale = values
    return MovieRow(*head, tuple(genres or ()), poster, backdrop, bool(stale))


def _like_prefix(text: str) -> str:
    """text as a LIKE pattern that matches it literally."""
    return text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def list_movies(
    conn: psycopg.Connection, *, limit: int, offset: int, query: str | None = None
) -> list[MovieRow]:
    """Published movies with a servable copy. Newest published first, or,
    when searching, titles that start with the query first."""
    params: dict = {**_AGES, "limit": limit, "offset": offset}
    where = "d.fetched_at >= now() - %(serve_for)s"
    order = "m.published_at desc, m.id"
    if query:
        params["contains"] = f"%{_like_prefix(query.lower())}%"
        params["starts"] = f"{_like_prefix(query.lower())}%"
        where += " and lower(d.title) like %(contains)s"
        order = (
            "lower(d.title) like %(starts)s desc, lower(d.title), m.published_at desc"
        )
    rows = conn.execute(
        f"""
        select {_COLUMNS}
        from public.movies m
        join public.tmdb_movie_details d using (tmdb_id)
        where {where}
        order by {order}
        limit %(limit)s offset %(offset)s
        """,
        params,
    ).fetchall()
    return [_row(row) for row in rows]


class DetailsUnavailable(Exception):
    """The movie is published, but has no servable copy yet."""

    def __init__(self, tmdb_id: int) -> None:
        super().__init__(tmdb_id)
        self.tmdb_id = tmdb_id


def get_movie(conn: psycopg.Connection, movie_id: UUID) -> MovieRow | None:
    """One published movie, or None. DetailsUnavailable if its copy is
    missing or too old to serve."""
    row = conn.execute(
        f"""
        select {_COLUMNS}, d.fetched_at >= now() - %(serve_for)s as servable
        from public.movies m
        left join public.tmdb_movie_details d using (tmdb_id)
        where m.id = %(id)s
        """,
        {**_AGES, "id": movie_id},
    ).fetchone()
    if row is None:
        return None
    *values, servable = row
    if not servable:
        raise DetailsUnavailable(values[1])
    return _row(tuple(values))


def needing_refresh(conn: psycopg.Connection, limit: int) -> list[int]:
    """TMDB IDs of published movies whose copy is missing or old, oldest
    first."""
    rows = conn.execute(
        """
        select m.tmdb_id from public.movies m
        left join public.tmdb_movie_details d using (tmdb_id)
        where d.fetched_at is null or d.fetched_at < now() - %(refresh_after)s
        order by d.fetched_at nulls first
        limit %(limit)s
        """,
        {**_AGES, "limit": limit},
    ).fetchall()
    return [row[0] for row in rows]


def save_details(conn: psycopg.Connection, details: MovieDetails) -> None:
    """Adds or replaces a movie's copy, dated now. The owner's script uses
    this too."""
    conn.execute(
        """
        insert into public.tmdb_movie_details (
          tmdb_id, title, original_title, overview, release_date,
          runtime_minutes, genres, poster_path, backdrop_path, fetched_at
        ) values (%s, %s, %s, %s, %s, %s, %s, %s, %s, now())
        on conflict (tmdb_id) do update set
          title = excluded.title,
          original_title = excluded.original_title,
          overview = excluded.overview,
          release_date = excluded.release_date,
          runtime_minutes = excluded.runtime_minutes,
          genres = excluded.genres,
          poster_path = excluded.poster_path,
          backdrop_path = excluded.backdrop_path,
          fetched_at = excluded.fetched_at
        """,
        (
            details.tmdb_id,
            details.title,
            details.original_title,
            details.overview,
            details.release_date,
            details.runtime_minutes,
            list(details.genres),
            details.poster_path,
            details.backdrop_path,
        ),
    )


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
        self._in_flight: set[int] = set()
        self._failed_at: dict[int, float] = {}
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
                tmdb_ids = needing_refresh(conn, MAX_FETCHES_PER_RUN)
        except Exception as error:
            logger.warning(
                "Couldn't look for old TMDB copies: %s", type(error).__name__
            )
            return
        self.refresh(tmdb_ids)

    def refresh(self, tmdb_ids: Iterable[int]) -> None:
        self._refresh_images()
        for tmdb_id in list(dict.fromkeys(tmdb_ids))[:MAX_FETCHES_PER_RUN]:
            if not self._claim(tmdb_id):
                continue
            try:
                self._refresh_one(tmdb_id)
            finally:
                with self._lock:
                    self._in_flight.discard(tmdb_id)

    def _claim(self, tmdb_id: int) -> bool:
        now = self._clock()
        with self._lock:
            if self._token_refused or now < self._paused_until:
                return False
            if tmdb_id in self._in_flight:
                return False
            failed = self._failed_at.get(tmdb_id)
            if failed is not None and now - failed < RETRY_AFTER_FAILURE_SECONDS:
                return False
            self._in_flight.add(tmdb_id)
            return True

    def _refresh_one(self, tmdb_id: int) -> None:
        try:
            details = self._client.movie(tmdb_id)
        except TmdbError as error:
            self._failed(tmdb_id, error)
            return
        try:
            with self._database.anonymous() as conn:
                save_details(conn, details)
        except Exception as error:
            # For example, the movie was unpublished meanwhile, so row-level
            # security refuses the write.
            logger.warning(
                "Couldn't save TMDB movie %s: %s", tmdb_id, type(error).__name__
            )
            with self._lock:
                self._failed_at[tmdb_id] = self._clock()
            return
        with self._lock:
            self._failed_at.pop(tmdb_id, None)
        logger.info("Refreshed TMDB movie %s", tmdb_id)

    def _failed(self, tmdb_id: int, error: TmdbError) -> None:
        now = self._clock()
        with self._lock:
            self._failed_at[tmdb_id] = now
            if isinstance(error, TmdbRefused):
                self._token_refused = True
            elif isinstance(error, TmdbUnavailable) and error.retry_after is not None:
                self._paused_until = now + min(error.retry_after, 300)
        if isinstance(error, TmdbRefused):
            logger.error("TMDB refused the token. Refreshing has stopped")
        elif isinstance(error, TmdbNotFound):
            # Kept until it ages out. The owner should check the movie.
            logger.warning("TMDB has no movie %s. Its copy is kept for now", tmdb_id)
        else:
            logger.warning("Couldn't refresh TMDB movie %s: %s", tmdb_id, error)

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
