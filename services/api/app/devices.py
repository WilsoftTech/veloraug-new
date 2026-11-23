"""Registered devices and playback sessions, Milestone 10.

A device is one installation of the app: a browser profile, or the Android
app on one phone. When it registers, the API makes it an ID and a random
secret, and shows the secret once. The device sends both on every request
that needs it, as `X-Velora-Device: <id>.<secret>`. Only the secret's
SHA-256 hash is stored, so a database leak can't be replayed, and a made-up
or copied ID is useless without its secret. Nothing about the hardware is
collected: no IMEI, serial number or advertising ID.

The pass running now decides how many devices an account may have and how
many may play at once. Whatever the plan, never more than three of either;
the database enforces that too. One device plays one thing at a time.

Every change for one account happens under one advisory lock, the same one
the database's triggers take, so two requests at once can't both take the
last free place.

Everything here runs in Database.as_user, so row-level security limits it
to the viewer's own rows.
"""

import base64
import hashlib
import hmac
import re
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

import psycopg

from app import audit
from app.passes import MAX_DEVICES, MAX_STREAMS, Entitlement

HEADER = "X-Velora-Device"
_CREDENTIAL = re.compile(
    r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"
    r"\.([A-Za-z0-9_-]{43})"
)
PLATFORMS = ("web", "android", "ios", "other")

# The player says it's still watching this often. A session not heard from
# for IDLE is over: its place is free, and the media gateway stops serving
# it.
HEARTBEAT_SECONDS = 60
IDLE = timedelta(seconds=180)
# Device switching: within any 30 days, an account can register its plan's
# devices plus this many replacements, for a lost or broken device. Beyond
# that, it waits, or asks support.
SWITCH_WINDOW = timedelta(days=30)
REPLACEMENTS = 3
# Without a pass, one device can still register, to see its account.
ALLOWANCE_WITHOUT_PASS = 1
# Device and session activity is written at most this often.
TOUCH_EVERY = timedelta(seconds=55)
_LOCK = 7


class DeviceProblem(Exception):
    """Refused, with a code the app understands."""

    code = "device"

    def __init__(self, message: str, **details) -> None:
        super().__init__(message)
        self.details = details


class DeviceLimit(DeviceProblem):
    code = "device_limit"


class SwitchLimit(DeviceProblem):
    code = "device_switch_limit"


class StreamLimit(DeviceProblem):
    code = "stream_limit"


@dataclass(frozen=True)
class Device:
    id: UUID
    label: str
    platform: str
    registered_at: datetime
    last_active_at: datetime
    revoked_at: datetime | None


@dataclass(frozen=True)
class Session:
    id: UUID
    device_id: UUID
    device_label: str
    item_id: UUID
    started_at: datetime
    last_seen_at: datetime


DEVICE_COLUMNS = "id, label, platform, registered_at, last_active_at, revoked_at"


# --- Credentials -------------------------------------------------------------


def _hash(secret: str) -> bytes:
    return hashlib.sha256(secret.encode("ascii")).digest()


def new_secret() -> str:
    """32 random bytes, base64url without padding: 43 characters."""
    return base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode()


def parse(credential: str | None) -> tuple[UUID, str] | None:
    if not credential or len(credential) > 100:
        return None
    match = _CREDENTIAL.fullmatch(credential.strip())
    if match is None:
        return None
    return UUID(match[1]), match[2]


def authenticate(conn: psycopg.Connection, credential: str | None) -> Device | None:
    """The viewer's own active device this credential names, or None for a
    missing, malformed, forged, removed or someone else's device."""
    parsed = parse(credential)
    if parsed is None:
        return None
    device_id, secret = parsed
    row = conn.execute(
        f"select {DEVICE_COLUMNS}, secret_hash from public.devices "
        "where id = %s and revoked_at is null",
        (device_id,),
    ).fetchone()
    if row is None or not hmac.compare_digest(bytes(row[6]), _hash(secret)):
        return None
    return Device(*row[:6])


def lock(conn: psycopg.Connection, user_id: UUID) -> None:
    """One account's devices and sessions, one transaction at a time."""
    conn.execute(
        "select pg_advisory_xact_lock(hashtextextended(%s, %s))",
        (str(user_id), _LOCK),
    )


# --- Devices -----------------------------------------------------------------


def allowance(entitlement: Entitlement | None) -> int:
    if entitlement is None:
        return ALLOWANCE_WITHOUT_PASS
    return min(MAX_DEVICES, entitlement.max_devices)


def stream_allowance(entitlement: Entitlement) -> int:
    return min(MAX_STREAMS, entitlement.max_streams, entitlement.max_devices)


def active_devices(conn: psycopg.Connection) -> list[Device]:
    rows = conn.execute(
        f"select {DEVICE_COLUMNS} from public.devices where revoked_at is null "
        "order by last_active_at desc"
    ).fetchall()
    return [Device(*row) for row in rows]


def register(
    conn: psycopg.Connection,
    user_id: UUID,
    *,
    label: str,
    platform: str,
    entitlement: Entitlement | None,
    now: datetime,
) -> tuple[Device, str]:
    """Registers this installation, answering it and its secret, shown once.
    Raises DeviceLimit when the plan's devices are all taken, and
    SwitchLimit when too many devices have been added lately."""
    if platform not in PLATFORMS:
        platform = "other"
    lock(conn, user_id)
    allowed = allowance(entitlement)
    devices = active_devices(conn)
    if len(devices) >= allowed:
        raise DeviceLimit(
            f"Your plan allows {allowed} registered "
            f"device{'s' if allowed != 1 else ''}. Remove one to add this one.",
            limit=allowed,
        )
    (recent,) = conn.execute(
        "select count(*) from public.devices where registered_at > %s",
        (now - SWITCH_WINDOW,),
    ).fetchone()
    if recent >= allowed + REPLACEMENTS:
        raise SwitchLimit(
            "This account has added too many devices in the last 30 days. "
            "Keep using a device already registered, or contact support.",
            limit=allowed + REPLACEMENTS,
        )
    secret = new_secret()
    row = conn.execute(
        f"""
        insert into public.devices (user_id, secret_hash, label, platform,
          registered_at, last_active_at)
        values (%s, %s, %s, %s, %s, %s)
        returning {DEVICE_COLUMNS}
        """,
        (user_id, _hash(secret), label, platform, now, now),
    ).fetchone()
    device = Device(*row)
    audit.event("device.registered", user_id=user_id, device_id=device.id)
    return device, secret


def rename(conn: psycopg.Connection, device_id: UUID, label: str) -> Device | None:
    row = conn.execute(
        f"""
        update public.devices set label = %s
        where id = %s and revoked_at is null returning {DEVICE_COLUMNS}
        """,
        (label, device_id),
    ).fetchone()
    return Device(*row) if row else None


def revoke(
    conn: psycopg.Connection,
    user_id: UUID,
    device_id: UUID,
    now: datetime,
    *,
    by: str = "owner",
) -> bool:
    """Removes a device, and ends anything it is playing at once. The media
    gateway stops serving its grant within a minute."""
    lock(conn, user_id)
    row = conn.execute(
        """
        update public.devices set revoked_at = %s, revoked_by = %s
        where id = %s and user_id = %s and revoked_at is null returning id
        """,
        (now, by, device_id, user_id),
    ).fetchone()
    if row is None:
        return False
    conn.execute(
        """
        update public.playback_sessions
        set ended_at = %s, end_reason = 'device_removed'
        where device_id = %s and ended_at is null
        """,
        (now, device_id),
    )
    audit.event("device.removed", user_id=user_id, device_id=device_id, reason=by)
    return True


def touch(conn: psycopg.Connection, device: Device, now: datetime) -> None:
    if now - device.last_active_at >= TOUCH_EVERY:
        conn.execute(
            "update public.devices set last_active_at = %s where id = %s",
            (now, device.id),
        )


# --- Sessions ----------------------------------------------------------------


def end_idle(conn: psycopg.Connection, now: datetime) -> None:
    conn.execute(
        """
        update public.playback_sessions set ended_at = %s, end_reason = 'idle'
        where ended_at is null and last_seen_at <= %s
        """,
        (now, now - IDLE),
    )


def live_sessions(conn: psycopg.Connection, now: datetime) -> list[Session]:
    rows = conn.execute(
        """
        select s.id, s.device_id, d.label, s.item_id, s.started_at, s.last_seen_at
        from public.playback_sessions s join public.devices d on d.id = s.device_id
        where s.ended_at is null and s.last_seen_at > %s
        order by s.started_at
        """,
        (now - IDLE,),
    ).fetchall()
    return [Session(*row) for row in rows]


def check_device_limit(conn: psycopg.Connection, entitlement: Entitlement) -> None:
    """Raises DeviceLimit if the account has more devices than the pass
    allows, as start_session does, without starting anything: for
    downloads, which take no stream."""
    devices_allowed = allowance(entitlement)
    count = len(active_devices(conn))
    if count > devices_allowed:
        raise DeviceLimit(
            f"Your plan allows {devices_allowed} registered "
            f"device{'s' if devices_allowed != 1 else ''}, and this account has "
            f"{count}. Choose which to remove in Account, My devices.",
            limit=devices_allowed,
        )


def start_session(
    conn: psycopg.Connection,
    user_id: UUID,
    device: Device,
    entitlement: Entitlement,
    item_id: UUID,
    now: datetime,
) -> UUID:
    """A playback session for this device under the pass running now. The
    device's earlier session, if any, is replaced: one device, one stream.
    Raises DeviceLimit if the account has more devices than the plan allows,
    after a change to a smaller plan, and StreamLimit when every stream is
    in use on other devices."""
    lock(conn, user_id)
    devices_allowed = allowance(entitlement)
    devices = active_devices(conn)
    if len(devices) > devices_allowed:
        raise DeviceLimit(
            f"Your plan allows {devices_allowed} registered "
            f"device{'s' if devices_allowed != 1 else ''}, and this account has "
            f"{len(devices)}. Choose which to remove in Account, My devices.",
            limit=devices_allowed,
        )
    end_idle(conn, now)
    conn.execute(
        """
        update public.playback_sessions set ended_at = %s, end_reason = 'replaced'
        where device_id = %s and ended_at is null
        """,
        (now, device.id),
    )
    streams = stream_allowance(entitlement)
    others = live_sessions(conn, now)
    if len(others) >= streams:
        raise StreamLimit(
            f"Your plan allows {streams} "
            f"stream{'s' if streams != 1 else ''} at once, and "
            f"{'it is' if streams == 1 else 'they are'} in use. "
            "Stop playback on another device to watch here.",
            limit=streams,
            sessions=[
                {
                    "id": str(s.id),
                    "device_label": s.device_label,
                    "started_at": s.started_at.isoformat(),
                }
                for s in others
            ],
        )
    (session_id,) = conn.execute(
        """
        insert into public.playback_sessions (user_id, device_id, pass_id,
          item_id, started_at, last_seen_at)
        values (%s, %s, %s, %s, %s, %s) returning id
        """,
        (user_id, device.id, entitlement.id, item_id, now, now),
    ).fetchone()
    touch(conn, device, now)
    audit.event(
        "session.started",
        user_id=user_id,
        device_id=device.id,
        session_id=session_id,
        item_id=item_id,
    )
    return session_id


def heartbeat(
    conn: psycopg.Connection, session_id: UUID, device: Device, now: datetime
) -> str:
    """Keeps a session alive. Answers 'live', or why it isn't: 'ended' (by
    its owner, another device, a removed device or going idle) or 'pass'
    (its pass is over or was revoked)."""
    row = conn.execute(
        """
        select s.ended_at, s.last_seen_at, p.revoked_at, p.starts_at, p.ends_at
        from public.playback_sessions s join public.passes p on p.id = s.pass_id
        where s.id = %s and s.device_id = %s
        for update of s
        """,
        (session_id, device.id),
    ).fetchone()
    if row is None:
        return "ended"
    ended, seen, revoked, starts, ends = row
    if ended is not None or seen <= now - IDLE:
        return "ended"
    if revoked is not None or not (starts <= now < ends):
        conn.execute(
            """
            update public.playback_sessions set ended_at = %s,
              end_reason = 'pass_ended' where id = %s
            """,
            (now, session_id),
        )
        return "pass"
    conn.execute(
        "update public.playback_sessions set last_seen_at = %s where id = %s",
        (now, session_id),
    )
    touch(conn, device, now)
    return "live"


def end_session(
    conn: psycopg.Connection,
    user_id: UUID,
    session_id: UUID,
    now: datetime,
    *,
    reason: str = "owner",
) -> bool:
    row = conn.execute(
        """
        update public.playback_sessions set ended_at = %s, end_reason = %s
        where id = %s and ended_at is null returning id
        """,
        (now, reason, session_id),
    ).fetchone()
    if row is not None:
        audit.event(
            "session.ended", user_id=user_id, session_id=session_id, reason=reason
        )
    return row is not None


def gateway_status(
    conn: psycopg.Connection, session_id: UUID
) -> tuple[bool, datetime | None]:
    """For the media gateway: whether this session may still fetch video,
    and until when. Answered by a database function that says nothing
    else about the session."""
    row = conn.execute(
        "select live, until from public.playback_session_status(%s, %s)",
        (session_id, int(IDLE.total_seconds())),
    ).fetchone()
    if row is None:
        return False, None
    return bool(row[0]), row[1]
