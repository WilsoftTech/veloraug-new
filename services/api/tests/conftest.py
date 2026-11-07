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
