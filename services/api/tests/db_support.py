"""Shared setup for the tests that need a real Postgres.

They run against a throwaway local Postgres, never Neon. Start one and point
VELORAUG_TEST_ADMIN_URL at it, as "Run the checks" in README.md shows.
Without it, those tests are skipped. The fixtures that use these helpers,
owner_url and app_url, are in conftest.py.

The setup copies Neon's arrangement: migrations run as a database owner with
CREATEROLE and BYPASSRLS, not a superuser, and a neon_auth schema exists that
veloraug_app must not read.
"""

import os
import uuid
from pathlib import Path
from urllib.parse import urlsplit

import psycopg
import pytest

ADMIN_URL = os.environ.get("VELORAUG_TEST_ADMIN_URL", "")
needs_database = pytest.mark.skipif(
    not ADMIN_URL,
    reason="needs a local test Postgres: set VELORAUG_TEST_ADMIN_URL (README)",
)

API_DIR = Path(__file__).resolve().parent.parent
DATABASE = "veloraug_test"
OWNER = "veloraug_test_owner"
OWNER_PASSWORD = "local-test-owner-password"
APP_PASSWORD = "local-test-app-password"
MEDIA_PASSWORD = "local-test-media-password"


def url_for(user: str, password: str, database: str = DATABASE) -> str:
    parts = urlsplit(ADMIN_URL)
    return f"postgresql://{user}:{password}@{parts.hostname}:{parts.port}/{database}"


def admin_credentials():
    parts = urlsplit(ADMIN_URL)
    return parts.username, parts.password


def owner_query(owner_url, query, params=()):
    with psycopg.connect(owner_url) as conn:
        return conn.execute(query, params).fetchall()


def create_test_database() -> str:
    """A fresh veloraug_test database, set up as Neon is. Its owner's URL."""
    with psycopg.connect(ADMIN_URL, autocommit=True) as admin:
        admin.execute(f"drop database if exists {DATABASE} with (force)")
        admin.execute("drop role if exists veloraug_app")
        admin.execute("drop role if exists veloraug_media")
        admin.execute("drop role if exists veloraug_editor")
        admin.execute(f"drop role if exists {OWNER}")
        admin.execute(
            """
            do $$ begin
              if not exists (select from pg_roles where rolname = 'neon_superuser')
              then create role neon_superuser nologin;
              end if;
            end $$
            """
        )
        admin.execute(
            f"create role {OWNER} login createrole bypassrls "
            f"password '{OWNER_PASSWORD}' in role neon_superuser"
        )
        admin.execute(f"create database {DATABASE} owner {OWNER}")
    with psycopg.connect(url_for(*admin_credentials(), DATABASE)) as admin_db:
        admin_db.execute("create schema neon_auth")
        admin_db.execute("create table neon_auth.users_sync (id text, email text)")
        admin_db.execute("insert into neon_auth.users_sync values ('1', 'a@b.test')")
        # As Neon Auth (Better Auth) keeps its users, with the columns
        # migration 0005's verified_user_id reads.
        admin_db.execute(
            """
            create table neon_auth."user" (
              id uuid primary key default gen_random_uuid(),
              email text not null unique,
              "emailVerified" boolean not null,
              banned boolean
            )
            """
        )
        admin_db.execute(f"grant usage on schema neon_auth to {OWNER}")
        admin_db.execute(f'grant select on neon_auth."user" to {OWNER}')
    return url_for(OWNER, OWNER_PASSWORD)


def migrate(owner_url: str, revision: str = "head", *, down: bool = False) -> None:
    from alembic import command
    from alembic.config import Config

    config = Config(str(API_DIR / "alembic.ini"))
    previous = os.environ.get("VELORAUG_MIGRATION_DATABASE_URL")
    os.environ["VELORAUG_MIGRATION_DATABASE_URL"] = owner_url
    try:
        if down:
            command.downgrade(config, revision)
        else:
            command.upgrade(config, revision)
    finally:
        if previous is None:
            os.environ.pop("VELORAUG_MIGRATION_DATABASE_URL", None)
        else:
            os.environ["VELORAUG_MIGRATION_DATABASE_URL"] = previous


# --- Catalogue rows, made as the owner. The caller commits. ------------------


def new_item(conn, kind: str = "movie", title: str = "A draft") -> uuid.UUID:
    """A draft edition with one item: what an upload key and an original
    need. Its ID is the item's."""
    from app.editions import create_draft

    if kind == "movie":
        return create_draft(conn, kind="movie", title=title).item_id
    return create_draft(conn, kind="series", title=title, season=1, episode=1).item_id


def add_movie(conn, details) -> uuid.UUID:
    """A film as migration 0005 moves one from before Milestone 9: a TMDB
    source, a test edition and an item with the same ID, hidden. Returns
    that ID."""
    film = uuid.uuid4()
    (source,) = conn.execute(
        """
        insert into public.sources (kind, tmdb_id, title, original_title, overview,
          release_date, runtime_minutes, genres, poster_path, backdrop_path,
          details_from, fetched_at)
        values ('movie', %s, %s, %s, %s, %s, %s, %s, %s, %s, 'tmdb', now())
        returning id
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
    ).fetchone()
    conn.execute(
        """
        insert into public.editions (id, kind, source_id, display_title, status,
          test, tmdb_lookup)
        values (%s, 'movie', %s, %s, 'hidden', true, 'chosen')
        """,
        (film, source, details.title),
    )
    conn.execute(
        "insert into public.items (id, edition_id, kind, approved_at) "
        "values (%s, %s, 'movie', now())",
        (film, film),
    )
    return film


def film_id(conn, key: str) -> uuid.UUID:
    """A film from add_movie, by its ID or its TMDB ID."""
    try:
        return uuid.UUID(key)
    except ValueError:
        return conn.execute(
            "select e.id from public.editions e join public.sources s "
            "on s.id = e.source_id where s.tmdb_id = %s and e.test",
            (int(key),),
        ).fetchone()[0]


def set_published(conn, key: str, published: bool) -> uuid.UUID:
    """Shows or hides a film from add_movie, named by its ID or TMDB ID."""
    film = film_id(conn, key)
    conn.execute(
        """
        update public.editions
        set status = case when %s then 'published' else 'hidden' end,
            published_at = case when %s then coalesce(published_at, now()) end
        where id = %s
        """,
        (published, published, film),
    )
    return film


def clear_admins(conn) -> None:
    """Empties public.admins between tests. Only the table's owner can turn
    off the rule that keeps one admin, and only for this."""
    conn.execute("alter table public.admins disable trigger admins_keep_one")
    conn.execute("delete from public.admins")
    conn.execute("alter table public.admins enable trigger admins_keep_one")


def delete_editions(conn, where: str = "true", params=()) -> None:
    """Deletes editions, with their items, keys, originals and sources."""
    editions = f"select id from public.editions where {where}"
    items = f"select id from public.items where edition_id in ({editions})"
    originals = f"select id from public.media_originals where item_id in ({items})"
    conn.execute(
        f"delete from public.media_renditions where original_id in ({originals})",
        params,
    )
    conn.execute(
        f"delete from public.media_originals where id in ({originals})", params
    )
    conn.execute(f"delete from public.upload_keys where item_id in ({items})", params)
    sources = [
        row[0]
        for row in conn.execute(
            f"select source_id from public.editions where id in ({editions})", params
        ).fetchall()
    ]
    conn.execute(f"delete from public.items where id in ({items})", params)
    conn.execute(f"delete from public.editions where id in ({editions})", params)
    conn.execute(
        "delete from public.sources s where s.id = any(%s) and not exists "
        "(select from public.editions e where e.source_id = s.id)",
        ([s for s in sources if s],),
    )
