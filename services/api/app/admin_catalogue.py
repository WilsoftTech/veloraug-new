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
    editions: int


def list_vjs(conn: psycopg.Connection) -> list[Vj]:
    rows = conn.execute(
        """
        select v.id, v.name, v.slug, v.match_names, v.photo_path, v.bio,
               (select count(*) from public.editions e where e.vj_id = v.id)
        from public.vjs v order by lower(v.name)
        """
    ).fetchall()
    return [Vj(*row) for row in rows]


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
    items: list[ItemState] = field(default_factory=list)
    missing: list[str] = field(default_factory=list)
    matches: list[SearchResult] = field(default_factory=list)


_EDITION = """
    select e.id, e.kind, e.display_title, e.submitted_year, e.language,
           e.status, e.test, e.tmdb_lookup, e.source_id, s.tmdb_id, s.title,
           extract(year from s.release_date)::int, s.overview, s.poster_path,
           s.details_from, e.poster_path, e.vj_id, v.name, e.created_at
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
               o.filename, o.credit_hints
        from public.items i
        left join lateral (
          select state, reason, filename, credit_hints from public.media_originals
          where item_id = i.id order by created_at desc limit 1
        ) o on true
        where i.edition_id = %s
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
    row = conn.execute(_EDITION + " where e.id = %s", (edition_id,)).fetchone()
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
    return state


def list_work(conn: psycopg.Connection) -> list[EditionState]:
    """Editions that need an admin: every draft and hidden edition, and
    published series with an episode waiting for approval. Newest first."""
    ids = conn.execute(
        """
        select e.id from public.editions e
        where e.status <> 'published'
           or exists (select from public.items i where i.edition_id = e.id
                      and i.approved_at is null)
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
                  from public.items i where i.edition_id = e.id),
                 '{}')
        from public.editions e
        left join public.vjs v on v.id = e.vj_id
        where e.kind = 'series' and not e.test
        order by e.created_at desc
        limit 1000
        """
    ).fetchall()
    return [
        SeriesRef(*row[:6], episodes=[(pair[0], pair[1]) for pair in row[6]])
        for row in rows
    ]


def due_for_lookup(conn: psycopg.Connection, limit: int = 5) -> list[uuid.UUID]:
    """Drafts whose video is ready and that TMDB hasn't been asked about."""
    return [
        row[0]
        for row in conn.execute(
            """
            select e.id from public.editions e
            where e.source_id is null and e.tmdb_lookup is null and exists (
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
          trailer_key, tmdb_rating, tmdb_vote_count, details_from, fetched_at,
          rating_updated_at)
        values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'tmdb', now(),
          now())
        on conflict (kind, tmdb_id) do update set
          title = excluded.title, original_title = excluded.original_title,
          overview = excluded.overview, release_date = excluded.release_date,
          runtime_minutes = excluded.runtime_minutes, genres = excluded.genres,
          poster_path = excluded.poster_path, backdrop_path = excluded.backdrop_path,
          trailer_key = excluded.trailer_key, tmdb_rating = excluded.tmdb_rating,
          tmdb_vote_count = excluded.tmdb_vote_count,
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
