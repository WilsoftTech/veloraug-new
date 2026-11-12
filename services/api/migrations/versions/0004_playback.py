"""Playback: the API can see which published movies are ready to watch.

Revision ID: 0004
Revises: 0003
Create Date: 2026-11-12

Hand-written SQL, from docs/step-08a-playback-plan.md, "Database". The API's
role reads three columns of ready originals of published movies: enough to
grant a viewing and build its path in R2. Nothing about uploads, keys,
qualities, or originals in any other state.
"""

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"

UPGRADE = [
    f"grant select (id, movie_id, state) on table public.media_originals to {APP_ROLE}",
    # The subquery runs under the API's own rules on movies, which show it
    # published movies only.
    f"""
    create policy originals_app_ready on public.media_originals
      for select to {APP_ROLE}
      using (state = 'ready' and exists (
        select from public.movies m
        where m.id = media_originals.movie_id and m.published
      ))
    """,
]

# For local test databases only. Never downgrade a hosted branch: fix
# mistakes with a new migration.
DOWNGRADE = [
    "drop policy originals_app_ready on public.media_originals",
    f"revoke select on table public.media_originals from {APP_ROLE}",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
