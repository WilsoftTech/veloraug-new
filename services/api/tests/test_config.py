import pytest
from pydantic import ValidationError

from app.config import Settings


def test_defaults_suit_local_development():
    settings = Settings()

    assert settings.environment == "development"
    assert settings.allowed_origins == ["http://localhost:8765"]


ISSUER = "https://auth.example.test/neondb/auth"
APP_DATABASE_URL = (
    "postgresql://veloraug_app:app-secret@ep-x-pooler.neon.tech/neondb?sslmode=require"
)
SIGN_IN = {
    "neon_auth_url": ISSUER,
    "api_resource": "https://api.example.invalid",
    "neon_auth_client_ids": ["web", "android"],
}


def test_settings_are_read_from_environment_variables(monkeypatch):
    monkeypatch.setenv("VELORAUG_ENVIRONMENT", "production")
    monkeypatch.setenv("VELORAUG_ALLOWED_ORIGINS", '["https://app.example"]')
    monkeypatch.setenv("VELORAUG_NEON_AUTH_URL", ISSUER)
    monkeypatch.setenv("VELORAUG_API_RESOURCE", "https://api.example.invalid")
    monkeypatch.setenv("VELORAUG_NEON_AUTH_CLIENT_IDS", '["web","android"]')
    monkeypatch.setenv("VELORAUG_DATABASE_URL", APP_DATABASE_URL)

    settings = Settings()

    assert settings.environment == "production"
    assert settings.allowed_origins == ["https://app.example"]
    assert settings.neon_auth_url == ISSUER
    assert settings.neon_auth_client_ids == ["web", "android"]
    assert settings.sign_in_configured


def test_production_refuses_to_start_without_the_database():
    with pytest.raises(ValidationError, match="VELORAUG_DATABASE_URL"):
        Settings(environment="production", **SIGN_IN)


def test_the_database_url_is_kept_secret():
    settings = Settings(database_url=APP_DATABASE_URL)

    assert settings.database_url.get_secret_value() == APP_DATABASE_URL
    assert "app-secret" not in repr(settings)
    assert "app-secret" not in str(settings.model_dump())


@pytest.mark.parametrize(
    "url",
    [
        "postgresql://neondb_owner:app-secret@ep-x-pooler.neon.tech/neondb",
        "postgresql://app-secret@ep-x-pooler.neon.tech/neondb",
        "mysql://veloraug_app:app-secret@host/db",
        "postgresql://veloraug_app:app-secret@/db",
    ],
)
def test_only_the_app_role_is_accepted_and_the_error_hides_the_url(url):
    with pytest.raises(ValidationError) as caught:
        Settings(database_url=url)

    assert "app-secret" not in str(caught.value)


def test_development_starts_without_sign_in_settings():
    assert not Settings().sign_in_configured


def test_empty_variables_count_as_unset(monkeypatch):
    for name in ["NEON_AUTH_URL", "API_RESOURCE", "NEON_AUTH_CLIENT_IDS"]:
        monkeypatch.setenv(f"VELORAUG_{name}", "")

    assert not Settings().sign_in_configured


def test_one_empty_sign_in_variable_is_reported(monkeypatch):
    monkeypatch.setenv("VELORAUG_NEON_AUTH_URL", ISSUER)
    monkeypatch.setenv("VELORAUG_API_RESOURCE", "https://api.example.invalid")
    monkeypatch.setenv("VELORAUG_NEON_AUTH_CLIENT_IDS", "")

    with pytest.raises(ValidationError, match="together"):
        Settings()


def test_production_refuses_to_start_without_sign_in_settings():
    with pytest.raises(ValidationError, match="Production needs"):
        Settings(environment="production")


@pytest.mark.parametrize("missing", list(SIGN_IN))
def test_sign_in_settings_must_be_given_together(missing):
    partial = {name: value for name, value in SIGN_IN.items() if name != missing}

    with pytest.raises(ValidationError, match="together"):
        Settings(**partial)


@pytest.mark.parametrize(
    "url",
    [
        "http://auth.example.test/neondb/auth",
        "https://auth.example.test/neondb/auth/",
        "https://auth.example.test/neondb/auth?x=1",
        "auth.example.test/neondb/auth",
    ],
)
def test_inexact_auth_urls_are_rejected(url):
    with pytest.raises(ValidationError):
        Settings(**{**SIGN_IN, "neon_auth_url": url})


def test_empty_client_ids_are_rejected():
    with pytest.raises(ValidationError):
        Settings(**{**SIGN_IN, "neon_auth_client_ids": ["web", " "]})


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
