"""The owner's catalogue: add, publish, hide, list and refresh movies.

Run by the project owner, from services/api:

    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py add 550
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py publish 550
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py unpublish 550
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py list
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py refresh
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py purge-tmdb

A movie is named by its TMDB ID, the number in its themoviedb.org address, or
by VeloraUG's own ID from `list`.

It connects as the database owner, because the API's role can't change the
catalogue. It asks for the owner's direct connection string, hidden, unless
VELORAUG_MIGRATION_DATABASE_URL is set, and checks it is the branch sign-in
uses before changing anything. The TMDB token comes from
VELORAUG_TMDB_READ_ACCESS_TOKEN, in the environment or services/api/.env.
Neither is ever printed. See docs/step-06a-catalogue-plan.md.
"""

import argparse
import getpass
import os
import sys
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.parse import unquote, urlsplit

import psycopg

API_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(API_DIR))

from app.catalogue import REFRESH_AFTER, save_details  # noqa: E402
from app.tmdb import (  # noqa: E402
    MovieDetails,
    TmdbClient,
    TmdbError,
    TmdbRefused,
)
from migrations.connection import (  # noqa: E402
    NEON_AUTH_TABLES,
    UnsafeConnection,
    _setting,
    clean,
    describe,
    require_sign_in_branch,
)

TOKEN_NAME = "VELORAUG_TMDB_READ_ACCESS_TOKEN"
# `refresh` fetches copies older than REFRESH_AFTER, 7 days, as the API does.
# TMDB's terms allow 6 months. A copy that couldn't be refreshed by then is
# deleted. The API stops serving a copy earlier, at 150 days.
DELETE_AFTER = timedelta(days=180)


class CatalogueError(Exception):
    """A mistake the owner can fix. The message is safe to show."""


@dataclass(frozen=True)
class Movie:
    id: uuid.UUID
    tmdb_id: int
    published: bool
    title: str | None
    year: int | None
    fetched_at: datetime | None


# --- Database work, given a connection. The caller commits. ------------------


def add_movie(conn: psycopg.Connection, details: MovieDetails) -> uuid.UUID:
    """Adds the movie, unpublished, with its TMDB copy."""
    row = conn.execute(
        """
        insert into public.movies (tmdb_id) values (%s)
        on conflict (tmdb_id) do nothing
        returning id
        """,
        (details.tmdb_id,),
    ).fetchone()
    if row is None:
        raise CatalogueError(f"TMDB movie {details.tmdb_id} is already added")
    save_details(conn, details)
    return row[0]


def _where(key: str) -> tuple[str, object]:
    """The movie a key names: VeloraUG's ID, or a TMDB ID."""
    try:
        return "id = %s", uuid.UUID(key)
    except ValueError:
        pass
    if key.isdigit() and 0 < int(key) < 2**31:
        return "tmdb_id = %s", int(key)
    raise CatalogueError(f"{key!r} isn't a TMDB ID or a VeloraUG movie ID")


def find_movie(conn: psycopg.Connection, key: str) -> Movie:
    column, value = _where(key)
    row = conn.execute(
        f"""
        select m.id, m.tmdb_id, m.published, d.title,
               extract(year from d.release_date)::int, d.fetched_at
        from public.movies m
        left join public.tmdb_movie_details d using (tmdb_id)
        where m.{column}
        """,
        (value,),
    ).fetchone()
    if row is None:
        raise CatalogueError(f"No movie {key} in the catalogue. Add it first")
    return Movie(*row)


def set_published(conn: psycopg.Connection, key: str, published: bool) -> Movie:
    movie = find_movie(conn, key)
    if published and movie.title is None:
        raise CatalogueError(
            f"TMDB movie {movie.tmdb_id} has no details yet. Run refresh first"
        )
    conn.execute(
        """
        update public.movies
        set published = %s,
            published_at = case when %s then coalesce(published_at, now()) end
        where id = %s
        """,
        (published, published, movie.id),
    )
    return find_movie(conn, str(movie.id))


def list_movies(conn: psycopg.Connection) -> list[Movie]:
    rows = conn.execute(
        """
        select m.id, m.tmdb_id, m.published, d.title,
               extract(year from d.release_date)::int, d.fetched_at
        from public.movies m
        left join public.tmdb_movie_details d using (tmdb_id)
        order by m.published desc, m.published_at desc nulls last, m.added_at desc
        """
    ).fetchall()
    return [Movie(*row) for row in rows]


@dataclass
class RefreshResult:
    refreshed: int = 0
    up_to_date: int = 0
    deleted: int = 0
    failed: list[str] | None = None


def refresh(
    conn: psycopg.Connection,
    fetch: Callable[[int], MovieDetails],
    now: datetime | None = None,
) -> RefreshResult:
    """Fetches copies older than REFRESH_AFTER. A copy that can't be fetched
    is kept until DELETE_AFTER, then deleted.

    Stops at the first refused token, because every other fetch would fail
    the same way.
    """
    now = now or datetime.now(UTC)
    result = RefreshResult(failed=[])
    rows = conn.execute(
        """
        select m.tmdb_id, d.fetched_at from public.movies m
        left join public.tmdb_movie_details d using (tmdb_id)
        order by m.tmdb_id
        """
    ).fetchall()
    for tmdb_id, fetched_at in rows:
        if fetched_at is not None and now - fetched_at < REFRESH_AFTER:
            result.up_to_date += 1
            continue
        try:
            save_details(conn, fetch(tmdb_id))
            result.refreshed += 1
            continue
        except TmdbRefused:
            raise
        except TmdbError as error:
            result.failed.append(f"{tmdb_id}: {error}")
        if fetched_at is not None and now - fetched_at >= DELETE_AFTER:
            conn.execute(
                "delete from public.tmdb_movie_details where tmdb_id = %s", (tmdb_id,)
            )
            result.deleted += 1
    return result


def purge_tmdb(conn: psycopg.Connection) -> int:
    """Deletes every TMDB copy. Movies stay, unpublished."""
    conn.execute(
        "update public.movies set published = false, published_at = null "
        "where published"
    )
    return conn.execute("delete from public.tmdb_movie_details").rowcount


# --- The command line --------------------------------------------------------


def _age(fetched_at: datetime | None, now: datetime) -> str:
    if fetched_at is None:
        return "no details"
    days = (now - fetched_at).days
    return "fetched today" if days == 0 else f"fetched {days} days ago"


def describe_movie(movie: Movie, now: datetime | None = None) -> str:
    now = now or datetime.now(UTC)
    state = "published" if movie.published else "hidden"
    year = f" ({movie.year})" if movie.year else ""
    title = movie.title or "(no details)"
    return (
        f"{title}{year}  TMDB {movie.tmdb_id}  {state}  "
        f"{_age(movie.fetched_at, now)}  id {movie.id}"
    )


def typed(question: str, word: str) -> bool:
    """True if the owner types the word. No input at all, as from a closed
    pipe, counts as no."""
    try:
        answer = input(f"{question} Type {word}: ")
    except EOFError:
        print()
        return False
    # PowerShell can put a byte-order mark before piped text.
    return answer.strip().lstrip("﻿").lower() == word


def plural(count: int, one: str, many: str) -> str:
    return f"{count} {one if count == 1 else many}"


def tmdb_client() -> TmdbClient:
    token = _setting(TOKEN_NAME)
    if not token:
        raise CatalogueError(f"{TOKEN_NAME} isn't set, and isn't in services/api/.env")
    return TmdbClient(token)


def connect() -> psycopg.Connection:
    """The owner's connection, after checking it is the right database."""
    url = os.environ.get("VELORAUG_MIGRATION_DATABASE_URL", "").strip()
    if not url:
        url = getpass.getpass(
            "Owner connection string, direct (not pooled). Hidden as you paste: "
        )
    try:
        url = clean(url)
        print(f"Database: {describe(url)}")
    except UnsafeConnection as error:
        raise CatalogueError(f"Refused: {error}") from None
    try:
        conn = psycopg.connect(url, connect_timeout=15)
    except psycopg.Error as error:
        raise CatalogueError(
            f"Couldn't connect ({type(error).__name__}): {safe_message(error, url)}"
        ) from None
    try:
        tables = conn.execute(NEON_AUTH_TABLES).fetchone()[0]
        print(f"Branch: {require_sign_in_branch(url, tables)}")
    except UnsafeConnection as error:
        conn.close()
        raise CatalogueError(f"Refused: {error}") from None
    return conn


def safe_message(error: Exception, url: str) -> str:
    """The error's last line, with the password masked wherever it appears.

    psycopg's messages about a malformed string can quote part of it.
    """
    message = (str(error).strip().splitlines() or [""])[-1]
    password = urlsplit(url).password
    for secret in {password, unquote(password or "")} - {None, ""}:
        message = message.replace(secret, "<hidden>")
    return message[:300]


def run(args: argparse.Namespace) -> int:
    if args.command == "add":
        # Everything is fetched before the owner string is asked for, so a
        # wrong ID costs nothing.
        tmdb_ids = list(dict.fromkeys(args.tmdb_ids))
        with tmdb_client() as client:
            found = [client.movie(tmdb_id) for tmdb_id in tmdb_ids]
        for details in found:
            year = f" ({details.year})" if details.year else ""
            genres = f"  {', '.join(details.genres)}" if details.genres else ""
            print(f"TMDB {details.tmdb_id}: {details.title}{year}{genres}")
        with connect() as conn:
            for details in found:
                try:
                    find_movie(conn, str(details.tmdb_id))
                except CatalogueError:
                    continue
                raise CatalogueError(
                    f"TMDB movie {details.tmdb_id} is already added. Nothing changed"
                )
            question = "Add it, hidden?" if len(found) == 1 else "Add them, hidden?"
            if not typed(question, "yes"):
                print("Nothing changed.")
                return 1
            for details in found:
                add_movie(conn, details)
            # One commit: all are added, or none.
            conn.commit()
        print(f"Added {plural(len(found), 'movie', 'movies')}, hidden.")
        ids = " ".join(str(tmdb_id) for tmdb_id in tmdb_ids)
        print(f"Publish with: scripts\\catalogue.py publish {ids}")
        return 0

    if args.command in ("publish", "unpublish"):
        with connect() as conn:
            movies = [
                set_published(conn, key, args.command == "publish")
                for key in dict.fromkeys(args.movies)
            ]
            # One commit: all change, or none.
            conn.commit()
        for movie in movies:
            print(describe_movie(movie))
        return 0

    if args.command == "list":
        with connect() as conn:
            movies = list_movies(conn)
        for movie in movies:
            print(describe_movie(movie))
        published = sum(movie.published for movie in movies)
        print(f"\n{plural(len(movies), 'movie', 'movies')}, {published} published")
        return 0

    if args.command == "refresh":
        with tmdb_client() as client, connect() as conn:
            result = refresh(conn, client.movie)
            conn.commit()
        print(
            f"{result.refreshed} refreshed, {result.up_to_date} already up to "
            f"date, {plural(result.deleted, 'expired copy', 'expired copies')} "
            "deleted"
        )
        for failure in result.failed or []:
            print(f"Failed: {failure}")
        return 1 if result.failed else 0

    if args.command == "purge-tmdb":
        with connect() as conn:
            if not typed("Delete every TMDB copy and hide every movie?", "purge"):
                print("Nothing changed.")
                return 1
            deleted = purge_tmdb(conn)
            conn.commit()
        print(
            f"{plural(deleted, 'TMDB copy', 'TMDB copies')} deleted. "
            "Every movie is hidden."
        )
        return 0

    raise AssertionError(args.command)


def parser() -> argparse.ArgumentParser:
    main_parser = argparse.ArgumentParser(description="Manage VeloraUG's movies.")
    commands = main_parser.add_subparsers(dest="command", required=True)
    add = commands.add_parser("add", help="add movies from TMDB, hidden")
    add.add_argument("tmdb_ids", type=int, nargs="+", metavar="tmdb_id")
    for name, text in (("publish", "show"), ("unpublish", "hide")):
        command = commands.add_parser(name, help=f"{text} movies in the app")
        command.add_argument(
            "movies", nargs="+", metavar="movie", help="TMDB IDs or VeloraUG movie IDs"
        )
    commands.add_parser("list", help="every movie, published or not")
    commands.add_parser("refresh", help="fetch TMDB copies older than 7 days")
    commands.add_parser("purge-tmdb", help="delete every TMDB copy")
    return main_parser


def main() -> int:
    args = parser().parse_args()
    try:
        return run(args)
    except (CatalogueError, TmdbError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    except psycopg.Error as error:
        # Postgres and Neon messages don't repeat connection strings.
        print(f"Failed, nothing saved: {type(error).__name__}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
