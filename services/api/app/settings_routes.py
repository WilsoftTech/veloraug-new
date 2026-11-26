"""Settings, Step 13H Phase 5: admins read and change them; anyone reads
what the app needs to show, such as maintenance mode and support contacts.

See app/app_settings.py for each setting and its checks.
"""

import logging
from typing import Annotated, Any

from fastapi import APIRouter, Body, HTTPException, Request, status
from pydantic import BaseModel

from app import app_settings, audit
from app.admin import AdminUser, EditorDatabase, editing
from app.viewer_routes import AppDatabase

logger = logging.getLogger("veloraug.admin")
router = APIRouter(prefix="/api/v1", tags=["settings"])

# The limits and qualities the server works to, shown to admins as they are.
VIDEO_LIMIT_GB = 50
IMAGE_LIMIT_MB = 2
QUALITIES = ["360p", "480p", "720p", "1080p"]


class ServerInfo(BaseModel):
    """What admins can see but not change here: set on the server."""

    environment: str
    api_version: str
    # The database's migration, or None when it can't be read.
    schema_version: str | None
    pesapal_configured: bool
    pesapal_environment: str
    tmdb_configured: bool
    playback_configured: bool
    # VELORAUG_PAYMENT_TIMEOUT_MINUTES: used when no timeout is stored.
    payment_timeout_minutes_server: int
    video_limit_gb: int
    image_limit_mb: int
    qualities: list[str]


class SettingsOut(BaseModel):
    values: dict[str, Any]
    defaults: dict[str, Any]
    server: ServerInfo


class Status(BaseModel):
    """What the app shows everyone: maintenance, and how to get help."""

    maintenance: bool
    maintenance_message: str
    support_email: str
    support_phone: str
    support_whatsapp: str


def _defaults(request: Request) -> dict[str, Any]:
    defaults = {k: s.default for k, s in app_settings.SETTINGS.items()}
    defaults["payment_timeout_minutes"] = (
        request.app.state.settings.payment_timeout_minutes
    )
    return defaults


def _out(request: Request, conn) -> SettingsOut:
    values = app_settings.read(conn)
    try:
        with conn.transaction():
            row = conn.execute("select version_num from alembic_version").fetchone()
        schema = row[0] if row else None
    except Exception:  # Not readable by this role: shown as unknown.
        schema = None
    settings = request.app.state.settings
    return SettingsOut(
        values=values,
        defaults=_defaults(request),
        server=ServerInfo(
            environment=settings.environment,
            api_version=request.app.version,
            schema_version=schema,
            pesapal_configured=request.app.state.pesapal is not None,
            pesapal_environment=settings.pesapal_environment,
            tmdb_configured=request.app.state.tmdb is not None,
            playback_configured=request.app.state.granter is not None,
            payment_timeout_minutes_server=settings.payment_timeout_minutes,
            video_limit_gb=VIDEO_LIMIT_GB,
            image_limit_mb=IMAGE_LIMIT_MB,
            qualities=QUALITIES,
        ),
    )


@router.get("/admin/settings", tags=["admin"])
def get_settings(request: Request, user: AdminUser, db: EditorDatabase) -> SettingsOut:
    """Every setting, its default, and what the server is set up with."""
    with editing(db, user) as conn:
        return _out(request, conn)


@router.patch(
    "/admin/settings",
    tags=["admin"],
    responses={400: {"description": "A value is wrong: `errors` says which."}},
)
def change_settings(
    request: Request,
    user: AdminUser,
    db: EditorDatabase,
    changes: Annotated[dict[str, Any], Body(max_length=20)],
) -> SettingsOut:
    """Changes the settings sent. null returns one to its default. If any
    value is wrong, nothing is saved, and each wrong one is named."""
    try:
        with editing(db, user) as conn:
            changed = app_settings.write(conn, changes, user.user_id)
    except app_settings.SettingErrors as error:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            {"message": "Some settings weren't saved", "errors": error.errors},
        ) from None
    audit.event("admin.settings_changed", admin_id=user.user_id, count=len(changed))
    logger.info("Admin %s changed settings: %s", user.user_id, ", ".join(changed))
    with editing(db, user) as conn:
        return _out(request, conn)


@router.get("/status")
def app_status(db: AppDatabase) -> Status:
    """Maintenance mode and support contacts, for everyone. Needs no
    sign-in."""
    with db.anonymous() as conn:
        values = app_settings.safe_read(conn)
    return Status(
        maintenance=values["maintenance"],
        maintenance_message=values["maintenance_message"],
        support_email=values["support_email"],
        support_phone=values["support_phone"],
        support_whatsapp=values["support_whatsapp"],
    )
