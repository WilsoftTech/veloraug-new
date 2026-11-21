"""The viewer's devices and playback sessions, and the media gateway's
question about a session. Milestone 10; see app/devices.py.

Every route but the gateway's needs a sign-in, and acts only on the
signed-in viewer's own devices and sessions: row-level security hides the
rest, so another account's ID answers 404, as a made-up one does.
"""

import logging
from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response, status
from pydantic import BaseModel, StringConstraints

from app import devices, passes, ratelimit
from app.auth import VerifiedUser, current_user
from app.playback import Granter
from app.viewer_routes import AppDatabase, device_refusal, granter

logger = logging.getLogger("veloraug.devices")
router = APIRouter(prefix="/api/v1", tags=["devices"])

Viewer = Annotated[VerifiedUser, Depends(current_user)]
Credential = Annotated[str | None, Header(alias=devices.HEADER, max_length=100)]
Label = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=60)
]
NO_DEVICE = "There's no such device."
NO_SESSION = "There's no such playback session."


def _now() -> datetime:
    return datetime.now(UTC)


class DeviceOut(BaseModel):
    id: UUID
    label: str
    platform: str
    registered_at: datetime
    last_active_at: datetime
    # The device asking.
    current: bool


class DevicesOut(BaseModel):
    devices: list[DeviceOut]
    # How many the pass running now allows, and how many may play at once.
    allowed: int
    streams_allowed: int
    # Whether this account has more than it may use, after a smaller plan.
    over_limit: bool


class RegisterIn(BaseModel):
    label: Label
    platform: Literal["web", "android", "ios", "other"]


class Registered(BaseModel):
    device: DeviceOut
    # `<id>.<secret>`, for the X-Velora-Device header. Shown once, never
    # stored by the API, and never logged. Null when the device sending the
    # request was already registered.
    credential: str | None


class RenameIn(BaseModel):
    label: Label


class SessionOut(BaseModel):
    id: UUID
    device_id: UUID
    device_label: str
    started_at: datetime
    last_seen_at: datetime
    current_device: bool


class HeartbeatOut(BaseModel):
    live: bool


class GatewayOut(BaseModel):
    live: bool
    # Unix seconds, when live: the pass's end. The grant ends sooner.
    until: int | None


def _device_out(device: devices.Device, current: devices.Device | None) -> DeviceOut:
    return DeviceOut(
        id=device.id,
        label=device.label,
        platform=device.platform,
        registered_at=device.registered_at,
        last_active_at=device.last_active_at,
        current=current is not None and current.id == device.id,
    )


@router.get("/me/devices")
def my_devices(user: Viewer, db: AppDatabase, credential: Credential = None):
    """The viewer's registered devices, most recently active first, and
    what their pass allows."""
    now = _now()
    with db.as_user(user.user_id) as conn:
        current = devices.authenticate(conn, credential)
        found = devices.active_devices(conn)
        entitlement = passes.current_entitlement(conn, user.user_id, now)
    allowed = devices.allowance(entitlement)
    return DevicesOut(
        devices=[_device_out(d, current) for d in found],
        allowed=allowed,
        streams_allowed=devices.stream_allowance(entitlement) if entitlement else 0,
        over_limit=len(found) > allowed,
    )


@router.post(
    "/me/devices",
    status_code=status.HTTP_201_CREATED,
    responses={
        200: {"description": "This device was already registered."},
        409: {"description": "Every device the plan allows is registered."},
        429: {"description": "Too many devices added lately, or too fast."},
    },
)
def register_device(
    body: RegisterIn,
    request: Request,
    response: Response,
    user: Viewer,
    db: AppDatabase,
    credential: Credential = None,
) -> Registered:
    """Registers this installation. A device that sends a valid credential
    is already registered, and gets itself back, not a second place."""
    now = _now()
    with db.as_user(user.user_id) as conn:
        existing = devices.authenticate(conn, credential)
        if existing is not None:
            response.status_code = status.HTTP_200_OK
            return Registered(device=_device_out(existing, existing), credential=None)
    request.app.state.rate_limiter.check(
        "device", str(user.user_id), ratelimit.DEVICE_REGISTER
    )
    with db.as_user(user.user_id) as conn:
        entitlement = passes.current_entitlement(conn, user.user_id, now)
        try:
            device, secret = devices.register(
                conn,
                user.user_id,
                label=body.label,
                platform=body.platform,
                entitlement=entitlement,
                now=now,
            )
        except devices.DeviceProblem as problem:
            raise device_refusal(problem) from None
    return Registered(
        device=_device_out(device, device), credential=f"{device.id}.{secret}"
    )


@router.patch("/me/devices/{device_id}", responses={404: {"description": NO_DEVICE}})
def rename_device(
    device_id: UUID,
    body: RenameIn,
    user: Viewer,
    db: AppDatabase,
    credential: Credential = None,
) -> DeviceOut:
    with db.as_user(user.user_id) as conn:
        device = devices.rename(conn, device_id, body.label)
        current = devices.authenticate(conn, credential)
    if device is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NO_DEVICE)
    return _device_out(device, current)


@router.delete(
    "/me/devices/{device_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={404: {"description": NO_DEVICE}},
)
def remove_device(device_id: UUID, user: Viewer, db: AppDatabase) -> Response:
    """Removes a device, and stops anything it is playing within a minute.
    Its place is free at once."""
    with db.as_user(user.user_id) as conn:
        removed = devices.revoke(conn, user.user_id, device_id, _now())
    if not removed:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NO_DEVICE)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me/playback-sessions")
def my_sessions(
    user: Viewer, db: AppDatabase, credential: Credential = None
) -> list[SessionOut]:
    """What is playing on the viewer's devices now."""
    now = _now()
    with db.as_user(user.user_id) as conn:
        current = devices.authenticate(conn, credential)
        found = devices.live_sessions(conn, now)
    return [
        SessionOut(
            id=s.id,
            device_id=s.device_id,
            device_label=s.device_label,
            started_at=s.started_at,
            last_seen_at=s.last_seen_at,
            current_device=current is not None and current.id == s.device_id,
        )
        for s in found
    ]


@router.delete(
    "/me/playback-sessions/{session_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={404: {"description": NO_SESSION}},
)
def stop_session(session_id: UUID, user: Viewer, db: AppDatabase) -> Response:
    """Stops playback on one of the viewer's devices, freeing its stream.
    The media gateway stops serving it within a minute."""
    with db.as_user(user.user_id) as conn:
        ended = devices.end_session(conn, user.user_id, session_id, _now())
    if not ended:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NO_SESSION)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/me/playback-sessions/{session_id}/heartbeat",
    responses={
        402: {"description": "The pass this session was under is over."},
        403: {"description": "This device isn't registered, or was removed."},
        410: {"description": "The session was ended."},
    },
)
def keep_watching(
    session_id: UUID, user: Viewer, db: AppDatabase, credential: Credential = None
) -> HeartbeatOut:
    """The player says it is still watching, every heartbeat_seconds."""
    now = _now()
    with db.as_user(user.user_id) as conn:
        device = devices.authenticate(conn, credential)
        if device is None:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                {"code": "device_revoked", "message": "This device was removed."},
            )
        state = devices.heartbeat(conn, session_id, device, now)
    if state == "pass":
        raise HTTPException(status.HTTP_402_PAYMENT_REQUIRED, "Your pass has ended.")
    if state == "ended":
        raise HTTPException(
            status.HTTP_410_GONE,
            {"code": "session_ended", "message": "Playback was stopped."},
        )
    return HeartbeatOut(live=True)


@router.get("/gateway/sessions/{session_id}", include_in_schema=False)
def gateway_session(
    session_id: UUID,
    db: AppDatabase,
    signer: Annotated[Granter, Depends(granter)],
    signature: Annotated[
        str | None, Header(alias="X-Velora-Gateway", max_length=80)
    ] = None,
) -> GatewayOut:
    """The media gateway's question: may this session still fetch video?
    Only the Worker, signing with the shared key, may ask. The answer is a
    yes or no and an end time, nothing about the viewer."""
    if not signer.gateway_check_valid(session_id, signature):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not the media gateway.")
    with db.anonymous() as conn:
        live, until = devices.gateway_status(conn, session_id)
    return GatewayOut(
        live=live, until=int(until.timestamp()) if live and until else None
    )
