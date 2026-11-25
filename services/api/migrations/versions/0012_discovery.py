"""Discovery rails on an edition's page: popularity, new episodes, indexes.

Revision ID: 0012
Revises: 0011
Create Date: 2026-11-25

- tmdb_popularity: TMDB's attention score for a source title, the fallback
  for ranking Most popular. Part of the TMDB copy, cleared with it.
- edition_viewers(days): how many viewers played part of each published
  edition lately. Watch history is private to each viewer, so the API's role
  can't count it; this function counts for it, as the migration's owner,
  and returns counts only, never who watched.
- The API's role may read when an episode was approved, for New episodes
  this week.
- Indexes for the rails' queries.
"""

from alembic import op

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"

UPGRADE = [
    """
    alter table public.sources
      add column tmdb_popularity numeric(12, 3)
        check (tmdb_popularity >= 0)
    """,
    f"grant update (tmdb_popularity) on table public.sources to {APP_ROLE}",
    f"grant select (approved_at) on table public.items to {APP_ROLE}",
    # Counts only. "Played part of it" is a saved position, not just a
    # grant. Days are kept between 1 and 365.
    """
    create function public.edition_viewers(days integer)
    returns table (edition_id uuid, viewers bigint)
    language sql stable security definer
    set search_path = '' as $$
      select i.edition_id, count(distinct h.user_id)
      from public.watch_history h
      join public.items i on i.id = h.item_id
      join public.editions e on e.id = i.edition_id
      where e.status = 'published'
        and h.position_seconds is not null
        and h.last_watched_at >=
            now() - make_interval(days => least(greatest(days, 1), 365))
      group by i.edition_id
    $$
    """,
    "revoke all on function public.edition_viewers(integer) from public",
    f"grant execute on function public.edition_viewers(integer) to {APP_ROLE}",
    # Recommended: titles sharing a genre.
    "create index sources_genres_idx on public.sources using gin (genres)",
    # More from this VJ, newest first.
    """
    create index editions_vj_published_idx
      on public.editions (vj_id, kind, published_at desc)
      where status = 'published'
    """,
    # Counting viewers per item over the last days.
    """
    create index watch_history_item_idx
      on public.watch_history (item_id, last_watched_at)
    """,
    # New episodes this week.
    "create index items_edition_approved_idx on public.items (edition_id, approved_at)",
]

# For local test databases only. Never downgrade a hosted branch.
DOWNGRADE = [
    "drop index public.items_edition_approved_idx",
    "drop index public.watch_history_item_idx",
    "drop index public.editions_vj_published_idx",
    "drop index public.sources_genres_idx",
    "drop function public.edition_viewers(integer)",
    f"revoke select (approved_at) on table public.items from {APP_ROLE}",
    f"revoke update (tmdb_popularity) on table public.sources from {APP_ROLE}",
    "alter table public.sources drop column tmdb_popularity",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
