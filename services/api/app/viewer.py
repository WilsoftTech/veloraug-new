"""What viewers see from Step 9D: VJs, editions, seasons and episodes.

Reads run in Database.anonymous(), where row-level security shows the API's
role published editions, their sources, their VJs and their approved items
only. A source from TMDB whose copy is older than SERVE_FOR isn't shown,
as in Milestone 6. See docs/step-09a-vj-catalogue-plan.md, section 5.
"""

import re
import unicodedata
from dataclasses import dataclass, field
from uuid import UUID

import psycopg

from app.catalogue import REFRESH_AFTER, SERVE_FOR

_AGES = {"refresh_after": REFRESH_AFTER, "serve_for": SERVE_FOR}

_SERVABLE = "(s.details_from = 'manual' or s.fetched_at >= now() - %(serve_for)s)"

# TMDB's rating is shown only from this many votes: a handful of votes on a
# small film gives a misleading 10.0.
MIN_VOTES = 10

_SUMMARY = f"""
    e.id, e.kind,
    case when e.test then s.title else e.display_title end,
    extract(year from s.release_date)::int,
    case when e.test then s.poster_path else e.poster_path end,
    v.name, v.slug, e.language, l.name, e.test,
    case when s.tmdb_vote_count >= {MIN_VOTES} then s.tmdb_rating::float8 end,
    case when s.tmdb_vote_count >= {MIN_VOTES} then s.tmdb_vote_count end
"""
_SUMMARY_COLUMNS = 12

_FROM = """
    from public.editions e
    join public.sources s on s.id = e.source_id
    join public.languages l on l.code = e.language
    left join public.vjs v on v.id = e.vj_id
"""


@dataclass(frozen=True)
class EditionSummary:
    id: UUID
    kind: str
    title: str
    year: int | None
    poster_path: str | None
    vj_name: str | None
    vj_slug: str | None
    language: str
    language_name: str
    test: bool
    # TMDB's score for the source title, out of 10, and its votes. None
    # below MIN_VOTES, for typed-in details, or when TMDB has none.
    rating: float | None = None
    vote_count: int | None = None

    @property
    def label(self) -> str:
        """ "Luganda · VJ Junior", as the edition's page shows it."""
        if self.test or not self.vj_name:
            return "Test"
        return f"{self.language_name} · {self.vj_name}"


@dataclass(frozen=True)
class Episode:
    item_id: UUID
    season: int
    episode: int
    title: str | None
    playable: bool


@dataclass
class EditionDetail:
    summary: EditionSummary
    source_title: str
    overview: str | None
    runtime_minutes: int | None
    genres: list[str]
    backdrop_path: str | None
    trailer_key: str | None
    tmdb_id: int | None
    details_from: str
    stale: bool
    vj_id: UUID | None
    vj_photo_path: str | None
    # A movie's one item, or None for a series.
    movie_item: UUID | None = None
    playable: bool = False
    episodes: list[Episode] = field(default_factory=list)


class DetailsUnavailable(Exception):
    """Published, but its TMDB copy is missing or too old to show."""

    def __init__(self, kind: str, tmdb_id: int) -> None:
        super().__init__(kind, tmdb_id)
        self.kind, self.tmdb_id = kind, tmdb_id


def _like(text: str) -> str:
    return text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def list_editions(
    conn: psycopg.Connection,
    *,
    limit: int,
    offset: int,
    kind: str | None = None,
    vj: str | None = None,
    language: str | None = None,
    genre: str | None = None,
    query: str | None = None,
) -> list[EditionSummary]:
    """Published editions, newest first; when searching, titles that start
    with the query first. `vj` is a VJ's slug."""
    where = [_SERVABLE]
    params: dict = {**_AGES, "limit": limit, "offset": offset}
    if kind:
        where.append("e.kind = %(kind)s")
        params["kind"] = kind
    if vj:
        where.append("v.slug = %(vj)s")
        params["vj"] = vj
    if language:
        where.append("e.language = %(language)s")
        params["language"] = language
    if genre:
        where.append("%(genre)s = any(s.genres)")
        params["genre"] = genre
    order = "e.published_at desc, e.id"
    if query:
        title = "lower(case when e.test then s.title else e.display_title end)"
        params["contains"] = f"%{_like(query.lower())}%"
        params["starts"] = f"{_like(query.lower())}%"
        where.append(
            f"({title} like %(contains)s or lower(s.title) like %(contains)s "
            "or lower(coalesce(v.name, '')) like %(contains)s)"
        )
        order = f"{title} like %(starts)s desc, {title}, e.published_at desc"
    rows = conn.execute(
        f"""
        select {_SUMMARY} {_FROM}
        where {" and ".join(where)}
        order by {order}
        limit %(limit)s offset %(offset)s
        """,
        params,
    ).fetchall()
    return [EditionSummary(*row) for row in rows]


def get_edition(conn: psycopg.Connection, edition_id: UUID) -> EditionDetail | None:
    """One published edition with its episodes, or None. DetailsUnavailable
    if its TMDB copy can't be shown."""
    row = conn.execute(
        f"""
        select {_SUMMARY}, s.title, s.overview, s.runtime_minutes, s.genres,
               s.backdrop_path, s.trailer_key, s.tmdb_id, s.details_from,
               s.details_from = 'tmdb'
                 and coalesce(s.fetched_at < now() - %(refresh_after)s, true),
               v.id, v.photo_path, {_SERVABLE}
        {_FROM}
        where e.id = %(id)s
        """,
        {**_AGES, "id": edition_id},
    ).fetchone()
    if row is None:
        return None
    summary = EditionSummary(*row[:_SUMMARY_COLUMNS])
    (
        source_title,
        overview,
        runtime,
        genres,
        backdrop,
        trailer,
        tmdb_id,
        details_from,
        stale,
        vj_id,
        photo,
        servable,
    ) = row[_SUMMARY_COLUMNS:]
    if not servable:
        raise DetailsUnavailable(summary.kind, tmdb_id)
    detail = EditionDetail(
        summary=summary,
        source_title=source_title,
        overview=overview,
        runtime_minutes=runtime,
        genres=list(genres or ()),
        backdrop_path=backdrop,
        trailer_key=trailer,
        tmdb_id=tmdb_id,
        details_from=details_from,
        stale=bool(stale),
        vj_id=vj_id,
        vj_photo_path=photo,
    )
    items = conn.execute(
        """
        select i.id, i.season, i.episode, i.episode_title,
               exists (select from public.media_originals o where o.item_id = i.id)
        from public.items i where i.edition_id = %s
        order by i.season nulls first, i.episode nulls first
        """,
        (edition_id,),
    ).fetchall()
    if summary.kind == "movie":
        if items:
            detail.movie_item, detail.playable = items[0][0], items[0][4]
    else:
        detail.episodes = [Episode(*item) for item in items]
        detail.playable = any(episode.playable for episode in detail.episodes)
    return detail


# How many titles Home's hero shows.
FEATURED_COUNT = 3


@dataclass(frozen=True)
class Featured:
    """A title for Home's hero: a summary, with what the hero adds."""

    summary: EditionSummary
    genres: list[str]
    backdrop_path: str | None
    # A movie's one item, to play. None for a series.
    movie_item: UUID | None


def list_featured(
    conn: psycopg.Connection, limit: int = FEATURED_COUNT
) -> list[Featured]:
    """The newest published editions with something to watch, test films
    left out. Row-level security shows the API's role only approved items
    and ready originals, so the exists() means "playable"."""
    rows = conn.execute(
        f"""
        select {_SUMMARY}, s.genres, s.backdrop_path,
               (select i.id from public.items i
                where i.edition_id = e.id and e.kind = 'movie' limit 1)
        {_FROM}
        where not e.test and {_SERVABLE}
          and exists (
            select from public.items i
            join public.media_originals o on o.item_id = i.id
            where i.edition_id = e.id)
        order by e.published_at desc, e.id
        limit %(limit)s
        """,
        {**_AGES, "limit": limit},
    ).fetchall()
    return [
        Featured(
            summary=EditionSummary(*row[:_SUMMARY_COLUMNS]),
            genres=list(row[_SUMMARY_COLUMNS] or ()),
            backdrop_path=row[_SUMMARY_COLUMNS + 1],
            movie_item=row[_SUMMARY_COLUMNS + 2],
        )
        for row in rows
    ]


@dataclass(frozen=True)
class VjSummary:
    id: UUID
    name: str
    slug: str
    photo_path: str | None
    bio: str | None
    editions: int


def list_vjs(conn: psycopg.Connection) -> list[VjSummary]:
    """VJs with at least one published edition, by name."""
    rows = conn.execute(
        """
        select v.id, v.name, v.slug, v.photo_path, v.bio,
               (select count(*) from public.editions e where e.vj_id = v.id)
        from public.vjs v
        order by lower(v.name)
        """
    ).fetchall()
    return [VjSummary(*row) for row in rows]


def get_vj(conn: psycopg.Connection, slug: str) -> VjSummary | None:
    row = conn.execute(
        """
        select v.id, v.name, v.slug, v.photo_path, v.bio,
               (select count(*) from public.editions e where e.vj_id = v.id)
        from public.vjs v where v.slug = %s
        """,
        (slug,),
    ).fetchone()
    return VjSummary(*row) if row else None


def list_languages(conn: psycopg.Connection) -> list[tuple[str, str, int]]:
    """Languages with published editions, Luganda first."""
    return conn.execute(
        """
        select l.code, l.name, count(e.id)
        from public.languages l join public.editions e on e.language = l.code
        where not e.test
        group by l.code, l.name
        order by l.code = 'lg' desc, l.name
        """
    ).fetchall()


def list_genres(conn: psycopg.Connection) -> list[tuple[str, int]]:
    """Genres of published editions whose details can be shown, exactly as
    the catalogue stores them, most editions first. The values are the ones
    list_editions' `genre` matches."""
    return conn.execute(
        f"""
        select g.name, count(distinct e.id)
        {_FROM}
        cross join lateral unnest(s.genres) as g(name)
        where not e.test and {_SERVABLE} and g.name <> ''
        group by g.name
        order by count(distinct e.id) desc, g.name
        """,
        _AGES,
    ).fetchall()


def playable_item(conn: psycopg.Connection, item_id: UUID) -> bool:
    """True if the item belongs to a published edition and is approved."""
    return (
        conn.execute("select 1 from public.items where id = %s", (item_id,)).fetchone()
        is not None
    )


def download_name(conn: psycopg.Connection, item_id: UUID) -> str:
    """A file name for an item's download, without its quality or ending:
    "Fast X - VJ Junior", or "Kabaka - S01E02 - VJ Emmy" for an episode.
    Plain ASCII, so every phone, computer and browser keeps it as it is."""
    row = conn.execute(
        "select edition_id, season, episode from public.items where id = %s",
        (item_id,),
    ).fetchone()
    if row is None:
        return "VeloraUG"
    edition_id, season, episode = row
    try:
        detail = get_edition(conn, edition_id)
    except DetailsUnavailable:
        detail = None
    parts = [detail.summary.title if detail else "VeloraUG"]
    if season is not None and episode is not None:
        parts.append(f"S{season:02d}E{episode:02d}")
    if detail and detail.summary.vj_name:
        parts.append(detail.summary.vj_name)
    return safe_file_name(" - ".join(parts))


def safe_file_name(text: str, limit: int = 100) -> str:
    """Letters, digits, spaces and . , ' ( ) - only, accents dropped."""
    plain = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    kept = re.sub(r"[^A-Za-z0-9 .,'()-]+", " ", plain)
    kept = re.sub(r"\s+", " ", kept).strip(" .-")
    return kept[:limit].rstrip(" .-") or "VeloraUG"
