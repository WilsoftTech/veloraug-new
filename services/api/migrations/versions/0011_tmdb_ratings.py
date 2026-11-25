"""TMDB's rating for each source title.

Revision ID: 0011
Revises: 0010
Create Date: 2026-11-25

The rating is TMDB's audience score for the source film or series, not for a
VJ's edition of it. It is part of the TMDB copy, so the same rules apply: it
is refreshed with the rest of the copy and cleared with it at 180 days.

rating_updated_at says when TMDB was last asked, even if it had no rating, so
the backfill script knows which sources it has already done.
"""

from alembic import op

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"

UPGRADE = [
    """
    alter table public.sources
      add column tmdb_rating numeric(3, 1)
        check (tmdb_rating between 0 and 10),
      add column tmdb_vote_count integer
        check (tmdb_vote_count >= 0),
      add column rating_updated_at timestamptz,
      add constraint sources_rating_with_votes
        check ((tmdb_rating is null) = (tmdb_vote_count is null))
    """,
    # The API's background refresh writes the copy column by column (0005).
    f"""
    grant update (tmdb_rating, tmdb_vote_count, rating_updated_at)
      on table public.sources to {APP_ROLE}
    """,
]

# For local test databases only. Never downgrade a hosted branch.
DOWNGRADE = [
    f"""
    revoke update (tmdb_rating, tmdb_vote_count, rating_updated_at)
      on table public.sources from {APP_ROLE}
    """,
    """
    alter table public.sources
      drop constraint sources_rating_with_votes,
      drop column rating_updated_at,
      drop column tmdb_vote_count,
      drop column tmdb_rating
    """,
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
