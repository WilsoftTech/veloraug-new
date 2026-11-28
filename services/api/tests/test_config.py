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
    monkeypatch.setenv("VELORAUG_PLAYBACK_SIGNING_KEY", "k" * 43)
    monkeypatch.setenv("VELORAUG_MEDIA_GATEWAY_URL", "https://media.example/")

    with pytest.raises(ValidationError, match="PASSES_REQUIRED"):
        Settings()
    monkeypatch.setenv("VELORAUG_PASSES_REQUIRED", "false")
    settings = Settings()

    assert settings.environment == "production"
    assert settings.allowed_origins == ["https://app.example"]
    assert settings.neon_auth_url == ISSUER
    assert settings.neon_auth_client_ids == ["web", "android"]
    assert settings.sign_in_configured
    assert settings.media_gateway_url == "https://media.example"
    assert settings.playback_configured


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


def test_the_tmdb_token_is_kept_secret(monkeypatch):
    monkeypatch.setenv("VELORAUG_TMDB_READ_ACCESS_TOKEN", "eyJ-tmdb-secret")

    settings = Settings()

    assert settings.tmdb_read_access_token.get_secret_value() == "eyJ-tmdb-secret"
    assert "tmdb-secret" not in repr(settings)
    assert "tmdb-secret" not in str(settings.model_dump())


def test_a_blank_tmdb_token_is_refused_without_quoting_it():
    with pytest.raises(ValidationError) as raised:
        Settings(tmdb_read_access_token="   ")

    assert "can't be blank" in str(raised.value)


def test_the_tmdb_token_is_optional():
    assert Settings().tmdb_read_access_token is None


# --- Pesapal and passes, Step 10B ---------------------------------------------


def test_passes_are_off_and_pesapal_unset_by_default():
    settings = Settings()

    assert settings.passes_required is False
    assert settings.pesapal_configured is False
    assert settings.pesapal_environment == "sandbox"


def test_pesapal_is_configured_with_its_keys_ipn_and_public_address():
    settings = Settings(
        pesapal_consumer_key="key",
        pesapal_consumer_secret="secret",
        pesapal_ipn_id="a1b2c3d4-0000-1111-2222-333344445555",
        public_api_url="https://api.example.com/",
    )

    assert settings.pesapal_configured is True
    assert settings.public_api_url == "https://api.example.com"


def test_register_ipn_needs_only_the_keys():
    settings = Settings(pesapal_consumer_key="key", pesapal_consumer_secret="secret")

    assert settings.pesapal_configured is False


@pytest.mark.parametrize(
    "given",
    [
        {"pesapal_consumer_key": "key"},
        {"pesapal_ipn_id": "a1b2c3d4-0000"},
        {
            "pesapal_consumer_key": "key",
            "pesapal_consumer_secret": "secret",
            "pesapal_ipn_id": "not an id!",
        },
        {"public_api_url": "http://api.example.com"},
        {"public_api_url": "https://api.example.com/api"},
        {"pesapal_environment": "test"},
    ],
)
def test_incomplete_or_unsafe_pesapal_settings_are_refused(given):
    with pytest.raises(ValidationError):
        Settings(**given)
