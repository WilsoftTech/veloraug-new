"""What the admin routes read and write, as veloraug_editor.

Each function takes a connection in a transaction and leaves the commit to
the caller. TMDB is called by the routes between transactions, never while
one is open, so a slow TMDB never holds a database connection.

See docs/step-09a-vj-catalogue-plan.md, sections 2 to 5.
"""

import re
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta

import psycopg
import psycopg.types.json

from app import editions
from app.editions import EditionError
from app.matching import KnownVj, Suggestion, suggest_credit
from app.tmdb import MovieDetails, SearchResult
from app.upload_keys import key_hash, new_key

KEY_DAYS = 7
MAX_KEY_DAYS = 30
# A TMDB poster path, or one an admin uploaded to R2 (Step 9C, images).
# A TMDB poster path. Uploaded posters are checked against their edition.
TMDB_POSTER = re.compile(r"^/[A-Za-z0-9_-]{1,100}\.(jpg|jpeg|png)$")


class AdminError(EditionError):
    """A mistake the admin can fix. The message is safe to show."""


class NotFound(AdminError):
    pass


# --- Admins ------------------------------------------------------------------


def is_admin(conn: psycopg.Connection, user_id: uuid.UUID) -> bool:
    return (
        conn.execute(
            "select 1 from public.admins where user_id = %s", (user_id,)
        ).fetchone()
        is not None
    )


@dataclass(frozen=True)
class Admin:
    user_id: uuid.UUID
    email: str | None
    added_by: uuid.UUID | None
    added_by_email: str | None
    added_at: datetime


def list_admins(conn: psycopg.Connection) -> list[Admin]:
    rows = conn.execute(
        """
        select a.user_id, a.email, a.added_by, b.email, a.added_at
        from public.admins a left join public.admins b on b.user_id = a.added_by
        order by a.added_at
        """
    ).fetchall()
    return [Admin(*row) for row in rows]


def add_admin(conn: psycopg.Connection, email: str, added_by: uuid.UUID) -> uuid.UUID:
    email = " ".join(email.split())
    if "@" not in email or len(email) > 320:
        raise AdminError("That isn't an email address")
    (user_id,) = conn.execute("select public.verified_user_id(%s)", (email,)).fetchone()
    if user_id is None:
        raise NotFound(
            "No VeloraUG account has that email confirmed. Ask them to sign in "
            "once and confirm their email, then try again"
        )
    added = conn.execute(
        """
        insert into public.admins (user_id, email, added_by) values (%s, %s, %s)
        on conflict (user_id) do nothing
        """,
        (user_id, email.lower(), added_by),
    ).rowcount
    if not added:
        raise AdminError("They are already an admin")
    return user_id


def remove_admin(conn: psycopg.Connection, user_id: uuid.UUID) -> None:
    try:
        with conn.transaction():
            removed = conn.execute(
                "delete from public.admins where user_id = %s", (user_id,)
            ).rowcount
    except psycopg.errors.CheckViolation:
        raise AdminError(
            "That is the last admin. Add another first, then remove this one"
        ) from None
    if not removed:
        raise NotFound("That user isn't an admin")


# --- Languages and VJs -------------------------------------------------------


def list_languages(conn: psycopg.Connection) -> list[tuple[str, str]]:
    return conn.execute(
        "select code, name from public.languages order by code = 'lg' desc, name"
    ).fetchall()


def add_language(conn: psycopg.Connection, code: str, name: str) -> None:
    code, name = code.strip().lower(), " ".join(name.split())
    if not re.fullmatch(r"[a-z]{2,3}", code):
        raise AdminError("A language code is 2 or 3 letters, such as lg or nyn")
    if not 1 <= len(name) <= 50:
        raise AdminError("Give the language's name, up to 50 characters")
    try:
        with conn.transaction():
            conn.execute(
                "insert into public.languages (code, name) values (%s, %s)",
                (code, name),
            )
    except psycopg.errors.UniqueViolation:
        raise AdminError("That language is already there") from None


@dataclass(frozen=True)
class Vj:
    id: uuid.UUID
    name: str
    slug: str
    match_names: list[str]
    photo_path: str | None
    bio: str | None
    # Every edition credited to them, deleted ones left out.
    editions: int
    active: bool = True
    featured: bool = False
    sort_order: int | None = None
    links: dict = field(default_factory=dict)
    published: int = 0
    hidden: int = 0
    drafts: int = 0
    # Viewers of their titles in the last VIEWER_DAYS days.
    viewers: int = 0


def list_vjs(conn: psycopg.Connection, vj_id: uuid.UUID | None = None) -> list[Vj]:
    """Every VJ, or the one asked for, with their titles counted."""
    rows = conn.execute(
        """
        select v.id, v.name, v.slug, v.match_names, v.photo_path, v.bio,
               count(e.id)::int,
               v.active, v.featured, v.sort_order, v.links,
               count(e.id) filter (where e.status = 'published')::int,
               count(e.id) filter (where e.status = 'hidden')::int,
               count(e.id) filter (where e.status = 'draft')::int,
               coalesce(sum(w.viewers), 0)::int
        from public.vjs v
        left join public.editions e on e.vj_id = v.id and e.deleted_at is null
        left join public.edition_viewers(%(days)s) w on w.edition_id = e.id
        where %(id)s::uuid is null or v.id = %(id)s::uuid
        group by v.id
        order by lower(v.name)
        """,
        {"days": 30, "id": vj_id},
    ).fetchall()
    return [Vj(*row) for row in rows]


def get_vj(conn: psycopg.Connection, vj_id: uuid.UUID) -> Vj:
    found = list_vjs(conn, vj_id)
    if not found:
        raise NotFound("No such VJ")
    return found[0]


# The links a VJ can have, and the addresses each must start with.
VJ_LINKS = {
    "facebook": (
        "https://www.facebook.com/",
        "https://facebook.com/",
        "https://fb.com/",
    ),
    "instagram": ("https://www.instagram.com/", "https://instagram.com/"),
    "tiktok": ("https://www.tiktok.com/", "https://tiktok.com/"),
    "youtube": (
        "https://www.youtube.com/",
        "https://youtube.com/",
        "https://youtu.be/",
    ),
    "x": ("https://x.com/", "https://twitter.com/", "https://www.x.com/"),
    "whatsapp": (
        "https://wa.me/",
        "https://whatsapp.com/",
        "https://www.whatsapp.com/",
    ),
    "website": ("https://",),
}


def clean_links(links: dict) -> dict[str, str]:
    """Checks a VJ's links: known names, https addresses on that site, each
    up to 300 characters. An empty one is dropped."""
    cleaned: dict[str, str] = {}
    for name, value in links.items():
        if name not in VJ_LINKS:
            raise AdminError(f"Unknown link {name!r}")
        value = (value or "").strip()
        if not value:
            continue
        if len(value) > 300 or " " in value:
            raise AdminError(f"The {name} link is too long, or has a space")
        if not value.lower().startswith(VJ_LINKS[name]):
            raise AdminError(f"The {name} link should start with {VJ_LINKS[name][0]}")
        cleaned[name] = value
    return cleaned


def _spelling_of(
    conn: psycopg.Connection, name: str, other_than: uuid.UUID | None = None
) -> str | None:
    """The VJ whose other spellings include this name, if any."""
    row = conn.execute(
        """
        select v.name from public.vjs v
        where (%s::uuid is null or v.id <> %s::uuid)
          and exists (select from unnest(v.match_names) m
                      where lower(m) = lower(%s))
        limit 1
        """,
        (other_than, other_than, name),
    ).fetchone()
    return row[0] if row else None


def slug_for(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return slug[:80].strip("-") or "vj"


def _vj_fields(
    name: str | None, match_names: list[str] | None, bio: str | None
) -> dict:
    fields: dict = {}
    if name is not None:
        name = " ".join(name.split())
        if not 1 <= len(name) <= 80:
            raise AdminError("A VJ's name is 1 to 80 characters")
        fields["name"] = name
    if match_names is not None:
        names = []
        for other in match_names:
            other = " ".join(str(other).split())[:80]
            if other and other.lower() not in (n.lower() for n in names):
                names.append(other)
        if len(names) > 20:
            raise AdminError("At most 20 other spellings")
        fields["match_names"] = names
    if bio is not None:
        bio = bio.strip()
        if len(bio) > 1000:
            raise AdminError("A bio is at most 1,000 characters")
        fields["bio"] = bio or None
    return fields


def add_vj(
    conn: psycopg.Connection,
    name: str,
    match_names: list[str] | None = None,
    bio: str | None = None,
) -> uuid.UUID:
    fields = _vj_fields(name, match_names or [], bio)
    if other := _spelling_of(conn, fields["name"]):
        raise AdminError(
            f"Files already spell {other} as “{fields['name']}”. Change {other} "
            "instead, or add this VJ with another name"
        )
    base = slug_for(fields["name"])
    for attempt in range(20):
        slug = base if attempt == 0 else f"{base[:76]}-{attempt + 1}"
        try:
            with conn.transaction():
                (vj_id,) = conn.execute(
                    """
                    insert into public.vjs (name, slug, match_names, bio)
                    values (%s, %s, %s, %s) returning id
                    """,
                    (fields["name"], slug, fields["match_names"], fields.get("bio")),
                ).fetchone()
            return vj_id
        except psycopg.errors.UniqueViolation as error:
            if "vjs_name_idx" in str(error):
                raise AdminError("There is already a VJ with that name") from None
    raise AdminError("Couldn't make an address for that VJ. Try another name")


def update_vj(
    conn: psycopg.Connection,
    vj_id: uuid.UUID,
    *,
    name: str | None = None,
    match_names: list[str] | None = None,
    bio: str | None = None,
    photo_path: str | None = None,
) -> None:
    """Changes what is given. photo_path is a path an image upload for this
    VJ answered with, or "" to remove the photo."""
    fields = _vj_fields(name, match_names, bio)
    if "name" in fields and (other := _spelling_of(conn, fields["name"], vj_id)):
        raise AdminError(
            f"Files already spell {other} as “{fields['name']}”. Merge the two instead"
        )
    if photo_path is not None:
        if photo_path and not re.fullmatch(
            rf"vjs/{vj_id}/[A-Za-z0-9_-]{{16,43}}\.(jpg|png|webp)", photo_path
        ):
            raise AdminError("That isn't a photo uploaded for this VJ")
        fields["photo_path"] = photo_path or None
    if not fields:
        return
    columns = ", ".join(f"{column} = %({column})s" for column in fields)
    try:
        with conn.transaction():
            changed = conn.execute(
                f"update public.vjs set {columns}, updated_at = now() "
                "where id = %(id)s",
                {**fields, "id": vj_id},
            ).rowcount
    except psycopg.errors.UniqueViolation:
        raise AdminError("There is already a VJ with that name") from None
    if not changed:
        raise NotFound("No such VJ")


def update_vj_profile(
    conn: psycopg.Connection, vj_id: uuid.UUID, changes: dict
) -> None:
    """Changes what is given of active, featured, sort_order and links.
    A sort_order of None takes the VJ out of the order."""
    fields: dict = {}
    for flag in ("active", "featured"):
        if flag in changes:
            if not isinstance(changes[flag], bool):
                raise AdminError(f"{flag} is true or false")
            fields[flag] = changes[flag]
    if "sort_order" in changes:
        order = changes["sort_order"]
        if order is not None and not 1 <= order <= 9999:
            raise AdminError("The place in the list is 1 to 9999")
        fields["sort_order"] = order
    if "links" in changes:
        fields["links"] = psycopg.types.json.Jsonb(clean_links(changes["links"] or {}))
    if not fields:
        return
    columns = ", ".join(f"{column} = %({column})s" for column in fields)
    changed = conn.execute(
        f"update public.vjs set {columns}, updated_at = now() where id = %(id)s",
        {**fields, "id": vj_id},
    ).rowcount
    if not changed:
        raise NotFound("No such VJ")


class MergeConflict(AdminError):
    """Both VJs have an edition of the same film. The message names them."""


def merge_vjs(conn: psycopg.Connection, from_id: uuid.UUID, into_id: uuid.UUID) -> int:
    """Moves every title of one VJ to another, keeps the first's name and
    spellings as the second's other spellings, then deletes the first. The
    second keeps their own photo and bio, or takes the first's if they have
    none. How many titles moved."""
    if from_id == into_id:
        raise AdminError("Choose another VJ to merge into")
    rows = {
        row[0]: row
        for row in conn.execute(
            """
            select id, name, match_names, photo_path, bio from public.vjs
            where id = any(%s) for update
            """,
            ([from_id, into_id],),
        ).fetchall()
    }
    if from_id not in rows or into_id not in rows:
        raise NotFound("No such VJ")
    _, from_name, from_spellings, from_photo, from_bio = rows[from_id]
    _, into_name, into_spellings, into_photo, into_bio = rows[into_id]
    clashes = [
        title
        for (title,) in conn.execute(
            """
            select a.display_title from public.editions a
            join public.editions b on b.source_id = a.source_id
              and b.vj_id = %s and b.id <> a.id
            where a.vj_id = %s and a.source_id is not null
            order by a.display_title
            """,
            (into_id, from_id),
        ).fetchall()
    ]
    if clashes:
        raise MergeConflict(
            f"Both have an edition of {', '.join(clashes[:5])}. Delete or "
            "re-credit one of each first"
        )
    moved = conn.execute(
        "update public.editions set vj_id = %s, updated_at = now() where vj_id = %s",
        (into_id, from_id),
    ).rowcount
    spellings: list[str] = []
    for name in [*into_spellings, from_name, *from_spellings]:
        if name.lower() != into_name.lower() and name.lower() not in (
            s.lower() for s in spellings
        ):
            spellings.append(name)
    conn.execute(
        """
        update public.vjs set match_names = %s,
          photo_path = coalesce(photo_path, %s), bio = coalesce(bio, %s),
          updated_at = now()
        where id = %s
        """,
        (spellings[:20], from_photo, from_bio, into_id),
    )
    # The merged VJ's name becomes the other's spelling: free it first.
    conn.execute("delete from public.vjs where id = %s", (from_id,))
    return moved


def delete_vj(conn: psycopg.Connection, vj_id: uuid.UUID) -> None:
    """Deletes a VJ with no titles. One with titles is merged instead."""
    if not conn.execute(
        "select 1 from public.vjs where id = %s for update", (vj_id,)
    ).fetchone():
        raise NotFound("No such VJ")
    titles, deleting = conn.execute(
        "select count(*) filter (where deleted_at is null), "
        "count(*) filter (where deleted_at is not null) "
        "from public.editions where vj_id = %s",
        (vj_id,),
    ).fetchone()
    if titles:
        raise AdminError(
            "This VJ has titles. Merge them into another VJ, or make this one inactive"
        )
    if deleting:
        raise AdminError(
            "This VJ's deleted titles are still being removed. Try again in "
            "a few minutes"
        )
    conn.execute("delete from public.vjs where id = %s", (vj_id,))


def known_vjs(conn: psycopg.Connection) -> list[KnownVj]:
    return [
        KnownVj(id_, name, tuple(match_names or ()))
        for id_, name, match_names in conn.execute(
            "select id, name, match_names from public.vjs"
        ).fetchall()
    ]


# --- Drafts and keys ---------------------------------------------------------


def make_key(
    conn: psycopg.Connection, item_id: uuid.UUID, label: str, days: int = KEY_DAYS
) -> tuple[uuid.UUID, str, datetime]:
    """A one-time upload key for the item. Its text is returned once."""
    label = " ".join(label.split())
    if not 1 <= len(label) <= 100:
        raise AdminError("Say who the key is for, up to 100 characters")
    if not 1 <= days <= MAX_KEY_DAYS:
        raise AdminError(f"A key lasts 1 to {MAX_KEY_DAYS} days")
    text = new_key()
    key_id, expires_at = conn.execute(
        """
        insert into public.upload_keys (item_id, key_hash, label, expires_at)
        values (%s, %s, %s, now() + %s) returning id, expires_at
        """,
        (item_id, key_hash(text), label, timedelta(days=days)),
    ).fetchone()
    return key_id, text, expires_at


def revoke_key(conn: psycopg.Connection, key_id: uuid.UUID) -> None:
    changed = conn.execute(
        "update public.upload_keys set revoked_at = coalesce(revoked_at, now()) "
        "where id = %s",
        (key_id,),
    ).rowcount
    if not changed:
        raise NotFound("No such key")


@dataclass
class ItemState:
    id: uuid.UUID
    season: int | None
    episode: int | None
    episode_title: str | None
    approved: bool
    # The newest original's state, or None before any upload.
    video: str | None
    video_reason: str | None
    ready_original: uuid.UUID | None
    filename: str | None
    credit_hints: str | None
    # How far the worker has got converting or publishing, 0 to 100, and
    # the time left at that rate, from its own reports. None otherwise.
    progress: int | None = None
    eta_seconds: int | None = None
    # Waiting to be converted: its place in the worker's queue, from 1.
    queue_position: int | None = None
    size_bytes: int | None = None
    # Hidden from viewers on its own, apart from its series.
    hidden: bool = False
    keys: list[dict] = field(default_factory=list)


@dataclass
class EditionState:
    id: uuid.UUID
    kind: str
    display_title: str
    submitted_year: int | None
    language: str
    status: str
    test: bool
    tmdb_lookup: str | None
    source_id: uuid.UUID | None
    source_tmdb_id: int | None
    source_title: str | None
    source_year: int | None
    source_overview: str | None
    source_poster: str | None
    details_from: str | None
    poster_path: str | None
    vj_id: uuid.UUID | None
    vj_name: str | None
    created_at: datetime
    # The edition's own description, backdrop and trailer, over the source's.
    overview: str | None = None
    backdrop_path: str | None = None
    trailer_key: str | None = None
    source_backdrop: str | None = None
    source_trailer: str | None = None
    published_at: datetime | None = None
    items: list[ItemState] = field(default_factory=list)
    missing: list[str] = field(default_factory=list)
    matches: list[SearchResult] = field(default_factory=list)
    # Category names, in the order they were added.
    categories: list[str] = field(default_factory=list)

    @property
    def incomplete(self) -> bool:
        """No video of it has finished uploading yet. Drafts lists these
        apart, since there is nothing to check, convert or publish."""
        return all(item.video in (None, "uploading") for item in self.items)


_EDITION = """
    select e.id, e.kind, e.display_title, e.submitted_year, e.language,
           e.status, e.test, e.tmdb_lookup, e.source_id, s.tmdb_id, s.title,
           extract(year from s.release_date)::int, s.overview, s.poster_path,
           s.details_from, e.poster_path, e.vj_id, v.name, e.created_at,
           e.overview, e.backdrop_path, e.trailer_key, s.backdrop_path,
           s.trailer_key, e.published_at
    from public.editions e
    left join public.sources s on s.id = e.source_id
    left join public.vjs v on v.id = e.vj_id
"""


def _items(conn: psycopg.Connection, edition_id: uuid.UUID) -> list[ItemState]:
    rows = conn.execute(
        """
        select i.id, i.season, i.episode, i.episode_title, i.approved_at is not null,
               o.state, o.reason,
               (select r.id from public.media_originals r
                where r.item_id = i.id and r.state = 'ready'),
               o.filename, o.credit_hints,
               case when o.state in ('converting', 'publishing') then o.progress end,
               -- The time so far in this stage, scaled to what is left.
               case when o.state in ('converting', 'publishing')
                         and o.progress between 1 and 99
                    then ceil(extract(epoch from o.progress_at - o.updated_at)
                              * (100 - o.progress) / o.progress)::int end,
               case when o.state = 'received' then (
                 select count(*) from public.media_originals q
                 where q.state = 'received' and q.created_at <= o.created_at
               )::int end,
               o.size_bytes,
               i.hidden_at is not null
        from public.items i
        left join lateral (
          select state, reason, filename, credit_hints, progress, progress_at,
                 updated_at, created_at, size_bytes
          from public.media_originals
          where item_id = i.id order by created_at desc limit 1
        ) o on true
        where i.edition_id = %s and i.deleted_at is null
        order by i.season nulls first, i.episode nulls first
        """,
        (edition_id,),
    ).fetchall()
    items = [ItemState(*row) for row in rows]
    for item in items:
        item.keys = [
            {
                "id": key_id,
                "label": label,
                "expires_at": expires_at,
                "used": used_at is not None,
                "revoked": revoked_at is not None,
            }
            for key_id, label, expires_at, used_at, revoked_at in conn.execute(
                """
                select id, label, expires_at, used_at, revoked_at
                from public.upload_keys where item_id = %s order by created_at desc
                """,
                (item.id,),
            ).fetchall()
        ]
    return items


def get_edition(conn: psycopg.Connection, edition_id: uuid.UUID) -> EditionState:
    row = conn.execute(
        _EDITION + " where e.id = %s and e.deleted_at is null", (edition_id,)
    ).fetchone()
    if row is None:
        raise NotFound("No such edition")
    state = EditionState(*row)
    state.items = _items(conn, edition_id)
    state.missing = editions.missing_for_publish(conn, edition_id)
    state.matches = [
        SearchResult(*match)
        for match in conn.execute(
            """
            select tmdb_id, title, original_title, year, overview, poster_path
            from public.tmdb_matches where edition_id = %s order by position
            """,
            (edition_id,),
        ).fetchall()
    ]
    state.categories = edition_categories(conn, edition_id)
    return state


def list_work(conn: psycopg.Connection) -> list[EditionState]:
    """Editions that need an admin: every draft and hidden edition, and
    published series with an episode waiting for approval. Newest first."""
    ids = conn.execute(
        """
        select e.id from public.editions e
        where e.deleted_at is null
          and (e.status <> 'published'
               or exists (select from public.items i where i.edition_id = e.id
                          and i.approved_at is null and i.hidden_at is null
                          and i.deleted_at is null))
        order by e.created_at desc
        limit 200
        """
    ).fetchall()
    return [get_edition(conn, edition_id) for (edition_id,) in ids]


@dataclass
class SeriesRef:
    """A series edition, for matching dropped episode files to it."""

    id: uuid.UUID
    display_title: str
    language: str
    status: str
    vj_id: uuid.UUID | None
    vj_name: str | None
    episodes: list[tuple[int | None, int | None]]


def list_series(conn: psycopg.Connection) -> list[SeriesRef]:
    """Every series edition but test ones, in any state, with the
    episode numbers it already has. Newest first."""
    rows = conn.execute(
        """
        select e.id, e.display_title, e.language, e.status, e.vj_id, v.name,
               coalesce(
                 (select array_agg(array[i.season, i.episode]
                                   order by i.season, i.episode)
                  from public.items i
                  where i.edition_id = e.id and i.deleted_at is null),
                 '{}')
        from public.editions e
        left join public.vjs v on v.id = e.vj_id
        where e.kind = 'series' and not e.test and e.deleted_at is null
        order by e.created_at desc
        limit 1000
        """
    ).fetchall()
    return [
        SeriesRef(*row[:6], episodes=[(pair[0], pair[1]) for pair in row[6]])
        for row in rows
    ]


# --- Deleting ------------------------------------------------------------------


def delete_edition(
    conn: psycopg.Connection, edition_id: uuid.UUID, *, published_too: bool = False
) -> None:
    """Deletes an edition for good: see migration 0015. Its rows go once the
    media worker has deleted its videos' files. A published one is refused
    unless [published_too]: Drafts deletes drafts and hidden editions only."""
    row = conn.execute(
        "select status, test from public.editions "
        "where id = %s and deleted_at is null for update",
        (edition_id,),
    ).fetchone()
    if row is None:
        raise NotFound("No such edition")
    status, test = row
    if test:
        raise AdminError("Test films are deleted with the owner's script")
    if status == "published" and not published_too:
        raise AdminError("This is published. Hide it first, then delete it")
    conn.execute("select public.delete_edition(%s)", (edition_id,))


def delete_all_drafts(conn: psycopg.Connection) -> list[uuid.UUID]:
    """Deletes every draft, never a published or hidden edition. The IDs."""
    ids = [
        row[0]
        for row in conn.execute(
            """
            select id from public.editions
            where status = 'draft' and not test and deleted_at is null
            for update
            """
        ).fetchall()
    ]
    for edition_id in ids:
        conn.execute("select public.delete_edition(%s)", (edition_id,))
    return ids


# --- The Library: published, hidden and withdrawn titles ---------------------

LIBRARY_STATES = ("published", "hidden", "withdrawn")
LIBRARY_SORTS = ("newest", "oldest", "title", "viewers", "updated")
LIBRARY_PAGE = 50
# Viewers are counted over this many days, with public.edition_viewers.
VIEWER_DAYS = 30

# A title's place in the Library. Withdrawn: back to a draft, once published.
_LIBRARY_STATE = """
    case when e.status = 'draft' then 'withdrawn' else e.status end
"""


@dataclass(frozen=True)
class LibraryTitle:
    id: uuid.UUID
    kind: str
    display_title: str
    poster_path: str | None
    vj_id: uuid.UUID | None
    vj_name: str | None
    state: str
    published_at: datetime | None
    updated_at: datetime
    episodes: int
    hidden_episodes: int
    waiting: int
    viewers: int
    categories: list[str]
    year: int | None


def list_library(
    conn: psycopg.Connection,
    *,
    query: str | None = None,
    vj_id: uuid.UUID | None = None,
    kind: str | None = None,
    category: str | None = None,
    state: str | None = None,
    sort: str = "newest",
    limit: int = LIBRARY_PAGE,
    offset: int = 0,
) -> tuple[list[LibraryTitle], int]:
    """Titles viewers can see or once could, a page at a time, with how many
    match in all. Test films and deleted titles are left out."""
    if kind is not None and kind not in ("movie", "series"):
        raise AdminError("The kind is movie or series")
    if state is not None and state not in LIBRARY_STATES:
        raise AdminError("The state is published, hidden or withdrawn")
    if sort not in LIBRARY_SORTS:
        raise AdminError("Sort by newest, oldest, title, viewers or updated")
    where = [
        "not e.test",
        "e.deleted_at is null",
        "(e.status in ('published', 'hidden') or e.published_at is not null)",
    ]
    params: dict = {"days": VIEWER_DAYS, "limit": limit, "offset": offset}
    if query:
        where.append(
            "(strpos(lower(e.display_title), lower(%(q)s)) > 0"
            " or strpos(lower(coalesce(s.title, '')), lower(%(q)s)) > 0"
            " or strpos(lower(coalesce(v.name, '')), lower(%(q)s)) > 0)"
        )
        params["q"] = query.strip()[:120]
    if vj_id is not None:
        where.append("e.vj_id = %(vj)s")
        params["vj"] = vj_id
    if kind is not None:
        where.append("e.kind = %(kind)s")
        params["kind"] = kind
    if category:
        where.append(
            "exists (select from public.edition_categories ec"
            " join public.categories c on c.id = ec.category_id"
            " where ec.edition_id = e.id and lower(c.name) = lower(%(category)s))"
        )
        params["category"] = category
    if state is not None:
        where.append(f"{_LIBRARY_STATE} = %(state)s")
        params["state"] = state
    order = {
        "newest": "e.published_at desc nulls last, e.id",
        "oldest": "e.published_at asc nulls last, e.id",
        "title": "lower(e.display_title), e.id",
        "viewers": "coalesce(w.viewers, 0) desc, e.published_at desc, e.id",
        "updated": "e.updated_at desc, e.id",
    }[sort]
    rows = conn.execute(
        f"""
        select e.id, e.kind, e.display_title, e.poster_path, e.vj_id, v.name,
               {_LIBRARY_STATE}, e.published_at, e.updated_at,
               (select count(*) from public.items i
                where i.edition_id = e.id and i.deleted_at is null)::int,
               (select count(*) from public.items i
                where i.edition_id = e.id and i.deleted_at is null
                  and i.hidden_at is not null)::int,
               (select count(*) from public.items i
                where i.edition_id = e.id and i.deleted_at is null
                  and i.hidden_at is null and i.approved_at is null)::int,
               coalesce(w.viewers, 0)::int,
               coalesce((select array_agg(c.name order by ec.added_at)
                         from public.edition_categories ec
                         join public.categories c on c.id = ec.category_id
                         where ec.edition_id = e.id), '{{}}'),
               coalesce(e.submitted_year,
                        extract(year from s.release_date)::int),
               count(*) over ()
        from public.editions e
        left join public.sources s on s.id = e.source_id
        left join public.vjs v on v.id = e.vj_id
        left join public.edition_viewers(%(days)s) w on w.edition_id = e.id
        where {" and ".join(where)}
        order by {order}
        limit %(limit)s offset %(offset)s
        """,
        params,
    ).fetchall()
    total = rows[0][-1] if rows else 0
    if not rows and offset:
        (total,) = conn.execute(
            f"""
            select count(*) from public.editions e
            left join public.sources s on s.id = e.source_id
            left join public.vjs v on v.id = e.vj_id
            left join public.edition_viewers(%(days)s) w on w.edition_id = e.id
            where {" and ".join(where)}
            """,
            params,
        ).fetchone()
    return [LibraryTitle(*row[:-1]) for row in rows], total


_YOUTUBE = re.compile(
    r"^(?:https?://)?(?:www\.|m\.)?(?:youtube\.com/(?:watch\?(?:.*&)?v=|embed/|shorts/)"
    r"|youtu\.be/)([A-Za-z0-9_-]{6,20})(?:[?&#].*)?$"
)
_TRAILER_KEY = re.compile(r"^[A-Za-z0-9_-]{6,20}$")


def trailer_key(text: str) -> str | None:
    """A YouTube video's key, from its address or the key itself. None for
    empty text, which clears the edition's own trailer."""
    text = text.strip()
    if not text:
        return None
    match = _YOUTUBE.match(text)
    if match:
        return match.group(1)
    if _TRAILER_KEY.match(text):
        return text
    raise AdminError("Give a YouTube address, such as https://youtu.be/abc123XYZ")


def update_details(
    conn: psycopg.Connection, edition_id: uuid.UUID, changes: dict
) -> None:
    """Changes what is given of the edition's own details: title, year,
    language, description, trailer and backdrop. An empty description,
    trailer or backdrop clears the edition's own, so the source's shows."""
    fields: dict = {}
    if "display_title" in changes:
        fields["display_title"] = editions.clean_title(changes["display_title"] or "")
    if "submitted_year" in changes:
        year = changes["submitted_year"]
        if year is not None and not 1900 <= year <= 2100:
            raise AdminError("The year is from 1900 to 2100")
        fields["submitted_year"] = year
    if "language" in changes:
        code = changes["language"]
        if not conn.execute(
            "select 1 from public.languages where code = %s", (code,)
        ).fetchone():
            raise AdminError(f"No language {code!r}. Add it first")
        fields["language"] = code
    if "overview" in changes:
        text = (changes["overview"] or "").strip()
        if len(text) > 5000:
            raise AdminError("A description is at most 5,000 characters")
        fields["overview"] = text or None
    if "trailer" in changes:
        fields["trailer_key"] = trailer_key(changes["trailer"] or "")
    if "backdrop_path" in changes:
        path = changes["backdrop_path"] or ""
        if path and not re.fullmatch(
            rf"posters/{edition_id}/[A-Za-z0-9_-]{{16,43}}\.(jpg|png|webp)", path
        ):
            raise AdminError("That isn't a backdrop uploaded for this title")
        fields["backdrop_path"] = path or None
    if not fields:
        return
    columns = ", ".join(f"{column} = %({column})s" for column in fields)
    changed = conn.execute(
        f"update public.editions set {columns}, updated_at = now() "
        "where id = %(id)s and deleted_at is null",
        {**fields, "id": edition_id},
    ).rowcount
    if not changed:
        raise NotFound("No such edition")


def withdraw(conn: psycopg.Connection, edition_id: uuid.UUID) -> None:
    """Takes a published or hidden title back to a draft. Nothing is deleted:
    it waits in Drafts, and Publish brings it back."""
    row = conn.execute(
        "select status from public.editions "
        "where id = %s and deleted_at is null for update",
        (edition_id,),
    ).fetchone()
    if row is None:
        raise NotFound("No such edition")
    if row[0] == "draft":
        raise AdminError("This is a draft already")
    conn.execute(
        "update public.editions set status = 'draft', updated_at = now() where id = %s",
        (edition_id,),
    )


# --- Single episodes -------------------------------------------------------------


def _episode(conn: psycopg.Connection, item_id: uuid.UUID) -> tuple:
    """(edition ID, kind, season, episode), locked. NotFound if deleted."""
    row = conn.execute(
        """
        select i.edition_id, i.kind, i.season, i.episode from public.items i
        join public.editions e on e.id = i.edition_id
        where i.id = %s and i.deleted_at is null and e.deleted_at is null
        for update of i
        """,
        (item_id,),
    ).fetchone()
    if row is None:
        raise NotFound("No such episode")
    return row


def set_item_hidden(conn: psycopg.Connection, item_id: uuid.UUID, hidden: bool) -> None:
    """Hides an episode from viewers, or shows it again. A hidden episode
    keeps its approval, so showing it needs nothing else."""
    _episode(conn, item_id)
    conn.execute(
        "update public.items set hidden_at = "
        + ("coalesce(hidden_at, now())" if hidden else "null")
        + " where id = %s",
        (item_id,),
    )


def withdraw_item(conn: psycopg.Connection, item_id: uuid.UUID) -> None:
    """Takes an episode back to waiting for approval, in Drafts."""
    _episode(conn, item_id)
    conn.execute(
        "update public.items set approved_at = null, hidden_at = null where id = %s",
        (item_id,),
    )


def delete_item(conn: psycopg.Connection, item_id: uuid.UUID) -> None:
    """Deletes one episode for good, as delete_edition does a title. A
    movie's only video is deleted with its title instead."""
    edition_id, kind, *_ = _episode(conn, item_id)
    if kind != "series":
        raise AdminError("A movie's video goes with the movie: delete the movie")
    (others,) = conn.execute(
        "select count(*) from public.items "
        "where edition_id = %s and id <> %s and deleted_at is null",
        (edition_id, item_id),
    ).fetchone()
    if not others:
        raise AdminError("This is the series' only episode. Delete the series instead")
    conn.execute("select public.delete_item(%s)", (item_id,))


def update_item(conn: psycopg.Connection, item_id: uuid.UUID, changes: dict) -> None:
    """Changes an episode's title, or its season and episode numbers. Moving
    it to a number another episode has swaps the two, so episodes can be put
    in order."""
    edition_id, kind, season, episode = _episode(conn, item_id)
    if "episode_title" in changes:
        title = " ".join((changes["episode_title"] or "").split())[:200] or None
        conn.execute(
            "update public.items set episode_title = %s where id = %s",
            (title, item_id),
        )
    if "season" not in changes and "episode" not in changes:
        return
    if kind != "series":
        raise AdminError("A movie has no season or episode")
    new_season = changes.get("season", season)
    new_episode = changes.get("episode", episode)
    if new_season is None or new_episode is None:
        raise AdminError("An episode needs its season and episode numbers")
    if not 0 <= new_season <= 999 or not 1 <= new_episode <= 9999:
        raise AdminError("Seasons are 0 to 999, and episodes 1 to 9999")
    if (new_season, new_episode) == (season, episode):
        return
    other = conn.execute(
        """
        select id from public.items
        where edition_id = %s and season = %s and episode = %s and id <> %s
        for update
        """,
        (edition_id, new_season, new_episode, item_id),
    ).fetchone()
    if other is not None:
        # Swapped through a number nothing uses: the pair is unique.
        (free,) = conn.execute(
            """
            select n from generate_series(9999, 1, -1) n
            where not exists (select from public.items
                              where edition_id = %s and season = %s and episode = n)
            limit 1
            """,
            (edition_id, season),
        ).fetchone()
        conn.execute(
            "update public.items set episode = %s where id = %s", (free, item_id)
        )
        conn.execute(
            "update public.items set season = %s, episode = %s where id = %s",
            (season, episode, other[0]),
        )
    conn.execute(
        "update public.items set season = %s, episode = %s where id = %s",
        (new_season, new_episode, item_id),
    )
    conn.execute(
        "update public.editions set updated_at = now() where id = %s", (edition_id,)
    )


# --- Many titles at once ----------------------------------------------------------

BULK_ACTIONS = ("hide", "show", "withdraw", "credit")
BULK_MOST = 200


def bulk_change(
    conn: psycopg.Connection,
    ids: list[uuid.UUID],
    action: str,
    vj_id: uuid.UUID | None = None,
) -> dict[uuid.UUID, str | None]:
    """Does one action to each title, each on its own: a title that can't be
    changed is skipped with its reason. Each title's reason, or None."""
    if action not in BULK_ACTIONS:
        raise AdminError("The action is hide, show, withdraw or credit")
    if not 1 <= len(ids) <= BULK_MOST:
        raise AdminError(f"Choose 1 to {BULK_MOST} titles")
    if action == "credit" and vj_id is None:
        raise AdminError("Choose the VJ to credit")
    results: dict[uuid.UUID, str | None] = {}
    for edition_id in dict.fromkeys(ids):
        try:
            with conn.transaction():
                if action == "hide":
                    row = conn.execute(
                        "select status from public.editions "
                        "where id = %s and deleted_at is null",
                        (edition_id,),
                    ).fetchone()
                    if row is None:
                        raise NotFound("No such edition")
                    if row[0] != "published":
                        raise AdminError("Only a published title can be hidden")
                    editions.hide(conn, edition_id)
                elif action == "show":
                    editions.publish(conn, edition_id)
                elif action == "withdraw":
                    withdraw(conn, edition_id)
                else:
                    set_credit(conn, edition_id, vj_id)
            results[edition_id] = None
        except editions.PublishRefused as refused:
            results[edition_id] = "Still needs " + ", ".join(refused.missing)
        except EditionError as error:
            results[edition_id] = str(error)
        except psycopg.errors.UniqueViolation:
            results[edition_id] = "This VJ already has an edition of that title"
    return results


def purge_deleted(conn: psycopg.Connection) -> int:
    """Deletes the rows of deleted editions whose files are all gone."""
    return conn.execute("select public.purge_deleted_editions()").fetchone()[0]


def due_for_lookup(conn: psycopg.Connection, limit: int = 5) -> list[uuid.UUID]:
    """Drafts whose video is ready and that TMDB hasn't been asked about."""
    return [
        row[0]
        for row in conn.execute(
            """
            select e.id from public.editions e
            where e.source_id is null and e.tmdb_lookup is null
              and e.deleted_at is null and exists (
              select from public.items i join public.media_originals o
                on o.item_id = i.id
              where i.edition_id = e.id and o.state = 'ready')
            order by e.created_at
            limit %s
            """,
            (limit,),
        ).fetchall()
    ]


def set_title(conn: psycopg.Connection, edition_id: uuid.UUID, title: str) -> None:
    changed = conn.execute(
        "update public.editions set display_title = %s, updated_at = now() "
        "where id = %s",
        (editions.clean_title(title), edition_id),
    ).rowcount
    if not changed:
        raise NotFound("No such edition")


# --- TMDB lookups ------------------------------------------------------------


def lookup_failed(
    conn: psycopg.Connection, edition_id: uuid.UUID, outcome: str
) -> None:
    """Records that TMDB found nothing ('none') or couldn't be asked
    ('failed'). The draft waits for a retry, an ID or typed-in details."""
    conn.execute(
        "update public.editions set tmdb_lookup = %s, tmdb_lookup_at = now() "
        "where id = %s and source_id is null",
        (outcome, edition_id),
    )
    conn.execute("delete from public.tmdb_matches where edition_id = %s", (edition_id,))


def save_matches(
    conn: psycopg.Connection, edition_id: uuid.UUID, results: list[SearchResult]
) -> None:
    """Keeps TMDB's candidates for the admin to choose from."""
    conn.execute("delete from public.tmdb_matches where edition_id = %s", (edition_id,))
    with conn.cursor() as cur:
        cur.executemany(
            """
            insert into public.tmdb_matches (edition_id, tmdb_id, title,
              original_title, year, overview, poster_path, position)
            values (%s, %s, %s, %s, %s, %s, %s, %s)
            on conflict do nothing
            """,
            [
                (
                    edition_id,
                    r.tmdb_id,
                    r.title,
                    r.original_title,
                    r.year,
                    r.overview,
                    r.poster_path,
                    position,
                )
                for position, r in enumerate(results[:50])
            ],
        )
    conn.execute(
        "update public.editions set tmdb_lookup = 'choose', tmdb_lookup_at = now() "
        "where id = %s",
        (edition_id,),
    )


def use_source(
    conn: psycopg.Connection,
    edition_id: uuid.UUID,
    details: MovieDetails,
    *,
    trailer: str | None,
    posters: list[str],
    outcome: str,
) -> None:
    """Gives the edition this TMDB title as its source. The poster is chosen
    for the admin only when there is just one to choose from."""
    kind = _kind(conn, edition_id)
    (source_id,) = conn.execute(
        """
        insert into public.sources (kind, tmdb_id, title, original_title, overview,
          release_date, runtime_minutes, genres, poster_path, backdrop_path,
          trailer_key, tmdb_rating, tmdb_vote_count, tmdb_popularity, details_from,
          fetched_at, rating_updated_at)
        values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'tmdb',
          now(), now())
        on conflict (kind, tmdb_id) do update set
          title = excluded.title, original_title = excluded.original_title,
          overview = excluded.overview, release_date = excluded.release_date,
          runtime_minutes = excluded.runtime_minutes, genres = excluded.genres,
          poster_path = excluded.poster_path, backdrop_path = excluded.backdrop_path,
          trailer_key = excluded.trailer_key, tmdb_rating = excluded.tmdb_rating,
          tmdb_vote_count = excluded.tmdb_vote_count,
          tmdb_popularity = excluded.tmdb_popularity,
          fetched_at = excluded.fetched_at,
          rating_updated_at = excluded.rating_updated_at
        returning id
        """,
        (
            kind,
            details.tmdb_id,
            details.title[:500],
            details.original_title,
            details.overview,
            details.release_date,
            details.runtime_minutes,
            list(details.genres),
            details.poster_path,
            details.backdrop_path,
            trailer,
            details.rating,
            details.vote_count,
            details.popularity,
        ),
    ).fetchone()
    eligible = posters or ([details.poster_path] if details.poster_path else [])
    poster = eligible[0] if len(eligible) == 1 else None
    _set_source(conn, edition_id, source_id, outcome, poster)


def use_manual_details(
    conn: psycopg.Connection,
    edition_id: uuid.UUID,
    *,
    title: str,
    overview: str | None,
    year: int | None,
    genres: list[str],
    runtime_minutes: int | None,
) -> None:
    """Typed-in details, when TMDB has nothing. The poster is uploaded."""
    title = " ".join(title.split())
    if not 1 <= len(title) <= 500:
        raise AdminError("Give the source title, up to 500 characters")
    if year is not None and not 1900 <= year <= 2100:
        raise AdminError("The year is from 1900 to 2100")
    if runtime_minutes is not None and not 1 <= runtime_minutes <= 1000:
        raise AdminError("The running time is 1 to 1,000 minutes")
    genres = [" ".join(g.split())[:50] for g in genres if g.strip()][:10]
    kind = _kind(conn, edition_id)
    (source_id,) = conn.execute(
        """
        insert into public.sources (kind, title, overview, release_date,
          runtime_minutes, genres, details_from)
        values (%s, %s, %s, %s, %s, %s, 'manual') returning id
        """,
        (
            kind,
            title,
            (overview or "").strip()[:5000] or None,
            f"{year}-01-01" if year else None,
            runtime_minutes,
            genres,
        ),
    ).fetchone()
    _set_source(conn, edition_id, source_id, "manual", None)


def _kind(conn: psycopg.Connection, edition_id: uuid.UUID) -> str:
    row = conn.execute(
        "select kind from public.editions where id = %s", (edition_id,)
    ).fetchone()
    if row is None:
        raise NotFound("No such edition")
    return row[0]


def _set_source(
    conn: psycopg.Connection,
    edition_id: uuid.UUID,
    source_id: uuid.UUID,
    outcome: str,
    poster: str | None,
) -> None:
    conn.execute(
        """
        update public.editions set source_id = %s, tmdb_lookup = %s,
          tmdb_lookup_at = now(), poster_path = %s, updated_at = now()
        where id = %s
        """,
        (source_id, outcome, poster, edition_id),
    )
    conn.execute("delete from public.tmdb_matches where edition_id = %s", (edition_id,))


def source_of(
    conn: psycopg.Connection, edition_id: uuid.UUID
) -> tuple[str, int | None]:
    """The edition's kind, and its source's TMDB ID, if it has one."""
    row = conn.execute(
        """
        select e.kind, s.tmdb_id from public.editions e
        left join public.sources s on s.id = e.source_id where e.id = %s
        """,
        (edition_id,),
    ).fetchone()
    if row is None:
        raise NotFound("No such edition")
    return row


def movie_metadata_candidates(
    conn: psycopg.Connection, edition_id: uuid.UUID, query: str
) -> list[tuple[uuid.UUID, str, str | None, str | None]]:
    return conn.execute(
        """
        select e.id, e.display_title, e.poster_path, v.name
        from public.editions e
        join public.sources s on s.id = e.source_id
        left join public.vjs v on v.id = e.vj_id
        where e.kind = 'movie' and e.status = 'published' and not e.test
          and e.id <> %s
          and (strpos(lower(e.display_title), lower(%s)) > 0
               or strpos(lower(s.title), lower(%s)) > 0)
        order by e.display_title, e.id
        limit 20
        """,
        (edition_id, query, query),
    ).fetchall()


def reuse_movie_metadata(
    conn: psycopg.Connection, edition_id: uuid.UUID, donor_id: uuid.UUID
) -> None:
    changed = conn.execute(
        """
        update public.editions target
        set source_id = donor.source_id,
            poster_path = coalesce(target.poster_path, donor.poster_path),
            vj_id = coalesce(target.vj_id, donor.vj_id),
            tmdb_lookup = case
                when s.details_from = 'manual' then 'manual' else 'chosen'
            end,
            tmdb_lookup_at = now(),
            updated_at = now()
        from public.editions donor
        join public.sources s on s.id = donor.source_id
        where donor.id = %s and donor.kind = 'movie' and donor.status = 'published'
          and not donor.test and target.id = %s and target.kind = 'movie'
          and target.id <> donor.id
        """,
        (donor_id, edition_id),
    ).rowcount
    if not changed:
        raise NotFound("No published movie to reuse for this edition")
    conn.execute("delete from public.tmdb_matches where edition_id = %s", (edition_id,))


def set_poster(conn: psycopg.Connection, edition_id: uuid.UUID, path: str) -> None:
    uploaded = re.fullmatch(
        rf"posters/{edition_id}/[A-Za-z0-9_-]{{16,43}}\.(jpg|png|webp)", path
    )
    if not (TMDB_POSTER.match(path) or uploaded):
        raise AdminError("That isn't a poster VeloraUG can show")
    changed = conn.execute(
        "update public.editions set poster_path = %s, updated_at = now() where id = %s",
        (path, edition_id),
    ).rowcount
    if not changed:
        raise NotFound("No such edition")


# --- VJ credit ---------------------------------------------------------------


def credit_suggestions(
    conn: psycopg.Connection, edition_id: uuid.UUID
) -> list[Suggestion]:
    """VJs the edition's files and submitted title seem to name."""
    state = get_edition(conn, edition_id)
    sources: list[tuple[str, str | None]] = []
    for item in state.items:
        sources.append(("file name", item.filename))
        sources.append(("file tags", item.credit_hints))
    sources.append(("submitted title", state.display_title))
    return suggest_credit(sources, known_vjs(conn))


def set_credit(
    conn: psycopg.Connection, edition_id: uuid.UUID, vj_id: uuid.UUID
) -> None:
    if not conn.execute("select 1 from public.vjs where id = %s", (vj_id,)).fetchone():
        raise NotFound("No such VJ")
    changed = conn.execute(
        "update public.editions set vj_id = %s, updated_at = now() where id = %s",
        (vj_id, edition_id),
    ).rowcount
    if not changed:
        raise NotFound("No such edition")


def ready_original(conn: psycopg.Connection, item_id: uuid.UUID) -> uuid.UUID | None:
    """The item's ready original, published or not: for previews."""
    row = conn.execute(
        "select id from public.media_originals where item_id = %s and state = 'ready'",
        (item_id,),
    ).fetchone()
    return row[0] if row else None


# --- Categories --------------------------------------------------------------

MAX_CATEGORIES = 10
MAX_CATEGORY_LENGTH = 40


def normalise_category(name: str) -> str:
    """Trimmed, with single spaces. Refuses what a category can't be."""
    name = " ".join(str(name).split())
    if not name:
        raise AdminError("A category needs a name")
    if len(name) > MAX_CATEGORY_LENGTH:
        raise AdminError(
            f"A category is at most {MAX_CATEGORY_LENGTH} characters: {name[:40]}…"
        )
    if "," in name:
        raise AdminError("A category can't contain a comma")
    return name


def category_slug(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:50].strip("-")
    # A name without Latin letters or digits still gets an address.
    return slug or "category"


@dataclass(frozen=True)
class CategoryUse:
    id: uuid.UUID
    name: str
    slug: str
    editions: int


def list_categories(conn: psycopg.Connection) -> list[CategoryUse]:
    """Every category, for autocomplete: the most used first, then by name."""
    rows = conn.execute(
        """
        select c.id, c.name, c.slug, count(ec.edition_id)
        from public.categories c
        left join public.edition_categories ec on ec.category_id = c.id
        group by c.id
        order by count(ec.edition_id) desc, lower(c.name)
        """
    ).fetchall()
    return [CategoryUse(*row) for row in rows]


def edition_categories(conn: psycopg.Connection, edition_id: uuid.UUID) -> list[str]:
    return [
        name
        for (name,) in conn.execute(
            """
            select c.name from public.edition_categories ec
            join public.categories c on c.id = ec.category_id
            where ec.edition_id = %s
            order by ec.added_at, lower(c.name)
            """,
            (edition_id,),
        ).fetchall()
    ]


def _category_id(conn: psycopg.Connection, name: str) -> uuid.UUID:
    """The category with this name, whatever its case, made if it's new."""
    row = conn.execute(
        "select id from public.categories where lower(name) = lower(%s)", (name,)
    ).fetchone()
    if row:
        return row[0]
    base = category_slug(name)
    for attempt in range(20):
        slug = base if attempt == 0 else f"{base}-{attempt + 1}"
        try:
            with conn.transaction():
                return conn.execute(
                    "insert into public.categories (name, slug) values (%s, %s) "
                    "returning id",
                    (name, slug),
                ).fetchone()[0]
        except psycopg.errors.UniqueViolation as error:
            if "categories_name_idx" in str(error):
                # Made by another admin just now.
                return conn.execute(
                    "select id from public.categories where lower(name) = lower(%s)",
                    (name,),
                ).fetchone()[0]
    raise AdminError("Couldn't make an address for that category. Try another name")


def set_categories(
    conn: psycopg.Connection, edition_id: uuid.UUID, names: list[str]
) -> list[str]:
    """Replaces the edition's categories. Names are matched whatever their
    case, and new ones are made. Repeats are dropped. The saved names."""
    wanted: list[str] = []
    for name in names:
        name = normalise_category(name)
        if name.lower() not in (w.lower() for w in wanted):
            wanted.append(name)
    if len(wanted) > MAX_CATEGORIES:
        raise AdminError(f"A title has at most {MAX_CATEGORIES} categories")
    # Locks the edition, so two admins saving at once can't pass 10.
    if not conn.execute(
        "select 1 from public.editions where id = %s for update", (edition_id,)
    ).fetchone():
        raise NotFound("No such edition")
    ids = [_category_id(conn, name) for name in wanted]
    conn.execute(
        "delete from public.edition_categories "
        "where edition_id = %s and category_id <> all(%s::uuid[])",
        (edition_id, ids),
    )
    for category_id in ids:
        conn.execute(
            # clock_timestamp, so they keep the order they were given.
            "insert into public.edition_categories "
            "(edition_id, category_id, added_at) "
            "values (%s, %s, clock_timestamp()) on conflict do nothing",
            (edition_id, category_id),
        )
    return edition_categories(conn, edition_id)
