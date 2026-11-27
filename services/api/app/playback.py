"""Playback grants: what the API gives the app so it can watch one movie.

A grant is `<payload>.<signature>`, both base64url without padding. The
payload is JSON naming the movie, its ready original and the expiry time.
The signature is HMAC-SHA256, with the key the API and the Worker in
services/media_gateway/ share, over GRANT_CONTEXT followed by the payload
text. The Worker checks it on every playlist and chunk, and builds the R2
path from it, so a grant for one movie can't fetch another.

Since Milestone 9 the grant's "m" names a playable item: a movie edition's
one item, or one episode. Films from before then have items with their old
movie IDs, and R2 still keeps every item's files under movies/<item ID>/.

Downloads: the API gives a session-less grant for a day, and the viewer's
browser or phone downloads <quality>/download.mp4, one ordinary .mp4 file
that is theirs to keep. See docs/step-12a-downloads.md.

The grant goes in the path of the playback address, so the relative entries
in HLS playlists carry it to every file. See docs/step-08a-playback-plan.md.
No user is named in a grant: the address appears in browser history.

Milestone 10: with passes required, a viewer's grant also names a playback
session, "s", a random ID that says nothing about who is watching. Such a
grant lasts at most SESSION_GRANT_SECONDS, and the Worker asks the API, at
least every minute, whether its session is still live: a removed device, an
ended session, or an expired or reversed pass stops the video within a
minute, long before the grant itself runs out. The Worker's question is
signed with the same key under GATEWAY_CONTEXT, so nobody else can ask.
"""

import base64
import hashlib
import hmac
import json
import secrets
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Literal
from uuid import UUID

import psycopg

GRANT_CONTEXT = b"veloraug-playback-v1."
GRANT_SECONDS = 6 * 60 * 60
# A grant bound to a playback session. The player asks for a new one when
# it runs out, and carries on from the same moment.
SESSION_GRANT_SECONDS = 60 * 60
# The Worker's question about a session, and how long its signature counts.
GATEWAY_CONTEXT = b"veloraug-gateway-v1."
GATEWAY_SKEW_SECONDS = 120
PLAYLIST = "master.m3u8"
# Downloads: a grant with no playback session, so a download never takes a
# stream or replaces the player's session on the same device. The browser's
# or Android's own downloader fetches the file, resuming where it stopped,
# but can't ask for a new grant: so a day, for slow connections.
DOWNLOAD_GRANT_SECONDS = 24 * 60 * 60
# Each quality's whole video as one file, beside its playlist.
DOWNLOAD_FILE = "download.mp4"


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


GrantPurpose = Literal["playback", "preview", "download"]


def sign_grant(
    key: bytes,
    *,
    item_id: UUID,
    original_id: UUID,
    expires: int,
    purpose: GrantPurpose = "playback",
    session_id: UUID | None = None,
) -> str:
    """The grant text. `expires` is in seconds since 1970, UTC."""
    claims: dict[str, object] = {
        "m": str(item_id),
        "o": str(original_id),
        "e": expires,
        "p": purpose,
    }
    if session_id is not None:
        claims["s"] = str(session_id)
    payload = _b64(json.dumps(claims, separators=(",", ":")).encode())
    signature = hmac.new(key, GRANT_CONTEXT + payload.encode(), hashlib.sha256)
    return f"{payload}.{_b64(signature.digest())}"


@dataclass(frozen=True)
class Playback:
    playlist_url: str
    expires_at: datetime


class Granter:
    def __init__(self, *, key: bytes, gateway_url: str, clock=time.time) -> None:
        self._key = key
        self._gateway = gateway_url.rstrip("/")
        self._clock = clock

    def grant(
        self,
        item_id: UUID,
        original_id: UUID,
        *,
        until: datetime | None = None,
        session_id: UUID | None = None,
        seconds: int | None = None,
        purpose: GrantPurpose = "playback",
    ) -> Playback:
        """A grant for GRANT_SECONDS, or until `until` if that's sooner: the
        end of the viewer's pass, Step 10B. One bound to a playback session
        lasts SESSION_GRANT_SECONDS at most. `seconds`, when given, replaces
        either: a download's grant, DOWNLOAD_GRANT_SECONDS."""
        if seconds is None:
            seconds = GRANT_SECONDS if session_id is None else SESSION_GRANT_SECONDS
        expires = int(self._clock()) + seconds
        if until is not None:
            expires = min(expires, int(until.timestamp()))
        token = sign_grant(
            self._key,
            item_id=item_id,
            original_id=original_id,
            expires=expires,
            purpose=purpose,
            session_id=session_id,
        )
        return Playback(
            playlist_url=f"{self._gateway}/v1/{token}/{PLAYLIST}",
            expires_at=datetime.fromtimestamp(expires, UTC),
        )

    def upload(self, path: str, content_type: str) -> Playback:
        """Where an admin's browser sends one image, for UPLOAD_SECONDS."""
        expires = int(self._clock()) + UPLOAD_SECONDS
        token = sign_upload(
            self._key, path=path, content_type=content_type, expires=expires
        )
        return Playback(
            playlist_url=f"{self._gateway}/i/{token}",
            expires_at=datetime.fromtimestamp(expires, UTC),
        )

    @property
    def gateway(self) -> str:
        return self._gateway

    def gateway_check_valid(self, session_id: UUID, signature: str | None) -> bool:
        """Whether the Worker signed this question about this session. The
        header is `<expires>.<signature>`, valid until `expires`, and at most
        GATEWAY_SKEW_SECONDS ahead."""
        return verify_gateway_check(
            self._key, session_id, signature, int(self._clock())
        )

    def image_url(self, path: str) -> str:
        """The public address of an uploaded poster or VJ photo."""
        return f"{self._gateway}/i/{path}"


# Admins' uploaded images, Step 9C. The Worker checks these with its own
# context, so an upload grant is never a playback grant, nor the reverse.
UPLOAD_CONTEXT = b"veloraug-image-v1."
UPLOAD_SECONDS = 10 * 60
IMAGE_TYPES = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}


def sign_upload(key: bytes, *, path: str, content_type: str, expires: int) -> str:
    """An upload grant for one image at one R2 path."""
    payload = _b64(
        json.dumps(
            {"p": path, "t": content_type, "e": expires}, separators=(",", ":")
        ).encode()
    )
    signature = hmac.new(key, UPLOAD_CONTEXT + payload.encode(), hashlib.sha256)
    return f"{payload}.{_b64(signature.digest())}"


def image_path(folder: str, owner_id: UUID, content_type: str) -> str:
    """A new, unguessable R2 path for an image: posters/<edition>/<random>.jpg
    or vjs/<VJ>/<random>.png. New for every upload, so it can be cached
    forever."""
    if folder not in ("posters", "vjs") or content_type not in IMAGE_TYPES:
        raise ValueError("Not an image VeloraUG keeps")
    return (
        f"{folder}/{owner_id}/{secrets.token_urlsafe(16)}.{IMAGE_TYPES[content_type]}"
    )


def ready_original(conn: psycopg.Connection, item_id: UUID) -> UUID | None:
    """The ready original of an approved item of a published edition, or
    None. Row-level security shows the API's role nothing else."""
    row = conn.execute(
        "select id from public.media_originals where item_id = %s and state = 'ready'",
        (item_id,),
    ).fetchone()
    return row[0] if row else None


def sign_gateway_check(key: bytes, session_id: UUID, expires: int) -> str:
    """What the Worker sends in X-Velora-Gateway to ask about a session."""
    message = GATEWAY_CONTEXT + f"{session_id}.{expires}".encode()
    return f"{expires}.{_b64(hmac.new(key, message, hashlib.sha256).digest())}"


def verify_gateway_check(
    key: bytes, session_id: UUID, header: str | None, now: int
) -> bool:
    if not header or len(header) > 80 or "." not in header:
        return False
    expires_text, _, given = header.partition(".")
    if not expires_text.isdigit() or len(expires_text) > 12:
        return False
    expires = int(expires_text)
    if expires <= now or expires > now + GATEWAY_SKEW_SECONDS:
        return False
    expected = sign_gateway_check(key, session_id, expires).partition(".")[2]
    return hmac.compare_digest(expected, given)
