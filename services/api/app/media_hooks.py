"""The upload hooks: tusd asks here before accepting an upload, and says when
one has finished.

A separate app from the API, run as its own container with no published port,
so only tusd can reach it. It connects as veloraug_media, which can use an
upload key once and record the original, and nothing more. See "Uploads" in
docs/step-07a-uploads-plan.md.

tusd treats any answer but 200 as the hooks failing, and then tells the
uploader 500. So a refusal is a 200 whose JSON tells tusd to reject the upload
with the status and sentence given.

Run with:

    python -m uvicorn app.media_hooks:create_app --factory --host 0.0.0.0 --port 8000
"""

import base64
import hmac
import json
import logging
import unicodedata
import uuid
from contextlib import asynccontextmanager
from typing import Any
from urllib.parse import unquote, urlsplit

from fastapi import FastAPI, HTTPException, Request
from pydantic import SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from starlette.concurrency import run_in_threadpool

from app.db import Database, DatabaseUnavailable
from app.upload_keys import key_hash

MEDIA_ROLE = "veloraug_media"
KEY_HEADER = "Upload-Key"
# tusd's -max-size is the same, so a larger upload is refused twice over.
MAX_UPLOAD_BYTES = 50 * 1024**3
MAX_FILENAME = 255

BAD_KEY = (
    "This upload key doesn't work. It may be mistyped, already used, expired or "
    "revoked. Ask VeloraUG's owner for a new one."
)
UNAVAILABLE = "VeloraUG can't take uploads right now. Try again in a few minutes."
NOT_REMOVABLE = "Only an unfinished upload can be removed."
REMOVED_REASON = "Removed before it finished uploading."

logger = logging.getLogger("veloraug.media_hooks")


class MediaSettings(BaseSettings):
    """VELORAUG_MEDIA_* environment variables. Never the API's settings, so
    the API's container never holds the media role's password."""

    model_config = SettingsConfigDict(
        env_prefix="VELORAUG_MEDIA_", env_ignore_empty=True, hide_input_in_errors=True
    )

    database_url: SecretStr
    hook_secret: SecretStr | None = None

    @field_validator("database_url")
    @classmethod
    def require_media_role(cls, url: SecretStr) -> SecretStr:
        # The messages never quote the value: it holds a password.
        parts = urlsplit(url.get_secret_value())
        if parts.scheme not in ("postgresql", "postgres") or not parts.hostname:
            raise ValueError("database_url must be a postgresql:// connection string")
        if unquote(parts.username or "") != MEDIA_ROLE:
            raise ValueError(f"database_url must use the {MEDIA_ROLE} role")
        return url


def refuse(status: int, message: str) -> dict[str, Any]:
    return {
        "RejectUpload": True,
        "HTTPResponse": {
            "StatusCode": status,
            "Body": message + "\n",
            "Header": {"Content-Type": "text/plain; charset=utf-8"},
        },
    }


def refuse_removal(status: int, message: str) -> dict[str, Any]:
    return {
        "RejectTermination": True,
        "HTTPResponse": {
            "StatusCode": status,
            "Body": message + "\n",
            "Header": {"Content-Type": "text/plain; charset=utf-8"},
        },
    }


def header(event: dict[str, Any], name: str) -> str | None:
    """A request header. tusd sends names in Go's canonical form, such as
    Upload-Key, each with a list of values."""
    headers = (event.get("HTTPRequest") or {}).get("Header") or {}
    for key, values in headers.items():
        if key.lower() == name.lower() and isinstance(values, list) and values:
            value = values[0]
            return value if isinstance(value, str) else None
    return None


def clean_filename(metadata: Any) -> str | None:
    """The uploader's filename, for the owner to recognise: no folders, no
    control characters, at most 255 characters."""
    if not isinstance(metadata, dict):
        return None
    name = metadata.get("filename")
    if not isinstance(name, str):
        return None
    name = name.replace("\\", "/").rsplit("/", 1)[-1]
    name = "".join(ch for ch in name if unicodedata.category(ch)[0] != "C").strip()
    return name[:MAX_FILENAME] or None


class Hooks:
    def __init__(self, database: Database, max_bytes: int = MAX_UPLOAD_BYTES) -> None:
        self.database = database
        self.max_bytes = max_bytes

    def handle(self, body: Any) -> dict[str, Any]:
        if not isinstance(body, dict) or not isinstance(body.get("Event"), dict):
            return {}
        kind = body.get("Type")
        if kind == "pre-create":
            return self.pre_create(body["Event"])
        if kind == "pre-terminate":
            return self.pre_terminate(body["Event"])
        if kind == "post-finish":
            self.post_finish(body["Event"])
        return {}

    def pre_terminate(self, event: dict[str, Any]) -> dict[str, Any]:
        """Removing an upload through tusd, from the admin screens' Remove.
        Only one still uploading: never one received, being converted or
        published. It is marked removed here, before tusd deletes its files,
        so the worker never picks up a half-deleted upload."""
        upload_id = (event.get("Upload") or {}).get("ID")
        try:
            original_id = uuid.UUID(str(upload_id))
        except ValueError:
            return refuse_removal(403, NOT_REMOVABLE)
        try:
            with self.database.anonymous() as conn:
                changed = conn.execute(
                    """
                    update public.media_originals
                    set state = 'removed', reason = %s, updated_at = now()
                    where id = %s and state = 'uploading'
                    """,
                    (REMOVED_REASON, original_id),
                ).rowcount
        except DatabaseUnavailable as error:
            logger.warning("removal refused: database unavailable (%s)", error)
            return refuse_removal(503, UNAVAILABLE)
        if not changed:
            logger.info("removal of upload %s refused: not uploading", original_id)
            return refuse_removal(403, NOT_REMOVABLE)
        logger.info("upload %s removed before it finished", original_id)
        return {}

    def pre_create(self, event: dict[str, Any]) -> dict[str, Any]:
        upload = event.get("Upload") or {}
        if upload.get("IsPartial") or upload.get("IsFinal"):
            return refuse(400, "Upload the whole file in one upload.")
        size = upload.get("Size")
        if upload.get("SizeIsDeferred") or not isinstance(size, int) or size <= 0:
            return refuse(400, "Say the file's size when starting the upload.")
        if size > self.max_bytes:
            return refuse(413, "The file is larger than 50 GB, VeloraUG's limit.")
        key = header(event, KEY_HEADER)
        if not key or not key.strip():
            return refuse(403, BAD_KEY)

        original_id = uuid.uuid4()
        try:
            with self.database.anonymous() as conn:
                claimed = conn.execute(
                    """
                    update public.upload_keys set used_at = now()
                    where key_hash = %s and used_at is null and revoked_at is null
                      and expires_at > now()
                    returning id, item_id
                    """,
                    (key_hash(key),),
                ).fetchone()
                if claimed is None:
                    logger.info("upload refused: the key doesn't work")
                    return refuse(403, BAD_KEY)
                key_id, item_id = claimed
                conn.execute(
                    """
                    insert into public.media_originals
                      (id, item_id, upload_key_id, size_bytes, filename)
                    values (%s, %s, %s, %s, %s)
                    """,
                    (
                        original_id,
                        item_id,
                        key_id,
                        size,
                        clean_filename(upload.get("MetaData")),
                    ),
                )
        except DatabaseUnavailable as error:
            logger.warning("upload refused: database unavailable (%s)", error)
            return refuse(503, UNAVAILABLE)
        logger.info("upload %s accepted for item %s", original_id, item_id)
        # tusd uses this as the upload's ID, so its files are named by it.
        return {"ChangeFileInfo": {"ID": str(original_id)}}

    def post_finish(self, event: dict[str, Any]) -> None:
        upload_id = (event.get("Upload") or {}).get("ID")
        try:
            original_id = uuid.UUID(str(upload_id))
        except ValueError:
            logger.warning("finished upload with an unknown ID")
            return
        try:
            with self.database.anonymous() as conn:
                changed = conn.execute(
                    """
                    update public.media_originals
                    set state = 'received', updated_at = now()
                    where id = %s and state = 'uploading'
                    """,
                    (original_id,),
                ).rowcount
        except DatabaseUnavailable as error:
            # The file is complete in tusd's folder. The worker finds uploads
            # left in 'uploading' with a complete file, from Step 7D.
            logger.error(
                "upload %s finished, but not recorded (%s)", original_id, error
            )
            return
        if changed:
            logger.info("upload %s received", original_id)
        else:
            logger.warning("upload %s finished, but wasn't waiting", original_id)


def show_log_lines() -> None:
    """Prints the hooks' log lines, including accepted and refused uploads,
    which Python would otherwise drop below WARNING. They never hold a key."""
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter("%(levelname)s:     %(message)s"))
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
        logger.propagate = False


def create_app(
    settings: MediaSettings | None = None, database: Database | None = None
) -> FastAPI:
    settings = settings or MediaSettings()
    if (
        settings.hook_secret is None
        or len(settings.hook_secret.get_secret_value()) < 32
    ):
        raise ValueError("Configure VELORAUG_MEDIA_HOOK_SECRET for the hook listener")
    secret = settings.hook_secret.get_secret_value()
    authorization = "Basic " + base64.b64encode(f"tusd:{secret}".encode()).decode()
    database = database or Database(settings.database_url.get_secret_value())
    hooks = Hooks(database)
    show_log_lines()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        database.open()
        try:
            yield
        finally:
            database.close()

    # No documentation pages: nothing outside Docker's network should know
    # this exists.
    app = FastAPI(
        title="VeloraUG media hooks",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/tusd")
    async def tusd_hook(request: Request) -> dict[str, Any]:
        # The body holds the uploader's headers, including the key, so it is
        # never logged.
        supplied = request.headers.get("authorization", "")
        if not supplied.isascii() or not hmac.compare_digest(supplied, authorization):
            raise HTTPException(401, "Hook authentication required.")
        payload = bytearray()
        async for chunk in request.stream():
            if len(chunk) > 65536 - len(payload):
                raise HTTPException(413, "Hook body is too large.")
            payload.extend(chunk)
        try:
            body = json.loads(payload)
        except ValueError:
            raise HTTPException(400, "Invalid hook body.") from None
        return await run_in_threadpool(hooks.handle, body)

    return app
