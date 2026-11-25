"""Fills in TMDB's rating for source titles fetched before ratings were kept.

Run by the project owner, from services/api:

    .\\.venv\\Scripts\\python.exe scripts\\backfill_ratings.py --dry-run
    .\\.venv\\Scripts\\python.exe scripts\\backfill_ratings.py
    .\\.venv\\Scripts\\python.exe scripts\\backfill_ratings.py --refresh --rate 2

By default it fetches every TMDB source that has never had its rating asked
for, whatever the age of its copy. With --refresh it also fetches sources
whose rating is older than 7 days; anything newer is skipped. Each fetch
replaces the whole TMDB copy through app.catalogue.save_details, as the API's
background refresh does, so the copy's other fields stay in step.

It is paced to --rate requests a second (4 by default, far inside TMDB's
limit), waits when TMDB asks it to, and stops at a refused token. Each title
is saved as soon as it is fetched, so stopping part-way loses nothing.

It connects as the database owner, as scripts/catalogue.py does, and reads
the token from VELORAUG_TMDB_READ_ACCESS_TOKEN. Neither is ever printed.
"""

import argparse
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

import psycopg

API_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(API_DIR))

from app.catalogue import REFRESH_AFTER, SourceKey, save_details  # noqa: E402
from app.tmdb import (  # noqa: E402
    MovieDetails,
    TmdbError,
    TmdbRefused,
    TmdbUnavailable,
)

DEFAULT_RATE = 4.0
MAX_RATE = 20.0
# How many times one title is tried when TMDB asks us to wait.
MAX_TRIES = 3
# The longest wait TMDB's Retry-After is trusted for.
MAX_WAIT_SECONDS = 60.0


def pending(
    conn: psycopg.Connection, *, refresh: bool, limit: int | None = None
) -> list[SourceKey]:
    """TMDB sources to fetch: never rated first, then (with refresh) the
    oldest ratings. Ratings newer than REFRESH_AFTER are never included."""
    rows = conn.execute(
        """
        select kind, tmdb_id from public.sources
        where details_from = 'tmdb'
          and (rating_updated_at is null
               or (%(refresh)s
                   and rating_updated_at < now() - %(refresh_after)s))
        order by rating_updated_at nulls first, kind, tmdb_id
        limit %(limit)s
        """,
        {"refresh": refresh, "refresh_after": REFRESH_AFTER, "limit": limit},
    ).fetchall()
    return [(kind, tmdb_id) for kind, tmdb_id in rows]


@dataclass
class BackfillResult:
    saved: int = 0
    rated: int = 0
    failed: list[str] = field(default_factory=list)


class Pacer:
    """Keeps requests at least 1/rate seconds apart, and none before the end
    of a pause TMDB asked for."""

    def __init__(
        self,
        rate: float,
        *,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        if not 0 < rate <= MAX_RATE:
            raise ValueError(f"The rate is between 0 and {MAX_RATE:g} a second")
        self._gap = 1.0 / rate
        self._clock = clock
        self._sleep = sleep
        self._last: float | None = None
        self._not_before: float | None = None

    def wait(self) -> None:
        now = self._clock()
        due = now
        if self._last is not None:
            due = max(due, self._last + self._gap)
        if self._not_before is not None:
            due = max(due, self._not_before)
        if due > now:
            self._sleep(due - now)
            now = self._clock()
        self._last = now

    def hold(self, seconds: float) -> None:
        """No request for this long from now, whichever title is next."""
        self._not_before = self._clock() + seconds


def backfill(
    conn: psycopg.Connection,
    keys: list[SourceKey],
    fetch: Callable[[str, int], MovieDetails],
    pacer: Pacer,
    *,
    report: Callable[[str], None] = print,
) -> BackfillResult:
    """Fetches and saves each source, committing after each one. Stops at
    the first refused token."""
    result = BackfillResult()
    for kind, tmdb_id in keys:
        details = None
        for attempt in range(1, MAX_TRIES + 1):
            pacer.wait()
            try:
                details = fetch(kind, tmdb_id)
                break
            except TmdbRefused:
                raise
            except TmdbUnavailable as error:
                # Kept even after the last try, so the next title waits too.
                if error.retry_after is not None:
                    pacer.hold(min(error.retry_after, MAX_WAIT_SECONDS))
                if error.retry_after is None or attempt == MAX_TRIES:
                    result.failed.append(f"{kind} {tmdb_id}: {error}")
                    break
            except TmdbError as error:
                result.failed.append(f"{kind} {tmdb_id}: {error}")
                break
        if details is None:
            continue
        save_details(conn, details, kind)
        conn.commit()
        result.saved += 1
        if details.rating is not None:
            result.rated += 1
        report(
            f"{kind} {tmdb_id}: "
            + (
                f"{details.rating:.1f} from {details.vote_count} votes"
                if details.rating is not None
                else "no rating on TMDB"
            )
        )
    return result


def parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Fill in TMDB ratings for source titles."
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="also refetch ratings older than 7 days",
    )
    parser.add_argument(
        "--rate",
        type=float,
        default=DEFAULT_RATE,
        help=f"requests a second, at most {MAX_RATE:g} (default {DEFAULT_RATE:g})",
    )
    parser.add_argument("--limit", type=int, help="fetch at most this many titles")
    parser.add_argument(
        "--dry-run", action="store_true", help="list what would be fetched"
    )
    return parser


def main() -> int:
    # Imported here so --help works without the owner's settings.
    from scripts.catalogue import CatalogueError, connect, tmdb_client

    args = parser().parse_args()
    if args.limit is not None and args.limit < 1:
        print("--limit is at least 1", file=sys.stderr)
        return 2
    try:
        pacer = Pacer(args.rate)
        with connect() as conn:
            keys = pending(conn, refresh=args.refresh, limit=args.limit)
            conn.commit()
            print(f"{len(keys)} to fetch")
            if args.dry_run:
                for kind, tmdb_id in keys:
                    print(f"  {kind} {tmdb_id}")
                return 0
            if not keys:
                return 0
            with tmdb_client() as client:
                result = backfill(conn, keys, client.details, pacer)
    except (CatalogueError, TmdbError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    except psycopg.Error as error:
        print(f"Failed ({type(error).__name__}). Saved titles stay saved.")
        return 1
    print(
        f"{result.saved} saved, {result.rated} with a rating, "
        f"{len(result.failed)} failed"
    )
    for line in result.failed:
        print(f"  {line}")
    return 1 if result.failed else 0


if __name__ == "__main__":
    sys.exit(main())
