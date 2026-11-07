"""The migration, row-level security and the profile routes, on a real Postgres.

These run against a throwaway local Postgres, never Neon. Start one and point
VELORAUG_TEST_ADMIN_URL at it, as "Run the checks" in README.md shows.
Without it, these tests are skipped.

The setup copies Neon's arrangement: the migration runs as a database owner
with CREATEROLE and BYPASSRLS, not a superuser, and a neon_auth schema exists
that veloraug_app must not read.
"""

import logging
import os
import socket
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urlsplit

import psycopg
import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient

from app.auth import InvalidToken, VerifiedUser
from app.db import Database
from app.main import create_app
from migrations.connection import NEON_AUTH_TABLES
from scripts.check_database import run_checks
from scripts.create_app_role import ensure_app_role, role_problems

ADMIN_URL = os.environ.get("VELORAUG_TEST_ADMIN_URL", "")
pytestmark = pytest.mark.skipif(
    not ADMIN_URL,
    reason="needs a local test Postgres: set VELORAUG_TEST_ADMIN_URL (README)",
)

API_DIR = Path(__file__).resolve().parent.parent
DATABASE = "veloraug_test"
OWNER = "veloraug_test_owner"
OWNER_PASSWORD = "local-test-owner-password"
APP_PASSWORD = "local-test-app-password"


def url_for(user: str, password: str, database: str = DATABASE) -> str:
    parts = urlsplit(ADMIN_URL)
    return f"postgresql://{user}:{password}@{parts.hostname}:{parts.port}/{database}"


@pytest.fixture(scope="session")
def owner_url():
    with psycopg.connect(ADMIN_URL, autocommit=True) as admin:
        admin.execute(f"drop database if exists {DATABASE} with (force)")
        admin.execute("drop role if exists veloraug_app")
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
    with psycopg.connect(url_for(*_admin_credentials(), DATABASE)) as admin_db:
        admin_db.execute("create schema neon_auth")
        admin_db.execute("create table neon_auth.users_sync (id text, email text)")
        admin_db.execute("insert into neon_auth.users_sync values ('1', 'a@b.test')")
    return url_for(OWNER, OWNER_PASSWORD)


def _admin_credentials():
    parts = urlsplit(ADMIN_URL)
    return parts.username, parts.password


@pytest.fixture(scope="session")
def app_url(owner_url):
    with psycopg.connect(owner_url) as conn:
        assert ensure_app_role(conn, APP_PASSWORD) is True
        assert role_problems(conn) == []
    previous = os.environ.get("VELORAUG_MIGRATION_DATABASE_URL")
    os.environ["VELORAUG_MIGRATION_DATABASE_URL"] = owner_url
    try:
        command.upgrade(Config(str(API_DIR / "alembic.ini")), "head")
    finally:
        if previous is None:
            os.environ.pop("VELORAUG_MIGRATION_DATABASE_URL", None)
        else:
            os.environ["VELORAUG_MIGRATION_DATABASE_URL"] = previous
    return url_for("veloraug_app", APP_PASSWORD)


def owner_query(owner_url, query, params=()):
    with psycopg.connect(owner_url) as conn:
        return conn.execute(query, params).fetchall()


# --- The migration and the role ---------------------------------------------


def test_the_migration_is_at_head(owner_url, app_url):
    assert owner_query(owner_url, "select version_num from alembic_version") == [
        ("0001",)
    ]


def test_the_neon_auth_query_sees_the_schema_from_any_role(owner_url, app_url):
    for url in (owner_url, app_url):
        assert owner_query(url, NEON_AUTH_TABLES) == [(1,)]
    # A database without Neon Auth, like Neon's default branch.
    assert owner_query(ADMIN_URL, NEON_AUTH_TABLES) == [(0,)]


def test_every_database_check_passes(app_url):
    results = run_checks(app_url)

    failed = [f"{r.name} ({r.detail})" for r in results if not r.passed]
    assert failed == []
    assert len(results) >= 15


def test_the_role_script_changes_the_password(owner_url, app_url):
    with psycopg.connect(owner_url) as conn:
        assert ensure_app_role(conn, "a-new-password") is False

    with pytest.raises(psycopg.OperationalError):
        psycopg.connect(app_url).close()
    psycopg.connect(url_for("veloraug_app", "a-new-password")).close()

    with psycopg.connect(owner_url) as conn:
        ensure_app_role(conn, APP_PASSWORD)
    psycopg.connect(app_url).close()


def test_a_plain_password_works_too_as_neon_requires(owner_url, app_url):
    with psycopg.connect(owner_url) as conn:
        assert ensure_app_role(conn, "plain-password", plain=True) is False
        assert role_problems(conn) == []
    psycopg.connect(url_for("veloraug_app", "plain-password")).close()

    with psycopg.connect(owner_url) as conn:
        ensure_app_role(conn, APP_PASSWORD)
    psycopg.connect(app_url).close()


def test_the_password_never_reaches_the_database_in_plain_text(owner_url, app_url):
    stored = owner_query(
        url_for(*_admin_credentials(), DATABASE),
        "select rolpassword from pg_authid where rolname = 'veloraug_app'",
    )[0][0]

    assert stored.startswith("SCRAM-SHA-256$4096:")
    assert APP_PASSWORD not in stored


# --- The API, through real row-level security -------------------------------


class FakeVerifier:
    """The token is the user ID. TokenVerifier is covered in test_auth.py."""

    def verify(self, token: str) -> VerifiedUser:
        try:
            return VerifiedUser(user_id=uuid.UUID(token), client_id="web-client")
        except ValueError:
            raise InvalidToken("test") from None


@pytest.fixture
def api(app_url):
    app = create_app(token_verifier=FakeVerifier(), database=Database(app_url))
    with TestClient(app) as client:
        yield client


def as_user(user_id):
    return {"Authorization": f"Bearer {user_id}"}


def rows_for(owner_url, user_id):
    return owner_query(
        owner_url,
        "select display_name, created_at, updated_at from public.profiles "
        "where user_id = %s",
        (user_id,),
    )


def test_get_me_creates_exactly_one_profile(api, owner_url):
    user = uuid.uuid4()

    for _ in range(3):
        response = api.get("/api/v1/me", headers=as_user(user))
        assert response.status_code == 200
        assert response.json() == {"user_id": str(user), "display_name": None}

    assert len(rows_for(owner_url, user)) == 1


def test_simultaneous_first_requests_create_one_profile(api, owner_url):
    user = uuid.uuid4()

    with ThreadPoolExecutor(max_workers=8) as pool:
        statuses = list(
            pool.map(
                lambda _: api.get("/api/v1/me", headers=as_user(user)).status_code,
                range(8),
            )
        )

    assert statuses == [200] * 8
    assert len(rows_for(owner_url, user)) == 1


def test_the_display_name_can_be_set_and_cleared(api, owner_url):
    user = uuid.uuid4()
    # Created first, in its own transaction, so updated_at can move on.
    api.get("/api/v1/me", headers=as_user(user))

    response = api.patch(
        "/api/v1/me", headers=as_user(user), json={"display_name": "  Amara  "}
    )
    assert response.status_code == 200
    assert response.json() == {"user_id": str(user), "display_name": "Amara"}
    assert api.get("/api/v1/me", headers=as_user(user)).json()["display_name"] == (
        "Amara"
    )
    [(name, created, updated)] = rows_for(owner_url, user)
    assert updated > created

    response = api.patch(
        "/api/v1/me", headers=as_user(user), json={"display_name": None}
    )
    assert response.json()["display_name"] is None


@pytest.mark.parametrize(
    "body",
    [{}, {"display_name": ""}, {"display_name": "   "}, {"display_name": "x" * 81}],
)
def test_invalid_display_names_are_refused(api, body):
    response = api.patch("/api/v1/me", headers=as_user(uuid.uuid4()), json=body)

    assert response.status_code == 422


def test_eighty_characters_are_allowed(api):
    response = api.patch(
        "/api/v1/me", headers=as_user(uuid.uuid4()), json={"display_name": "é" * 80}
    )

    assert response.status_code == 200


def test_one_user_cant_read_or_change_another(api, owner_url):
    a, b = uuid.uuid4(), uuid.uuid4()
    api.patch("/api/v1/me", headers=as_user(b), json={"display_name": "B"})

    response = api.patch(
        "/api/v1/me",
        headers=as_user(a),
        json={"display_name": "A", "user_id": str(b)},
    )

    # The user ID in the body is ignored: A changed A's own profile.
    assert response.json() == {"user_id": str(a), "display_name": "A"}
    assert rows_for(owner_url, b)[0][0] == "B"
    assert api.get("/api/v1/me", headers=as_user(b)).json()["display_name"] == "B"


def test_without_a_token_nothing_is_read_or_written(api, owner_url):
    before = owner_query(owner_url, "select count(*) from public.profiles")

    assert api.get("/api/v1/me").status_code == 401
    assert api.patch("/api/v1/me", json={"display_name": "x"}).status_code == 401

    assert owner_query(owner_url, "select count(*) from public.profiles") == before


def test_an_unreachable_database_gives_503_without_secrets(caplog):
    caplog.set_level(logging.DEBUG)
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    url = f"postgresql://veloraug_app:SECRET-PASSWORD@127.0.0.1:{port}/nothing"
    app = create_app(
        token_verifier=FakeVerifier(), database=Database(url, wait_seconds=2)
    )

    with TestClient(app) as client:
        response = client.get("/api/v1/me", headers=as_user(uuid.uuid4()))

    assert response.status_code == 503
    assert "SECRET-PASSWORD" not in response.text
    assert "SECRET-PASSWORD" not in caplog.text


def test_health_still_needs_no_database():
    url = "postgresql://veloraug_app:pw@127.0.0.1:1/nothing"
    app = create_app(database=Database(url, wait_seconds=1))

    with TestClient(app) as client:
        assert client.get("/health").status_code == 200


# Last, because it changes the shared database and puts it back.
def test_the_migration_downgrades_and_upgrades_again(owner_url, app_url):
    config = Config(str(API_DIR / "alembic.ini"))
    os.environ["VELORAUG_MIGRATION_DATABASE_URL"] = owner_url
    try:
        command.downgrade(config, "base")
        assert owner_query(owner_url, "select to_regclass('public.profiles')") == [
            (None,)
        ]
        command.upgrade(config, "head")
    finally:
        os.environ.pop("VELORAUG_MIGRATION_DATABASE_URL", None)

    assert run_checks(app_url)[0].passed
