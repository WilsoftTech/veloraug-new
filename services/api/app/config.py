from typing import Literal
from urllib.parse import urlsplit

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed settings, read from VELORAUG_* environment variables.

    A .env file is not loaded, because no env_file is configured here. Under
    Docker Compose, Compose passes the file's values as environment variables.
    """

    # An empty variable, such as KEY="" in a Compose env file, counts as unset.
    model_config = SettingsConfigDict(env_prefix="VELORAUG_", env_ignore_empty=True)

    environment: Literal["development", "production"] = "development"
    allowed_origins: list[str] = ["http://localhost:8765"]

    # Sign-in. None of these is secret. All three are needed together.
    neon_auth_url: str | None = None
    api_resource: str | None = None
    neon_auth_client_ids: list[str] = []

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
        return self
