from typing import Literal
from urllib.parse import unquote, urlsplit

from pydantic import SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed settings, read from VELORAUG_* environment variables.

    A .env file is not loaded, because no env_file is configured here. Under
    Docker Compose, Compose passes the file's values as environment variables.
    """

    # An empty variable, such as KEY="" in a Compose env file, counts as unset.
    # Errors never quote a value, because the database URL holds a password.
    model_config = SettingsConfigDict(
        env_prefix="VELORAUG_", env_ignore_empty=True, hide_input_in_errors=True
    )

    environment: Literal["development", "production"] = "development"
    allowed_origins: list[str] = ["http://localhost:8765"]

    # Sign-in. None of these is secret. All three are needed together.
    neon_auth_url: str | None = None
    api_resource: str | None = None
    neon_auth_client_ids: list[str] = []

    # Secret. The pooled connection as veloraug_app. SecretStr keeps it out of
    # reprs, logs and error messages.
    database_url: SecretStr | None = None

    # Secret. veloraug_editor's pooled connection string, for the admin
    # routes, Step 9C. Without it, they answer 503.
    editor_database_url: SecretStr | None = None

    # Secret. TMDB's read access token, for refreshing movie details. Without
    # it, the catalogue serves the details it already has.
    tmdb_read_access_token: SecretStr | None = None

    # Playback, Step 8B. Both or neither. The key is secret, and shared with
    # the Worker in services/media_gateway/. The gateway's address isn't.
    playback_signing_key: SecretStr | None = None
    media_gateway_url: str | None = None

    @field_validator("allowed_origins")
    @classmethod
    def require_exact_origins(cls, origins: list[str]) -> list[str]:
        # Browsers send an origin as scheme://host[:port]. Anything else, such
        # as a trailing slash, would never match. Wildcards are not allowed.
        for origin in origins:
            parts = urlsplit(origin)
            is_exact = (
                parts.scheme in ("http", "https")
                and parts.netloc
                and "*" not in origin
                and not (parts.path or parts.query or parts.fragment)
            )
            if not is_exact:
                raise ValueError(
                    f"{origin!r} must look like http://host:port, with no "
                    "wildcard or path"
                )
        return origins

    @field_validator("neon_auth_url")
    @classmethod
    def require_https_issuer(cls, url: str | None) -> str | None:
        # Tokens are checked for an exact issuer match, so a trailing slash or
        # a missing path would refuse every real token.
        if url is None:
            return None
        parts = urlsplit(url)
        if (
            parts.scheme != "https"
            or not parts.netloc
            or url.endswith("/")
            or parts.query
            or parts.fragment
        ):
            raise ValueError(
                "neon_auth_url must be the exact https Auth URL from the Neon "
                "Console, with no trailing slash"
            )
        return url

    @field_validator("api_resource")
    @classmethod
    def require_resource(cls, resource: str | None) -> str | None:
        if resource is not None and not resource.strip():
            raise ValueError("api_resource can't be empty")
        return resource

    @field_validator("neon_auth_client_ids")
    @classmethod
    def require_client_ids(cls, client_ids: list[str]) -> list[str]:
        if any(not client_id.strip() for client_id in client_ids):
            raise ValueError("neon_auth_client_ids can't contain an empty ID")
        return client_ids

    @field_validator("database_url")
    @classmethod
    def require_app_role(cls, url: SecretStr | None) -> SecretStr | None:
        # The messages never quote the value: it holds a password.
        if url is None:
            return None
        parts = urlsplit(url.get_secret_value())
        if parts.scheme not in ("postgresql", "postgres") or not parts.hostname:
            raise ValueError("database_url must be a postgresql:// connection string")
        if unquote(parts.username or "") != "veloraug_app":
            raise ValueError(
                "database_url must use the veloraug_app role. The owner role "
                "bypasses row-level security"
            )
        return url

    @field_validator("editor_database_url")
    @classmethod
    def require_editor_role(cls, url: SecretStr | None) -> SecretStr | None:
        # The messages never quote the value: it holds a password.
        if url is None:
            return None
        parts = urlsplit(url.get_secret_value())
        if parts.scheme not in ("postgresql", "postgres") or not parts.hostname:
            raise ValueError(
                "editor_database_url must be a postgresql:// connection string"
            )
        if unquote(parts.username or "") != "veloraug_editor":
            raise ValueError("editor_database_url must use the veloraug_editor role")
        return url

    @field_validator("tmdb_read_access_token")
    @classmethod
    def require_token(cls, token: SecretStr | None) -> SecretStr | None:
        # The message never quotes the value.
        if token is not None and not token.get_secret_value().strip():
            raise ValueError("tmdb_read_access_token can't be blank")
        return token

    @field_validator("playback_signing_key")
    @classmethod
    def require_long_key(cls, key: SecretStr | None) -> SecretStr | None:
        # The message never quotes the value.
        if key is not None and len(key.get_secret_value().strip()) < 32:
            raise ValueError(
                "playback_signing_key must be at least 32 characters. Make one "
                'with: python -c "import secrets; print(secrets.token_urlsafe(32))"'
            )
        return key

    @field_validator("media_gateway_url")
    @classmethod
    def require_gateway_origin(cls, url: str | None) -> str | None:
        if url is None:
            return None
        parts = urlsplit(url)
        loopback = parts.hostname in ("127.0.0.1", "localhost")
        if (
            not parts.hostname
            or parts.scheme not in ("http", "https")
            or (parts.scheme == "http" and not loopback)
            or parts.path not in ("", "/")
            or parts.query
            or parts.fragment
            or parts.username
        ):
            raise ValueError(
                "media_gateway_url must look like https://host, with no path. "
                "Plain http is allowed for 127.0.0.1 and localhost only"
            )
        return url.rstrip("/")

    @property
    def playback_configured(self) -> bool:
        return (
            self.playback_signing_key is not None and self.media_gateway_url is not None
        )

    @property
    def sign_in_configured(self) -> bool:
        return bool(
            self.neon_auth_url and self.api_resource and self.neon_auth_client_ids
        )

    @model_validator(mode="after")
    def require_complete_sign_in(self) -> "Settings":
        given = [
            self.neon_auth_url is not None,
            self.api_resource is not None,
            bool(self.neon_auth_client_ids),
        ]
        if any(given) and not all(given):
            raise ValueError(
                "Set VELORAUG_NEON_AUTH_URL, VELORAUG_API_RESOURCE and "
                "VELORAUG_NEON_AUTH_CLIENT_IDS together, or none of them"
            )
        if self.environment == "production" and not self.sign_in_configured:
            raise ValueError("Production needs the sign-in settings")
        if self.environment == "production" and self.database_url is None:
            raise ValueError("Production needs VELORAUG_DATABASE_URL")
        if (self.playback_signing_key is None) != (self.media_gateway_url is None):
            raise ValueError(
                "Set VELORAUG_PLAYBACK_SIGNING_KEY and VELORAUG_MEDIA_GATEWAY_URL "
                "together, or neither"
            )
        if self.environment == "production" and not self.playback_configured:
            raise ValueError(
                "Production needs VELORAUG_PLAYBACK_SIGNING_KEY and "
                "VELORAUG_MEDIA_GATEWAY_URL"
            )
        return self
