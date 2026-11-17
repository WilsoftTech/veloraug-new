"""Editions and their playable items: drafts, publishing, and the test films.

Shared by the owner's script, as the database owner, and from Step 9C by the
API's admin routes, as veloraug_editor. Neither sees row-level security get
in the way: the owner bypasses it, and the editor's rules allow everything
in the catalogue. The caller commits.

An edition is a VJ's edition of a source title, a movie or a series. A movie
edition has one item; a series edition has one per episode. Upload keys and
originals belong to items. See docs/step-09a-vj-catalogue-plan.md.
"""

import uuid
from dataclasses import dataclass

import psycopg

KINDS = ("movie", "series")
DEFAULT_LANGUAGE = "lg"
# Originals that leave nothing behind in R2 once the worker has finished.
GONE = ("removed", "refused", "failed")


class EditionError(Exception):
    """A mistake the caller can fix. The message is safe to show."""


class PublishRefused(EditionError):
    """Publishing was refused. `missing` says what is still needed."""

    def __init__(self, missing: list[str]) -> None:
        super().__init__("Not ready to publish: " + "; ".join(missing))
        self.missing = missing


@dataclass(frozen=True)
class Draft:
    edition_id: uuid.UUID
    item_id: uuid.UUID
    kind: str


def _parse_id(text: str | uuid.UUID, what: str) -> uuid.UUID:
    if isinstance(text, uuid.UUID):
        return text
    try:
        return uuid.UUID(str(text))
    except ValueError:
        raise EditionError(f"{text!r} isn't {what}") from None


def clean_title(title: str) -> str:
    title = " ".join(str(title or "").split())
    if not title:
        raise EditionError("Give the title")
    if len(title) > 200:
        raise EditionError("The title is at most 200 characters")
    return title


def create_draft(
    conn: psycopg.Connection,
    *,
    kind: str,
    title: str | None = None,
    year: int | None = None,
    language: str = DEFAULT_LANGUAGE,
    series_edition: str | uuid.UUID | None = None,
    season: int | None = None,
    episode: int | None = None,
    episode_title: str | None = None,
) -> Draft:
    """A new draft: an edition and its item, or a new episode of an existing
    series edition. The upload key is made for the returned item."""
    if kind not in KINDS:
        raise EditionError("The kind is movie or series")
    if year is not None and not 1900 <= year <= 2100:
        raise EditionError("The year is from 1900 to 2100")
    if kind == "movie":
        if season is not None or episode is not None or series_edition is not None:
            raise EditionError("A movie has no season or episode")
    else:
        if season is None or episode is None:
            raise EditionError("An episode needs its season and episode numbers")
        if not 0 <= season <= 999 or not 1 <= episode <= 9999:
            raise EditionError("Seasons are 0 to 999, and episodes 1 to 9999")

    if series_edition is not None:
        edition_id = _parse_id(series_edition, "an edition ID")
        row = conn.execute(
            "select kind from public.editions where id = %s", (edition_id,)
        ).fetchone()
        if row is None:
            raise EditionError(f"No edition {edition_id}")
        if row[0] != "series":
            raise EditionError("That edition is a movie, not a series")
    else:
        if not conn.execute(
            "select 1 from public.languages where code = %s", (language,)
        ).fetchone():
            raise EditionError(f"No language {language!r}. Add it first")
        (edition_id,) = conn.execute(
            """
            insert into public.editions (kind, display_title, submitted_year, language)
            values (%s, %s, %s, %s) returning id
            """,
            (kind, clean_title(title or ""), year, language),
        ).fetchone()

    episode_title = " ".join((episode_title or "").split())[:200] or None
    try:
        with conn.transaction():
            (item_id,) = conn.execute(
                """
                insert into public.items
                  (edition_id, kind, season, episode, episode_title)
                values (%s, %s, %s, %s, %s) returning id
                """,
                (edition_id, kind, season, episode, episode_title),
            ).fetchone()
    except psycopg.errors.UniqueViolation:
        raise EditionError(
            f"Season {season} episode {episode} already exists in that series. "
            "To replace its video, make a new key for it instead"
        ) from None
    return Draft(edition_id, item_id, kind)


def find_item(conn: psycopg.Connection, key: str | uuid.UUID) -> uuid.UUID:
    """An item, named by its own ID, or by a movie edition's ID."""
    parsed = _parse_id(key, "an item or edition ID")
    row = conn.execute(
        """
        select id from public.items where id = %(id)s
        union all
        select id from public.items where edition_id = %(id)s and kind = 'movie'
        limit 1
        """,
        {"id": parsed},
    ).fetchone()
    if row is None:
        raise EditionError(
            f"No item {parsed}. For a series, name the episode's item ID"
        )
    return row[0]


def missing_for_publish(conn: psycopg.Connection, edition_id: uuid.UUID) -> list[str]:
    """What an edition still needs before it can be published. Test films,
    from before Milestone 9, need only something to watch."""
    row = conn.execute(
        """
        select e.test, e.source_id is not null, e.vj_id is not null,
               e.poster_path is not null,
               exists (select from public.items i
                       join public.media_originals o on o.item_id = i.id
                       where i.edition_id = e.id and o.state = 'ready')
        from public.editions e where e.id = %s
        """,
        (edition_id,),
    ).fetchone()
    if row is None:
        raise EditionError(f"No edition {edition_id}")
    test, has_source, has_vj, has_poster, has_video = row
    missing = []
    if not has_video:
        missing.append("a ready video")
    if not test:
        if not has_source:
            missing.append("details, from TMDB or typed in")
        if not has_poster:
            missing.append("a chosen poster")
        if not has_vj:
            missing.append("a confirmed VJ credit")
    return missing


def publish(conn: psycopg.Connection, key: str | uuid.UUID) -> uuid.UUID:
    """Publishes an edition, or refuses with what is missing. Approves its
    items that have a ready video, so a series shows its ready episodes."""
    edition_id = _parse_id(key, "an edition ID")
    missing = missing_for_publish(conn, edition_id)
    if missing:
        raise PublishRefused(missing)
    conn.execute(
        """
        update public.editions
        set status = 'published', published_at = coalesce(published_at, now()),
            updated_at = now()
        where id = %s
        """,
        (edition_id,),
    )
    conn.execute(
        """
        update public.items i set approved_at = now()
        where i.edition_id = %s and i.approved_at is null
          and exists (select from public.media_originals o
                      where o.item_id = i.id and o.state = 'ready')
        """,
        (edition_id,),
    )
    return edition_id


def hide(conn: psycopg.Connection, key: str | uuid.UUID) -> uuid.UUID:
    edition_id = _parse_id(key, "an edition ID")
    changed = conn.execute(
        """
        update public.editions set status = 'hidden', updated_at = now()
        where id = %s and status = 'published'
        """,
        (edition_id,),
    ).rowcount
    if (
        not changed
        and not conn.execute(
            "select 1 from public.editions where id = %s", (edition_id,)
        ).fetchone()
    ):
        raise EditionError(f"No edition {edition_id}")
    return edition_id


def approve_item(conn: psycopg.Connection, key: str | uuid.UUID) -> uuid.UUID:
    """Shows a new episode of a published series, once its video is ready."""
    item_id = _parse_id(key, "an item ID")
    row = conn.execute(
        """
        select exists (select from public.media_originals o
                       where o.item_id = i.id and o.state = 'ready')
        from public.items i where i.id = %s
        """,
        (item_id,),
    ).fetchone()
    if row is None:
        raise EditionError(f"No item {item_id}")
    if not row[0]:
        raise PublishRefused(["a ready video"])
    conn.execute(
        "update public.items set approved_at = coalesce(approved_at, now()) "
        "where id = %s",
        (item_id,),
    )
    return item_id


@dataclass(frozen=True)
class TestFilmsDeletion:
    """Where deleting the test films has got to."""

    editions: int
    marked_for_removal: int
    still_removing: int
    deleted: bool


def delete_test_films(conn: psycopg.Connection) -> TestFilmsDeletion:
    """Deletes the films from before Milestone 9, in two runs.

    The first hides them and marks their videos 'removing', so the media
    worker deletes their files from R2. Once none is still on its way out, a
    later run deletes their rows. Owner only: it deletes keys and originals.
    """
    editions = [
        row[0]
        for row in conn.execute("select id from public.editions where test").fetchall()
    ]
    if not editions:
        return TestFilmsDeletion(0, 0, 0, False)
    conn.execute(
        "update public.editions set status = 'hidden', updated_at = now() "
        "where test and status = 'published'"
    )
    marked = conn.execute(
        f"""
        update public.media_originals set state = 'removing', updated_at = now()
        where item_id in (select i.id from public.items i
                          join public.editions e on e.id = i.edition_id
                          where e.test)
          and state not in ({", ".join(["%s"] * len(GONE))}, 'removing')
        """,
        GONE,
    ).rowcount
    (still,) = conn.execute(
        f"""
        select count(*) from public.media_originals o
        join public.items i on i.id = o.item_id
        join public.editions e on e.id = i.edition_id
        where e.test and o.state not in ({", ".join(["%s"] * len(GONE))})
        """,
        GONE,
    ).fetchone()
    if still:
        return TestFilmsDeletion(len(editions), marked, still, False)
    test_items = (
        "select i.id from public.items i join public.editions e "
        "on e.id = i.edition_id where e.test"
    )
    conn.execute(
        "delete from public.media_renditions where original_id in "
        f"(select id from public.media_originals where item_id in ({test_items}))"
    )
    conn.execute(f"delete from public.media_originals where item_id in ({test_items})")
    conn.execute(f"delete from public.upload_keys where item_id in ({test_items})")
    sources = [
        row[0]
        for row in conn.execute(
            "select distinct source_id from public.editions "
            "where test and source_id is not null"
        ).fetchall()
    ]
    conn.execute(f"delete from public.items where id in ({test_items})")
    conn.execute("delete from public.editions where test")
    # A source another edition still uses is kept.
    conn.execute(
        """
        delete from public.sources s where s.id = any(%s)
          and not exists (select from public.editions e where e.source_id = s.id)
        """,
        (sources,),
    )
    return TestFilmsDeletion(len(editions), marked, 0, True)
