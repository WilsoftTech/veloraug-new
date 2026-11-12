"""One-time upload keys, the originals uploaded with them, and their qualities.

Used by scripts/catalogue.py, as the database owner. A key lets whoever holds
it upload one file for one movie. Only its SHA-256 is stored, so the text is
shown once, when it is made. See docs/step-07a-uploads-plan.md.
"""

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import psycopg

from app.upload_keys import KEY_PREFIX, key_hash, new_key

__all__ = ["KEY_PREFIX", "key_hash", "new_key"]

DEFAULT_DAYS = 7
MAX_DAYS = 30
MAX_LABEL = 100


class UploadKeyError(Exception):
    """A mistake the owner can fix. The message is safe to show."""


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
class Original:
    id: uuid.UUID
    upload_key_id: uuid.UUID
    state: str
    size_bytes: int
    height: int | None
    video_codec: str | None
    audio_codec: str | None
    reason: str | None
    qualities: tuple[int, ...] = ()


@dataclass(frozen=True)
class MovieUploads:
    movie_id: uuid.UUID
    tmdb_id: int
    title: str | None
    keys: list[UploadKey]
    originals: list[Original]


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
    on, and the original can be removed instead."""
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
    """Every movie with a key, newest key first, with its keys and originals."""
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
        originals = [
            Original(*row[:-1], qualities=tuple(row[-1]))
            for row in conn.execute(
                """
                select o.id, o.upload_key_id, o.state, o.size_bytes, o.height,
                       o.video_codec, o.audio_codec, o.reason,
                       array(select r.height from public.media_renditions r
                             where r.original_id = o.id order by r.height)
                from public.media_originals o where o.movie_id = %s
                order by o.created_at desc
                """,
                (id_,),
            )
        ]
        result.append(MovieUploads(id_, tmdb_id, title, keys, originals))
    return result


def size_text(size: int) -> str:
    for unit, scale in (("GB", 1e9), ("MB", 1e6), ("KB", 1e3)):
        if size >= scale:
            return f"{size / scale:.1f} {unit}"
    return f"{size} bytes"


def describe_uploads(movie: MovieUploads, now: datetime | None = None) -> list[str]:
    """Lines for `uploads`: the movie, then each key with its original."""
    now = now or datetime.now(UTC)
    lines = [f"{movie.title or '(no details)'}  TMDB {movie.tmdb_id}"]
    by_key = {original.upload_key_id: original for original in movie.originals}
    for key in movie.keys:
        state = key.state(now)
        when = (
            f"expires {key.expires_at:%d %b %H:%M} UTC" if state == "unused" else state
        )
        lines.append(f"  key for {key.label}: {when}  key id {key.id}")
        original = by_key.get(key.id)
        if original is None:
            continue
        quality = f"{original.height}p " if original.height else ""
        codecs = "/".join(
            codec.upper()
            for codec in (original.video_codec, original.audio_codec)
            if codec
        )
        detail = f"{quality}{codecs}".strip()
        size = size_text(original.size_bytes)
        text = f"    original {original.id}: {original.state}, {size}"
        if detail:
            text += f", {detail}"
        if original.qualities:
            made = ", ".join(f"{height}p" for height in original.qualities)
            text += f". Qualities: {made}"
        if original.reason:
            text += f". {original.reason}"
        lines.append(text)
    return lines
