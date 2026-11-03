from typing import Literal
from urllib.parse import urlsplit

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed settings, read from VELORAUG_* environment variables.

    A .env file is not loaded, because no env_file is configured here.
    """

    model_config = SettingsConfigDict(env_prefix="VELORAUG_")

    environment: Literal["development", "production"] = "development"
    allowed_origins: list[str] = ["http://localhost:8765"]

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
