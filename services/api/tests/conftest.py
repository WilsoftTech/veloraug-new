import psycopg
import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from migrations import connection

VELORAUG_SETTINGS = [
    "VELORAUG_ENVIRONMENT",
    "VELORAUG_ALLOWED_ORIGINS",
    "VELORAUG_NEON_AUTH_URL",
    "VELORAUG_API_RESOURCE",
    "VELORAUG_NEON_AUTH_CLIENT_IDS",
    "VELORAUG_DATABASE_URL",
    "VELORAUG_TMDB_READ_ACCESS_TOKEN",
]


@pytest.fixture(autouse=True)
def clear_veloraug_environment(monkeypatch, tmp_path):
    """Stop settings on the developer's machine from changing test results,
    including the real services/api/.env."""
    for name in VELORAUG_SETTINGS:
        monkeypatch.delenv(name, raising=False)
    monkeypatch.delenv("VELORAUG_MIGRATION_DATABASE_URL", raising=False)
    monkeypatch.setattr(connection, "ENV_FILE", tmp_path / "no.env")


@pytest.fixture
def client():
    return TestClient(create_app())


# --- A real Postgres, for the tests marked needs_database --------------------


@pytest.fixture(scope="session")
def owner_url():
    from tests.db_support import create_test_database

    return create_test_database()


@pytest.fixture(scope="session")
def app_url(owner_url):
    from scripts.create_app_role import ensure_app_role, role_problems
    from tests.db_support import APP_PASSWORD, migrate, url_for

    with psycopg.connect(owner_url) as conn:
        assert ensure_app_role(conn, APP_PASSWORD) is True
        assert role_problems(conn) == []
    migrate(owner_url)
    return url_for("veloraug_app", APP_PASSWORD)
