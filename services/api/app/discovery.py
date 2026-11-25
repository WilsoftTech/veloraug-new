"""Discovery rails on an edition's page, ranked in SQL.

Every rail leaves out the edition itself, other VJs' editions of the same
source title, test films, and TMDB copies too old to show. A rail with fewer
than MIN_RAIL titles isn't returned. See docs/step-13c-discovery-rails-report.md
for the scoring.

Reads run in Database.anonymous(), where row-level security shows published
editions only, except Because you watched, which reads the viewer's own
history in Database.as_user().
"""

from dataclasses import dataclass
from uuid import UUID

import psycopg

from app.viewer import (
    _AGES,
    _FROM,
    _SERVABLE,
    _SUMMARY,
    _SUMMARY_COLUMNS,
    MIN_VOTES,
    EditionSummary,
)

RAIL_SIZE = 12
MIN_RAIL = 3
# Most popular counts viewers over this many days.
POPULAR_DAYS = 30
# New episodes: approved within this many days.
NEW_EPISODE_DAYS = 7
# Recommended: a bonus for titles published within this many days.
RECENT_DAYS = 30

# Rails in the order the page shows them.
MOVIE_RAILS = ("vj", "recommended", "popular", "top_rated", "recent")
SERIES_RAILS = ("vj", "recommended", "popular", "top_rated", "new_episodes")


@dataclass(frozen=True)
class Seed:
    """What rails are ranked against: an edition's kind, VJ, source and
    genres."""

    id: UUID
    kind: str
    title: str
    vj_id: UUID | None
    source_id: UUID | None
    genres: list[str]


@dataclass(frozen=True)
class Rail:
    key: str
    editions: list[EditionSummary]


def _seed(conn: psycopg.Connection, edition_id: UUID) -> Seed | None:
    row = conn.execute(
        f"""
        select e.id, e.kind,
               case when e.test then s.title else e.display_title end,
               e.vj_id, e.source_id, s.genres
        {_FROM}
        where e.id = %(id)s and {_SERVABLE}
        """,
        {**_AGES, "id": edition_id},
    ).fetchone()
    if row is None:
        return None
    return Seed(*row[:5], genres=list(row[5] or ()))


# The score of a candidate for Recommended: 3 points per shared genre, 1 for
# the same VJ, up to 1 for TMDB's rating (only from MIN_VOTES votes), and 0.5
# if published lately. A candidate must share at least one genre.
_SCORE = f"""
    3 * cardinality(array(
          select unnest(s.genres) intersect select unnest(%(genres)s::text[])))
    + case when e.vj_id = %(vj)s then 1 else 0 end
    + coalesce(case when s.tmdb_vote_count >= {MIN_VOTES}
                    then s.tmdb_rating end, 0) / 10.0
    + case when e.published_at >= now() - make_interval(days => {RECENT_DAYS})
           then 0.5 else 0 end
"""


def _rail(
    conn: psycopg.Connection,
    seed: Seed,
    *,
    where: str = "true",
    order: str,
    joins: str = "",
    exclude: tuple[UUID, ...] = (),
    exclude_sources: tuple[UUID, ...] = (),
) -> list[EditionSummary]:
    """Published editions of the seed's kind, ranked by `order`."""
    rows = conn.execute(
        f"""
        select {_SUMMARY} {_FROM} {joins}
        where {_SERVABLE} and not e.test and e.kind = %(kind)s
          and e.id <> all(%(exclude)s::uuid[])
          and (e.source_id is null
               or e.source_id <> all(%(exclude_sources)s::uuid[]))
          and ({where})
        order by {order}, e.id
        limit %(limit)s
        """,
        {
            **_AGES,
            "kind": seed.kind,
            "vj": seed.vj_id,
            "genres": seed.genres,
            "exclude": [seed.id, *exclude],
            "exclude_sources": [
                s for s in (seed.source_id, *exclude_sources) if s is not None
            ],
            "limit": RAIL_SIZE,
        },
    ).fetchall()
    return [EditionSummary(*row[:_SUMMARY_COLUMNS]) for row in rows]


def recommended(
    conn: psycopg.Connection,
    seed: Seed,
    *,
    exclude: tuple[UUID, ...] = (),
    exclude_sources: tuple[UUID, ...] = (),
) -> list[EditionSummary]:
    if not seed.genres:
        return []
    return _rail(
        conn,
        seed,
        # && can use the GIN index on genres.
        where="s.genres && %(genres)s::text[]",
        order=f"({_SCORE}) desc, e.published_at desc",
        exclude=exclude,
        exclude_sources=exclude_sources,
    )


def _ranked(conn: psycopg.Connection, seed: Seed, key: str) -> list[EditionSummary]:
    if key == "vj":
        if seed.vj_id is None:
            return []
        return _rail(conn, seed, where="e.vj_id = %(vj)s", order="e.published_at desc")
    if key == "recommended":
        return recommended(conn, seed)
    if key == "popular":
        # Our own viewers first; TMDB's popularity only orders the rest.
        return _rail(
            conn,
            seed,
            joins=f"left join public.edition_viewers({POPULAR_DAYS}) pv "
            "on pv.edition_id = e.id",
            order="coalesce(pv.viewers, 0) desc, s.tmdb_popularity desc nulls last, "
            "e.published_at desc",
        )
    if key == "top_rated":
        return _rail(
            conn,
            seed,
            where=f"s.tmdb_vote_count >= {MIN_VOTES}",
            order="s.tmdb_rating desc, s.tmdb_vote_count desc",
        )
    if key == "recent":
        return _rail(conn, seed, order="e.published_at desc")
    if key == "new_episodes":
        return _rail(
            conn,
            seed,
            joins="cross join lateral (select max(i.approved_at) as latest "
            "from public.items i where i.edition_id = e.id) ne",
            where=f"ne.latest >= now() - make_interval(days => {NEW_EPISODE_DAYS})",
            order="ne.latest desc",
        )
    raise ValueError(f"No rail {key}")


def rails(conn: psycopg.Connection, edition_id: UUID) -> list[Rail] | None:
    """The edition's rails with at least MIN_RAIL titles, in page order, or
    None if the edition isn't published or can't be shown."""
    seed = _seed(conn, edition_id)
    if seed is None:
        return None
    keys = MOVIE_RAILS if seed.kind == "movie" else SERIES_RAILS
    found = [Rail(key, _ranked(conn, seed, key)) for key in keys]
    return [rail for rail in found if len(rail.editions) >= MIN_RAIL]


@dataclass(frozen=True)
class BecauseYouWatched:
    watched_id: UUID
    watched_title: str
    editions: list[EditionSummary]


def because_you_watched(
    conn: psycopg.Connection, edition_id: UUID
) -> BecauseYouWatched | None:
    """Titles like the one the viewer played most recently, other than this
    edition, or None without one or with fewer than MIN_RAIL. Runs as the
    viewer, whose history only they can see."""
    current = _seed(conn, edition_id)
    if current is None:
        return None
    row = conn.execute(
        f"""
        select e.id
        from public.watch_history h
        join public.items i on i.id = h.item_id
        join public.editions e on e.id = i.edition_id
        join public.sources s on s.id = e.source_id
        where e.id <> %(id)s and not e.test and {_SERVABLE}
          and h.position_seconds is not null
        order by h.last_watched_at desc
        limit 1
        """,
        {**_AGES, "id": edition_id},
    ).fetchone()
    watched = _seed(conn, row[0]) if row else None
    if watched is None:
        return None
    editions = recommended(
        conn,
        watched,
        exclude=(current.id,),
        exclude_sources=(current.source_id,) if current.source_id else (),
    )
    if len(editions) < MIN_RAIL:
        return None
    return BecauseYouWatched(watched.id, watched.title, editions)
