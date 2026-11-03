import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture(autouse=True)
def clear_veloraug_environment(monkeypatch):
    """Stop settings on the developer's machine from changing test results."""
    monkeypatch.delenv("VELORAUG_ENVIRONMENT", raising=False)
    monkeypatch.delenv("VELORAUG_ALLOWED_ORIGINS", raising=False)


@pytest.fixture
def client():
    return TestClient(create_app())
