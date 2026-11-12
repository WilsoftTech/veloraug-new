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
