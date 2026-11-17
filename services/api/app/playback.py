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

    def grant(self, item_id: UUID, original_id: UUID) -> Playback:
        expires = int(self._clock()) + GRANT_SECONDS
        token = sign_grant(
            self._key, item_id=item_id, original_id=original_id, expires=expires
        )
        return Playback(
            playlist_url=f"{self._gateway}/v1/{token}/{PLAYLIST}",
            expires_at=datetime.fromtimestamp(expires, UTC),
        )


def ready_original(conn: psycopg.Connection, item_id: UUID) -> UUID | None:
    """The ready original of an approved item of a published edition, or
    None. Row-level security shows the API's role nothing else."""
    row = conn.execute(
        "select id from public.media_originals where item_id = %s and state = 'ready'",
        (item_id,),
    ).fetchone()
    return row[0] if row else None
