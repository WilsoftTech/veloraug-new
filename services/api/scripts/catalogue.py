"""The owner's catalogue: editions, drafts, keys, admins and the test films.

Run by the project owner, from services/api:

    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py list
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py draft movie "Fast X" --year 2023
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py draft series "Kabaka" \\
        --season 1 --episode 1
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py draft episode \\
        --series <edition id> --season 1 --episode 2
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py publish <edition id>
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py unpublish <edition id>
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py refresh
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py purge-tmdb
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py grant-upload <item id> --for Me
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py revoke-upload <key id>
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py uploads [<edition id>]
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py remove-original <original id>
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py admin add <user id>
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py admin remove <user id>
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py admin list
    .\\.venv\\Scripts\\python.exe scripts\\catalogue.py delete-test-films

Editions, items and drafts are described in docs/step-09a-vj-catalogue-plan.md.
From Step 9C, admins do most of this in the app; these commands stay for the
owner, and `admin` and `delete-test-films` are the owner's alone.

It connects as the database owner, because the API's roles can't do all of
this. It asks for the owner's direct connection string, hidden, unless
VELORAUG_MIGRATION_DATABASE_URL is set, and checks it is the branch sign-in
uses before changing anything. The TMDB token comes from
VELORAUG_TMDB_READ_ACCESS_TOKEN, in the environment or services/api/.env.
Neither is ever printed.
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

from app import editions  # noqa: E402
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
from scripts.upload_keys import (  # noqa: E402
    DEFAULT_DAYS,
    UploadKeyError,
    describe_uploads,
    grant_upload,
    item_name,
    list_uploads,
    request_removal,
    revoke_upload,
)

TOKEN_NAME = "VELORAUG_TMDB_READ_ACCESS_TOKEN"
# `refresh` fetches copies older than REFRESH_AFTER, 7 days, as the API does.
# TMDB's terms allow 6 months. A copy that couldn't be refreshed by then is
# deleted. The API stops serving a copy earlier, at 150 days.
DELETE_AFTER = timedelta(days=180)


class CatalogueError(Exception):
    """A mistake the owner can fix. The message is safe to show."""


@dataclass(frozen=True)
class Edition:
    id: uuid.UUID
    kind: str
    title: str
    status: str
    test: bool
    vj: str | None
    language: str
    tmdb_id: int | None
    details_from: str | None
    fetched_at: datetime | None
    items: int
    ready: int


# --- Database work, given a connection. The caller commits. ------------------


_EDITION = """
    select e.id, e.kind, e.display_title, e.status, e.test, v.name, e.language,
           s.tmdb_id, s.details_from, s.fetched_at,
           (select count(*) from public.items i where i.edition_id = e.id),
           (select count(*) from public.items i
            where i.edition_id = e.id and exists (
              select from public.media_originals o
              where o.item_id = i.id and o.state = 'ready'))
    from public.editions e
    left join public.sources s on s.id = e.source_id
    left join public.vjs v on v.id = e.vj_id
"""


def find_edition(conn: psycopg.Connection, key: str) -> Edition:
    try:
        edition_id = uuid.UUID(key)
    except ValueError:
        raise CatalogueError(f"{key!r} isn't an edition ID. See `list`") from None
    row = conn.execute(_EDITION + " where e.id = %s", (edition_id,)).fetchone()
    if row is None:
        raise CatalogueError(f"No edition {key}. See `list`")
    return Edition(*row)


def list_editions(conn: psycopg.Connection) -> list[Edition]:
    rows = conn.execute(
        _EDITION
        + """
        order by e.status = 'published' desc, e.published_at desc nulls last,
                 e.created_at desc
        """
    ).fetchall()
    return [Edition(*row) for row in rows]


@dataclass
class RefreshResult:
    refreshed: int = 0
    up_to_date: int = 0
    deleted: int = 0
    failed: list[str] | None = None


def refresh(
    conn: psycopg.Connection,
    fetch: Callable[[str, int], MovieDetails],
    now: datetime | None = None,
) -> RefreshResult:
    """Fetches TMDB copies of sources, movies and series, older than
    REFRESH_AFTER. `fetch` takes the kind and TMDB ID. A copy that can't be
    fetched is kept until DELETE_AFTER; then it is cleared, and its editions
    are hidden.

    Stops at the first refused token, because every other fetch would fail
    the same way.
    """
    now = now or datetime.now(UTC)
    result = RefreshResult(failed=[])
    rows = conn.execute(
        """
        select kind, tmdb_id, fetched_at from public.sources
        where details_from = 'tmdb'
        order by kind, tmdb_id
        """
    ).fetchall()
    for kind, tmdb_id, fetched_at in rows:
        if fetched_at is not None and now - fetched_at < REFRESH_AFTER:
            result.up_to_date += 1
            continue
        try:
            save_details(conn, fetch(kind, tmdb_id), kind)
            result.refreshed += 1
            continue
        except TmdbRefused:
            raise
        except TmdbError as error:
            result.failed.append(f"{kind} {tmdb_id}: {error}")
        if fetched_at is not None and now - fetched_at >= DELETE_AFTER:
            result.deleted += expire_copy(conn, tmdb_id, kind)
    return result


def expire_copy(conn: psycopg.Connection, tmdb_id: int, kind: str = "movie") -> int:
    """Clears a TMDB copy past TMDB's limit, and hides what shows it. The
    source keeps its TMDB ID, so a later refresh can fill it again."""
    conn.execute(
        """
        update public.editions set status = 'hidden', updated_at = now()
        where status = 'published' and source_id in (
          select id from public.sources where kind = %s and tmdb_id = %s)
        """,
        (kind, tmdb_id),
    )
    return conn.execute(
        """
        update public.sources set overview = null, original_title = null,
          release_date = null, runtime_minutes = null, genres = '{}',
          poster_path = null, backdrop_path = null, trailer_key = null,
          tmdb_rating = null, tmdb_vote_count = null, tmdb_popularity = null,
          rating_updated_at = null,
          fetched_at = null
        where kind = %s and tmdb_id = %s
        """,
        (kind, tmdb_id),
    ).rowcount


def purge_tmdb(conn: psycopg.Connection) -> int:
    """Clears every TMDB copy, and hides every edition that shows one.
    Typed-in details stay."""
    conn.execute(
        """
        update public.editions set status = 'hidden', updated_at = now()
        where status = 'published' and source_id in (
          select id from public.sources where details_from = 'tmdb')
        """
    )
    return conn.execute(
        """
        update public.sources set overview = null, original_title = null,
          release_date = null, runtime_minutes = null, genres = '{}',
          poster_path = null, backdrop_path = null, trailer_key = null,
          tmdb_rating = null, tmdb_vote_count = null, tmdb_popularity = null,
          rating_updated_at = null,
          fetched_at = null
        where details_from = 'tmdb'
        """
    ).rowcount


def add_admin(
    conn: psycopg.Connection, user_id: str, email: str | None = None
) -> uuid.UUID:
    try:
        parsed = uuid.UUID(user_id)
    except ValueError:
        raise CatalogueError(
            f"{user_id!r} isn't a user ID. It is the long ID Neon Auth gives "
            "each user, shown in the Neon Console under Auth, Users"
        ) from None
    email = (email or "").strip() or None
    if email is not None and ("@" not in email or len(email) > 320):
        raise CatalogueError(f"{email!r} isn't an email address")
    added = conn.execute(
        """
        insert into public.admins (user_id, email) values (%s, %s)
        on conflict (user_id) do nothing
        """,
        (parsed, email),
    ).rowcount
    if not added:
        raise CatalogueError("That user is already an admin")
    return parsed


def remove_admin(conn: psycopg.Connection, user_id: str) -> None:
    try:
        parsed = uuid.UUID(user_id)
    except ValueError:
        raise CatalogueError(f"{user_id!r} isn't a user ID") from None
    try:
        with conn.transaction():
            removed = conn.execute(
                "delete from public.admins where user_id = %s", (parsed,)
            ).rowcount
    except psycopg.errors.CheckViolation:
        raise CatalogueError(
            "That is the last admin. Add another first, then remove this one"
        ) from None
    if not removed:
        raise CatalogueError("That user isn't an admin")


def list_admins(conn: psycopg.Connection) -> list[tuple]:
    return conn.execute(
        "select user_id, email, added_by, added_at from public.admins order by added_at"
    ).fetchall()


# --- The command line --------------------------------------------------------


def _age(fetched_at: datetime | None, now: datetime) -> str:
    if fetched_at is None:
        return "no TMDB copy"
    days = (now - fetched_at).days
    return "fetched today" if days == 0 else f"fetched {days} days ago"


def describe_edition(edition: Edition, now: datetime | None = None) -> str:
    now = now or datetime.now(UTC)
    who = "test film" if edition.test else (edition.vj or "no VJ yet")
    if edition.details_from == "tmdb":
        details = f"TMDB {edition.tmdb_id}, {_age(edition.fetched_at, now)}"
    elif edition.details_from == "manual":
        details = "details typed in"
    else:
        details = "no details yet"
    videos = (
        f"{edition.ready} of {plural(edition.items, 'episode', 'episodes')} ready"
        if edition.kind == "series"
        else ("video ready" if edition.ready else "no video yet")
    )
    return (
        f"{edition.title}  {edition.kind}  {edition.status}  {who}  "
        f"{edition.language}  {details}  {videos}  id {edition.id}"
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


# The connection string in use, so failure messages can mask its password.
_url = ""


def connect() -> psycopg.Connection:
    """The owner's connection, after checking it is the right database."""
    global _url
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
        _url = url
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


def failure_message(error: psycopg.Error, url: str) -> str:
    """What went wrong after connecting: the error's type, its SQLSTATE code
    and Postgres's whole message on one line, with the password masked."""
    code = f" {error.sqlstate}" if error.sqlstate else ""
    message = " ".join(line.strip() for line in str(error).splitlines() if line.strip())
    password = urlsplit(url).password
    for secret in {password, unquote(password or "")} - {None, ""}:
        message = message.replace(secret, "<hidden>")
    return f"{type(error).__name__}{code}: {message[:300]}"


def run(args: argparse.Namespace) -> int:
    if args.command == "draft":
        with connect() as conn:
            try:
                if args.kind == "episode" and not args.series:
                    raise CatalogueError(
                        "Name the series edition with --series. For a new "
                        "series, use `draft series` with its first episode"
                    )
                if args.kind == "series" and args.series:
                    raise CatalogueError(
                        "`draft series` starts a new series. For another "
                        "episode of one, use `draft episode`"
                    )
                if args.kind in ("series", "episode"):
                    draft = editions.create_draft(
                        conn,
                        kind="series",
                        title=args.title,
                        year=args.year,
                        language=args.language,
                        series_edition=args.series,
                        season=args.season,
                        episode=args.episode,
                    )
                else:
                    draft = editions.create_draft(
                        conn,
                        kind=args.kind,
                        title=args.title,
                        year=args.year,
                        language=args.language,
                    )
            except editions.EditionError as error:
                raise CatalogueError(str(error)) from None
            conn.commit()
        print(f"Draft edition {draft.edition_id}, item {draft.item_id}.")
        print(
            "Make its upload key with: scripts\\catalogue.py grant-upload "
            f"{draft.item_id} --for <who>"
        )
        return 0

    if args.command in ("publish", "unpublish"):
        with connect() as conn:
            changed = []
            for key in dict.fromkeys(args.editions):
                edition = find_edition(conn, key)
                try:
                    if args.command == "publish":
                        editions.publish(conn, edition.id)
                    else:
                        editions.hide(conn, edition.id)
                except editions.EditionError as error:
                    raise CatalogueError(f"{edition.title}: {error}") from None
                changed.append(edition.id)
            # One commit: all change, or none.
            conn.commit()
            for edition_id in changed:
                print(describe_edition(find_edition(conn, str(edition_id))))
        return 0

    if args.command == "list":
        with connect() as conn:
            found = list_editions(conn)
        for edition in found:
            print(describe_edition(edition))
        published = sum(edition.status == "published" for edition in found)
        print(f"\n{plural(len(found), 'edition', 'editions')}, {published} published")
        return 0

    if args.command == "refresh":
        with tmdb_client() as client, connect() as conn:
            result = refresh(conn, client.details)
            conn.commit()
        print(
            f"{result.refreshed} refreshed, {result.up_to_date} already up to "
            f"date, {plural(result.deleted, 'expired copy', 'expired copies')} "
            "cleared"
        )
        for failure in result.failed or []:
            print(f"Failed: {failure}")
        return 1 if result.failed else 0

    if args.command == "grant-upload":
        with connect() as conn:
            try:
                item_id = editions.find_item(conn, args.item)
            except editions.EditionError as error:
                raise CatalogueError(str(error)) from None
            title, season, episode = conn.execute(
                """
                select e.display_title, i.season, i.episode
                from public.items i join public.editions e on e.id = i.edition_id
                where i.id = %s
                """,
                (item_id,),
            ).fetchone()
            key, text = grant_upload(conn, item_id, args.label, args.days)
            conn.commit()
        print(
            f"Upload key for {key.label}: one file for "
            f"{item_name(title, season, episode)}, "
            f"until {key.expires_at:%d %B %Y %H:%M} UTC."
        )
        print("It is shown only this once:")
        print(f"\n    {text}\n")
        print(
            "Send it privately. Anyone who has it can upload one file for this. "
            "To stop it:"
        )
        print(f"    scripts\\catalogue.py revoke-upload {key.id}")
        return 0

    if args.command == "revoke-upload":
        with connect() as conn:
            key = revoke_upload(conn, args.key_id)
            conn.commit()
        if key.used_at:
            print(
                f"Key for {key.label} revoked, but it was already used. "
                "Its upload isn't stopped."
            )
        else:
            print(f"Key for {key.label} revoked. It can't be used now.")
        return 0

    if args.command == "uploads":
        with connect() as conn:
            only = None
            if args.edition:
                try:
                    only = uuid.UUID(args.edition)
                except ValueError:
                    raise CatalogueError(
                        f"{args.edition!r} isn't an edition or item ID"
                    ) from None
            items = list_uploads(conn, only)
        if not items:
            print("No upload keys yet. Make one with grant-upload.")
        for item in items:
            print("\n".join(describe_uploads(item)))
        return 0

    if args.command == "remove-original":
        with connect() as conn:
            if not typed(
                "Remove this original and every quality made from it? Viewers "
                "lose it if it is the one being shown.",
                "remove",
            ):
                print("Nothing changed.")
                return 1
            was = request_removal(conn, args.original_id)
            conn.commit()
        print(
            f"The original, {was} until now, is marked for removal. The media "
            "worker deletes its files from R2 and marks it removed."
        )
        return 0

    if args.command == "purge-tmdb":
        with connect() as conn:
            if not typed(
                "Clear every TMDB copy and hide every edition that shows one?",
                "purge",
            ):
                print("Nothing changed.")
                return 1
            cleared = purge_tmdb(conn)
            conn.commit()
        print(
            f"{plural(cleared, 'TMDB copy', 'TMDB copies')} cleared. "
            "Editions showing them are hidden."
        )
        return 0

    if args.command == "admin":
        with connect() as conn:
            if args.action == "add":
                add_admin(conn, args.user_id, args.email)
                conn.commit()
                print("Added. They see Admin in the app once they sign in again.")
            elif args.action == "remove":
                remove_admin(conn, args.user_id)
                conn.commit()
                print("Removed.")
            else:
                admins = list_admins(conn)
                for user_id, email, added_by, added_at in admins:
                    by = f"by {added_by}" if added_by else "from the terminal"
                    print(
                        f"{email or '(no email)'}  user {user_id}  added "
                        f"{added_at:%d %b %Y} {by}"
                    )
                print(plural(len(admins), "admin", "admins"))
        return 0

    if args.command == "delete-test-films":
        with connect() as conn:
            if not typed(
                "Delete the films from before Milestone 9, with their videos "
                "in R2? Their links stop working.",
                "delete",
            ):
                print("Nothing changed.")
                return 1
            done = editions.delete_test_films(conn)
            conn.commit()
        if not done.editions:
            print("There are no test films.")
        elif done.deleted:
            print(f"{plural(done.editions, 'test film', 'test films')} deleted.")
        else:
            print(
                f"{plural(done.editions, 'test film', 'test films')} hidden, and "
                f"{plural(done.still_removing, 'video', 'videos')} being removed "
                "from R2 by the media worker. Run this again once `uploads` "
                "shows them removed, to delete the films."
            )
        return 0

    raise AssertionError(args.command)


def parser() -> argparse.ArgumentParser:
    main_parser = argparse.ArgumentParser(description="Manage VeloraUG's catalogue.")
    commands = main_parser.add_subparsers(dest="command", required=True)
    draft = commands.add_parser(
        "draft", help="start a draft: a movie, a new series, or an episode"
    )
    draft.add_argument("kind", choices=("movie", "series", "episode"))
    draft.add_argument(
        "title", nargs="?", help="as submitted; not needed for an episode"
    )
    draft.add_argument("--year", type=int)
    draft.add_argument("--language", default=editions.DEFAULT_LANGUAGE)
    draft.add_argument("--series", help="for an episode: the series edition's ID")
    draft.add_argument("--season", type=int)
    draft.add_argument("--episode", type=int)
    for name, text in (("publish", "show"), ("unpublish", "hide")):
        command = commands.add_parser(name, help=f"{text} editions in the app")
        command.add_argument("editions", nargs="+", metavar="edition")
    commands.add_parser("list", help="every edition, published or not")
    commands.add_parser("refresh", help="fetch TMDB copies older than 7 days")
    commands.add_parser("purge-tmdb", help="clear every TMDB copy")
    grant = commands.add_parser(
        "grant-upload", help="make a one-time key to upload one file"
    )
    grant.add_argument("item", help="an item ID, or a movie edition's ID")
    grant.add_argument(
        "--for", dest="label", required=True, help="who the key is for, e.g. Owner"
    )
    grant.add_argument(
        "--days", type=int, default=DEFAULT_DAYS, help="days until it expires"
    )
    revoke = commands.add_parser("revoke-upload", help="stop an upload key working")
    revoke.add_argument("key_id", help="the key ID that uploads shows")
    uploads = commands.add_parser("uploads", help="upload keys and their originals")
    uploads.add_argument(
        "edition", nargs="?", help="only this edition, or this one item"
    )
    remove = commands.add_parser(
        "remove-original", help="delete an original and its qualities from R2"
    )
    remove.add_argument("original_id", help="the original ID that uploads shows")
    admin = commands.add_parser("admin", help="add, remove or list admins")
    admin.add_argument("action", choices=("add", "remove", "list"))
    admin.add_argument("user_id", nargs="?", help="the user's Neon Auth ID")
    admin.add_argument("--email", help="their email, to show in the list")
    commands.add_parser(
        "delete-test-films", help="delete the films from before Milestone 9"
    )
    return main_parser


def main() -> int:
    args = parser().parse_args()
    if args.command == "admin" and args.action != "list" and not args.user_id:
        print("Give the user's ID", file=sys.stderr)
        return 2
    try:
        return run(args)
    except (
        CatalogueError,
        UploadKeyError,
        editions.EditionError,
        TmdbError,
        ValueError,
    ) as error:
        print(str(error), file=sys.stderr)
        return 1
    except psycopg.Error as error:
        print(f"Failed, nothing saved. {failure_message(error, _url)}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
