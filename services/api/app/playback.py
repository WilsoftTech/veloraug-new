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

The grant goes in the path of the playback address, so the relative entries
in HLS playlists carry it to every file. See docs/step-08a-playback-plan.md.
No user is named in a grant: the address appears in browser history.
"""

import base64
import hashlib
import hmac
import json
import secrets
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID

import psycopg

GRANT_CONTEXT = b"veloraug-playback-v1."
GRANT_SECONDS = 6 * 60 * 60
PLAYLIST = "master.m3u8"


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def sign_grant(key: bytes, *, item_id: UUID, original_id: UUID, expires: int) -> str:
    """The grant text. `expires` is in seconds since 1970, UTC."""
    payload = _b64(
        json.dumps(
            {"m": str(item_id), "o": str(original_id), "e": expires},
            separators=(",", ":"),
        ).encode()
    )
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
        self, item_id: UUID, original_id: UUID, *, until: datetime | None = None
    ) -> Playback:
        """A grant for GRANT_SECONDS, or until `until` if that's sooner: the
        end of the viewer's pass, Step 10B."""
        expires = int(self._clock()) + GRANT_SECONDS
        if until is not None:
            expires = min(expires, int(until.timestamp()))
        token = sign_grant(
            self._key, item_id=item_id, original_id=original_id, expires=expires
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
