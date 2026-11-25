"""Lets the API read how long a ready video is, for episode running times.

Revision ID: 0014
Revises: 0013
Create Date: 2026-11-25

The media worker measures each original's duration when it converts it.
Episode rows show it as a running time, more accurate than TMDB's figure.
The API's role could already see ready originals of published, approved
items (their ID, item and state); this adds only their duration.
"""

from alembic import op

revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"

UPGRADE = [
    f"grant select (duration_seconds) on table public.media_originals to {APP_ROLE}",
]

# For local test databases only. Never downgrade a hosted branch.
DOWNGRADE = [
    f"revoke select (duration_seconds) on table public.media_originals from {APP_ROLE}",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
