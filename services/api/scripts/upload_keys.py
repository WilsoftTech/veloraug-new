"""One-time upload keys, the originals uploaded with them, and their qualities.

Used by scripts/catalogue.py, as the database owner. A key lets whoever holds
it upload one file for one playable item: a movie edition, or one episode.
Only its SHA-256 is stored, so the text is shown once, when it is made. See
docs/step-07a-uploads-plan.md and docs/step-09a-vj-catalogue-plan.md.
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
    item_id: uuid.UUID
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
class ItemUploads:
    item_id: uuid.UUID
    edition_id: uuid.UUID
    title: str
    season: int | None
    episode: int | None
    keys: list[UploadKey]
    originals: list[Original]


_KEY_COLUMNS = "id, item_id, label, created_at, expires_at, used_at, revoked_at"


def clean_label(label: str) -> str:
    label = " ".join(label.split())
    if not label:
        raise UploadKeyError("Say who the key is for, with --for")
    if len(label) > MAX_LABEL:
        raise UploadKeyError(f"--for is at most {MAX_LABEL} characters")
    return label


def grant_upload(
    conn: psycopg.Connection,
    item_id: uuid.UUID,
    label: str,
    days: int = DEFAULT_DAYS,
) -> tuple[UploadKey, str]:
    """A new key for one upload to the item. Returns the key's text once."""
    if not 1 <= days <= MAX_DAYS:
        raise UploadKeyError(f"--days must be from 1 to {MAX_DAYS}")
    key = new_key()
    row = conn.execute(
        f"""
        insert into public.upload_keys (item_id, key_hash, label, expires_at)
        values (%s, %s, %s, now() + %s)
        returning {_KEY_COLUMNS}
        """,
        (item_id, key_hash(key), clean_label(label), timedelta(days=days)),
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
    conn: psycopg.Connection, only: uuid.UUID | None = None
) -> list[ItemUploads]:
    """Every item with a key, newest key first, with its keys and originals.
    Only one edition's items, or one item, if its ID is given."""
    items = conn.execute(
        """
        select i.id, e.id, e.display_title, i.season, i.episode
        from public.items i join public.editions e on e.id = i.edition_id
        where exists (select from public.upload_keys k where k.item_id = i.id)
          and (%(only)s::uuid is null or e.id = %(only)s::uuid
               or i.id = %(only)s::uuid)
        order by (select max(created_at) from public.upload_keys k
                  where k.item_id = i.id) desc
        """,
        {"only": only},
    ).fetchall()
    result = []
    for item_id, edition, title, season, episode in items:
        keys = [
            UploadKey(*row)
            for row in conn.execute(
                f"""
                select {_KEY_COLUMNS} from public.upload_keys
                where item_id = %s order by created_at desc
                """,
                (item_id,),
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
                from public.media_originals o where o.item_id = %s
                order by o.created_at desc
                """,
                (item_id,),
            )
        ]
        result.append(
            ItemUploads(item_id, edition, title, season, episode, keys, originals)
        )
    return result


def item_name(title: str, season: int | None, episode: int | None) -> str:
    """ "Fast X", or "Kabaka S1 E2" for an episode."""
    return title if season is None else f"{title} S{season} E{episode}"


def size_text(size: int) -> str:
    for unit, scale in (("GB", 1e9), ("MB", 1e6), ("KB", 1e3)):
        if size >= scale:
            return f"{size / scale:.1f} {unit}"
    return f"{size} bytes"


def describe_uploads(item: ItemUploads, now: datetime | None = None) -> list[str]:
    """Lines for `uploads`: the item, then each key with its original."""
    now = now or datetime.now(UTC)
    lines = [f"{item_name(item.title, item.season, item.episode)}  item {item.item_id}"]
    by_key = {original.upload_key_id: original for original in item.originals}
    for key in item.keys:
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


# Originals the owner can remove: anything not already on its way out.
REMOVABLE = ("ready", "publishing", "failed", "refused")


def request_removal(conn: psycopg.Connection, original_id: str) -> str:
    """Marks an original 'removing'. The media worker deletes its files from R2
    and this computer, then marks it 'removed'. Returns its previous state."""
    try:
        parsed = uuid.UUID(original_id)
    except ValueError:
        raise UploadKeyError(
            f"{original_id!r} isn't an original's ID. See `uploads`"
        ) from None
    row = conn.execute(
        "select state from public.media_originals where id = %s for update", (parsed,)
    ).fetchone()
    if row is None:
        raise UploadKeyError(f"No original {original_id}")
    if row[0] not in REMOVABLE:
        raise UploadKeyError(
            f"That original is {row[0]}. Only one that is "
            f"{', '.join(REMOVABLE[:-1])} or {REMOVABLE[-1]} can be removed"
        )
    conn.execute(
        """
        update public.media_originals set state = 'removing', updated_at = now()
        where id = %s
        """,
        (parsed,),
    )
    return row[0]
