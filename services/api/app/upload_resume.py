"""Short, scoped credentials for one unfinished upload."""

import hashlib
import hmac
import time

from pydantic import SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

RESUME_HEADER = "upload-resume"
RESUME_SECONDS = 14 * 86400


class UploadSecurity(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="VELORAUG_UPLOAD_", hide_input_in_errors=True
    )
    resume_key: SecretStr
    web_origin: str = "http://localhost:8765"

    @field_validator("resume_key")
    @classmethod
    def long_key(cls, key: SecretStr) -> SecretStr:
        if len(key.get_secret_value()) < 32:
            raise ValueError("The upload resume key must be at least 32 characters")
        return key

    def issue(self, upload_id: str, now: int | None = None) -> str:
        expires = (int(time.time()) if now is None else now) + RESUME_SECONDS
        return self._token(upload_id, expires)

    def _token(self, upload_id: str, expires: int) -> str:
        digest = hmac.new(
            self.resume_key.get_secret_value().encode(),
            f"resume:{upload_id}:{expires}".encode(),
            hashlib.sha256,
        ).hexdigest()
        return f"{expires}.{digest}"

    def permits(
        self, upload_id: str, token: str | None, now: int | None = None
    ) -> bool:
        if not token or not token.isascii() or len(token) > 80:
            return False
        expires, dot, _ = token.partition(".")
        if not dot or not expires.isdecimal():
            return False
        now = int(time.time()) if now is None else now
        return int(expires) > now and hmac.compare_digest(
            token, self._token(upload_id, int(expires))
        )
