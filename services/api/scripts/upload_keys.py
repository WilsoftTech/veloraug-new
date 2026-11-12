"""One-time upload keys, and the movie versions uploaded with them.

Used by scripts/catalogue.py, as the database owner. A key lets whoever holds
it upload one file for one movie. Only its SHA-256 is stored, so the text is
shown once, when it is made. See docs/step-07a-uploads-plan.md.
"""

import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import psycopg

KEY_PREFIX = "vu_"
DEFAULT_DAYS = 7
MAX_DAYS = 30
MAX_LABEL = 100


class UploadKeyError(Exception):
    """A mistake the owner can fix. The message is safe to show."""


def new_key() -> str:
    """32 random bytes, as 43 URL-safe characters, after a recognisable prefix."""
    return KEY_PREFIX + secrets.token_urlsafe(32)


def key_hash(key: str) -> bytes:
    """What the database stores, and what the upload hooks look a key up by."""
    return hashlib.sha256(key.strip().encode()).digest()


@dataclass(frozen=True)
class UploadKey:
    id: uuid.UUID
    movie_id: uuid.UUID
    label: str
    created_at: datetime
    expires_at: datetime
    used_at: datetime | None
    revoked_at: datetime | None

    def state(self, now: datetime) -> str:
        if self.revoked_at:
            return "revoked"
        if self.used_at:
            return "used"
        if self.expires_at <= now:
            return "expired"
        return "unused"


@dataclass(frozen=True)
class Version:
    id: uuid.UUID
    upload_key_id: uuid.UUID
    state: str
    size_bytes: int
    height: int | None
    video_codec: str | None
    audio_codec: str | None
    reason: str | None


@dataclass(frozen=True)
class MovieUploads:
    movie_id: uuid.UUID
    tmdb_id: int
    title: str | None
    keys: list[UploadKey]
    versions: list[Version]


_KEY_COLUMNS = "id, movie_id, label, created_at, expires_at, used_at, revoked_at"


def clean_label(label: str) -> str:
    label = " ".join(label.split())
    if not label:
        raise UploadKeyError("Say who the key is for, with --for")
    if len(label) > MAX_LABEL:
        raise UploadKeyError(f"--for is at most {MAX_LABEL} characters")
    return label


def grant_upload(
    conn: psycopg.Connection,
    movie_id: uuid.UUID,
    label: str,
    days: int = DEFAULT_DAYS,
) -> tuple[UploadKey, str]:
    """A new key for one upload to the movie. Returns the key's text once."""
    if not 1 <= days <= MAX_DAYS:
        raise UploadKeyError(f"--days must be from 1 to {MAX_DAYS}")
    key = new_key()
    row = conn.execute(
        f"""
        insert into public.upload_keys (movie_id, key_hash, label, expires_at)
        values (%s, %s, %s, now() + %s)
        returning {_KEY_COLUMNS}
        """,
        (movie_id, key_hash(key), clean_label(label), timedelta(days=days)),
    ).fetchone()
    return UploadKey(*row), key


def revoke_upload(conn: psycopg.Connection, key_id: str) -> UploadKey:
    """Stops a key working. A key already used stays used: its upload carries
    on, and the version can be removed instead."""
    try:
        parsed = uuid.UUID(key_id)
    except ValueError:
        raise UploadKeyError(f"{key_id!r} isn't a key ID. See `uploads`") from None
    row = conn.execute(
        f"""
        update public.upload_keys set revoked_at = coalesce(revoked_at, now())
        where id = %s
        returning {_KEY_COLUMNS}
        """,
        (parsed,),
    ).fetchone()
    if row is None:
        raise UploadKeyError(f"No upload key {key_id}")
    return UploadKey(*row)


def list_uploads(
    conn: psycopg.Connection, movie_id: uuid.UUID | None = None
) -> list[MovieUploads]:
    """Every movie with a key, newest key first, with its keys and versions."""
    movies = conn.execute(
        """
        select m.id, m.tmdb_id, d.title
        from public.movies m
        left join public.tmdb_movie_details d using (tmdb_id)
        where exists (select from public.upload_keys k where k.movie_id = m.id)
          and (%(movie)s::uuid is null or m.id = %(movie)s::uuid)
        order by (select max(created_at) from public.upload_keys k
                  where k.movie_id = m.id) desc
        """,
        {"movie": movie_id},
    ).fetchall()
    result = []
    for id_, tmdb_id, title in movies:
        keys = [
            UploadKey(*row)
            for row in conn.execute(
                f"""
                select {_KEY_COLUMNS} from public.upload_keys
                where movie_id = %s order by created_at desc
                """,
                (id_,),
            )
        ]
        versions = [
            Version(*row)
            for row in conn.execute(
                """
                select id, upload_key_id, state, size_bytes, height,
                       video_codec, audio_codec, reason
                from public.media_versions where movie_id = %s
                order by created_at desc
                """,
                (id_,),
            )
        ]
        result.append(MovieUploads(id_, tmdb_id, title, keys, versions))
    return result


def size_text(size: int) -> str:
    for unit, scale in (("GB", 1e9), ("MB", 1e6), ("KB", 1e3)):
        if size >= scale:
            return f"{size / scale:.1f} {unit}"
    return f"{size} bytes"


def describe_uploads(movie: MovieUploads, now: datetime | None = None) -> list[str]:
    """Lines for `uploads`: the movie, then each key with its version."""
    now = now or datetime.now(UTC)
    lines = [f"{movie.title or '(no details)'}  TMDB {movie.tmdb_id}"]
    by_key = {version.upload_key_id: version for version in movie.versions}
    for key in movie.keys:
        state = key.state(now)
        when = (
            f"expires {key.expires_at:%d %b %H:%M} UTC" if state == "unused" else state
        )
        lines.append(f"  key for {key.label}: {when}  key id {key.id}")
        version = by_key.get(key.id)
        if version is None:
            continue
        quality = f"{version.height}p " if version.height else ""
        codecs = "/".join(
            codec.upper()
            for codec in (version.video_codec, version.audio_codec)
            if codec
        )
        detail = f"{quality}{codecs}".strip()
        size = size_text(version.size_bytes)
        text = f"    version {version.id}: {version.state}, {size}"
        if detail:
            text += f", {detail}"
        if version.reason:
            text += f". {version.reason}"
        lines.append(text)
    return lines
