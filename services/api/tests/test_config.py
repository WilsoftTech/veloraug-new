import pytest
from pydantic import ValidationError

from app.config import Settings


def test_defaults_suit_local_development():
    settings = Settings()

    assert settings.environment == "development"
    assert settings.allowed_origins == ["http://localhost:8765"]


def test_settings_are_read_from_environment_variables(monkeypatch):
    monkeypatch.setenv("VELORAUG_ENVIRONMENT", "production")
    monkeypatch.setenv("VELORAUG_ALLOWED_ORIGINS", '["https://app.example"]')

    settings = Settings()

    assert settings.environment == "production"
    assert settings.allowed_origins == ["https://app.example"]


def test_unknown_environment_is_rejected():
    with pytest.raises(ValidationError):
        Settings(environment="staging")


@pytest.mark.parametrize(
    "origin",
    [
        "*",
        "https://*.example.com",
        "http://localhost:8765/",
        "http://localhost:8765/app",
        "localhost:8765",
        "ftp://localhost:8765",
    ],
)
def test_inexact_origins_are_rejected(origin):
    with pytest.raises(ValidationError):
        Settings(allowed_origins=[origin])


def test_dotenv_file_is_not_loaded(tmp_path, monkeypatch):
    (tmp_path / ".env").write_text("VELORAUG_ENVIRONMENT=production\n")
    monkeypatch.chdir(tmp_path)

    assert Settings().environment == "development"
