"""Migration and role-script checks that need no database."""

import subprocess
import sys
from pathlib import Path

import pytest

from migrations.connection import (
    UnsafeConnection,
    clean,
    describe,
    require_sign_in_branch,
    sqlalchemy_url,
)
from scripts.create_app_role import app_database_url, scram_verifier, write_env

API_DIR = Path(__file__).resolve().parent.parent
DIRECT = (
    "postgresql://neondb_owner:owner-pw@ep-floral-salad-b98b3l94.c-7"
    ".eu-central-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require"
)


def alembic(*args, env=None):
    return subprocess.run(
        [sys.executable, "-m", "alembic", *args],
        cwd=API_DIR,
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )


def test_the_migration_sql_can_be_read_without_a_database():
    result = alembic("upgrade", "head", "--sql")

    assert result.returncode == 0, result.stderr
    sql = result.stdout
    assert "create table public.profiles" in sql
    assert "force row level security" in sql
    assert "grant update (display_name) on table public.profiles" in sql
    assert "neon_auth." not in sql
    assert "alembic_version" in sql


def test_there_is_one_head():
    result = alembic("heads")

    assert result.returncode == 0, result.stderr
    assert result.stdout.split() == ["0001", "(head)"]


def test_a_pooled_address_is_refused_before_connecting(monkeypatch, tmp_path):
    import os

    env = {**os.environ}
    env["VELORAUG_MIGRATION_DATABASE_URL"] = DIRECT.replace(
        "b98b3l94.", "b98b3l94-pooler."
    )
    result = alembic("current", env=env)

    assert result.returncode != 0
    assert "pooled address" in result.stderr
    assert "owner-pw" not in result.stderr + result.stdout


AUTH_URL = (
    "https://ep-floral-salad-b98b3l94.neonauth.c-7.eu-central-1.aws.neon.tech"
    "/neondb/auth"
)
# The two wrong databases seen on 7 November: the old project in us-east-2,
# and another endpoint in the Frankfurt project.
OLD_PROJECT = (
    "postgresql://neondb_owner:pw@ep-twilight-breeze-be9id8hj.c-9.us-east-2"
    ".aws.neon.tech/neondb?sslmode=require"
)
OTHER_ENDPOINT = DIRECT.replace("ep-floral-salad-b98b3l94", "ep-wild-wave-b9l7rt06")


@pytest.fixture
def sign_in_branch(monkeypatch):
    monkeypatch.setenv("VELORAUG_NEON_AUTH_URL", AUTH_URL)


def test_the_sign_in_branch_with_neon_auth_is_accepted(sign_in_branch):
    assert "ep-floral-salad-b98b3l94" in require_sign_in_branch(DIRECT, 16)


def test_its_pooled_address_is_accepted_too(sign_in_branch):
    pooled = DIRECT.replace("b98b3l94.", "b98b3l94-pooler.")

    assert "Neon Auth found" in require_sign_in_branch(pooled, 16)


@pytest.mark.parametrize("url", [OLD_PROJECT, OTHER_ENDPOINT])
def test_another_project_or_branch_is_refused_even_with_neon_auth(sign_in_branch, url):
    with pytest.raises(UnsafeConnection, match="sign-in uses the branch"):
        require_sign_in_branch(url, 16)


def test_the_refusal_names_the_right_host(sign_in_branch):
    with pytest.raises(UnsafeConnection) as caught:
        require_sign_in_branch(OLD_PROJECT, 16)

    assert "ep-floral-salad-b98b3l94.c-7.eu-central-1.aws.neon.tech" in str(
        caught.value
    )
    assert "pw" not in str(caught.value).split()


def test_the_right_host_without_neon_auth_is_refused(sign_in_branch):
    with pytest.raises(UnsafeConnection, match="no neon_auth schema"):
        require_sign_in_branch(DIRECT, 0)


def test_a_neon_database_is_refused_when_sign_in_isnt_set():
    with pytest.raises(UnsafeConnection, match="VELORAUG_NEON_AUTH_URL"):
        require_sign_in_branch(DIRECT, 16)


def test_the_auth_url_can_come_from_the_env_file(monkeypatch, tmp_path):
    from migrations import connection

    env = tmp_path / ".env"
    env.write_text(f'VELORAUG_NEON_AUTH_URL="{AUTH_URL}"\n', encoding="utf-8")
    monkeypatch.setattr(connection, "ENV_FILE", env)

    assert "Neon Auth found" in require_sign_in_branch(DIRECT, 16)


def test_a_local_database_needs_no_neon_auth():
    assert "local" in require_sign_in_branch("postgresql://o:p@127.0.0.1/t", 0)


@pytest.mark.parametrize(
    "pasted",
    [
        DIRECT,
        f"  {DIRECT}  ",
        f"psql '{DIRECT}'",
        f'psql "{DIRECT}"',
        f"'{DIRECT}'",
    ],
)
def test_the_connection_string_is_found_in_what_was_pasted(pasted):
    assert clean(pasted) == DIRECT


@pytest.mark.parametrize("pasted", ["", "neondb_owner", "host=x user=y"])
def test_pasted_text_without_a_connection_string_is_refused(pasted):
    with pytest.raises(UnsafeConnection, match="postgresql://"):
        clean(pasted)


def test_describe_names_the_host_but_not_the_password():
    where = describe(DIRECT)

    assert "ep-floral-salad-b98b3l94.c-7.eu-central-1.aws.neon.tech" in where
    assert "neondb_owner" in where
    assert "owner-pw" not in where


@pytest.mark.parametrize(
    "url",
    [
        DIRECT.replace("b98b3l94.", "b98b3l94-pooler."),
        DIRECT.replace("neondb_owner", "veloraug_app"),
        "mysql://user:pw@host/db",
        "postgresql:///neondb",
    ],
)
def test_unsafe_migration_connections_are_refused(url):
    with pytest.raises(UnsafeConnection):
        describe(url)


def test_the_psycopg_driver_is_used():
    assert sqlalchemy_url(DIRECT).startswith("postgresql+psycopg://")
    assert sqlalchemy_url("postgres://u@h/d") == "postgresql+psycopg://u@h/d"


def test_the_app_url_uses_the_pooler_and_keeps_tls():
    url = app_database_url(DIRECT, "app-pw")

    assert url == (
        "postgresql://veloraug_app:app-pw@ep-floral-salad-b98b3l94-pooler.c-7"
        ".eu-central-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require"
    )


def test_the_app_url_for_a_local_database_keeps_the_host_and_port():
    url = app_database_url("postgresql://o:p@127.0.0.1:55432/test", "pw")

    assert url == "postgresql://veloraug_app:pw@127.0.0.1:55432/test"


def test_write_env_replaces_only_the_database_line(tmp_path):
    env = tmp_path / ".env"
    env.write_text(
        '# comment\nVELORAUG_API_RESOURCE=x\nVELORAUG_DATABASE_URL="old"\n',
        encoding="utf-8",
    )

    write_env(env, "postgresql://new")

    assert env.read_text(encoding="utf-8") == (
        "# comment\nVELORAUG_API_RESOURCE=x\nVELORAUG_DATABASE_URL=postgresql://new\n"
    )


def test_write_env_adds_the_line_when_missing(tmp_path):
    env = tmp_path / ".env"
    env.write_text("VELORAUG_API_RESOURCE=x\n", encoding="utf-8")

    write_env(env, "postgresql://new")

    assert env.read_text(encoding="utf-8").endswith(
        "VELORAUG_DATABASE_URL=postgresql://new\n"
    )


def test_the_scram_hash_has_postgres_format_and_hides_the_password():
    verifier = scram_verifier("a-password", salt=b"0123456789abcdef")

    assert verifier.startswith("SCRAM-SHA-256$4096:MDEyMzQ1Njc4OWFiY2RlZg==$")
    assert "a-password" not in verifier
