"""VJ profiles: active or not, featured, their place in the list, their
links, and merging duplicates.

Revision ID: 0017
Revises: 0016
Create Date: 2026-11-26

- active: an inactive VJ is left out of the app's VJ list, and their page
  isn't found. Their titles stay, credited to them as before.
- featured: listed first in the app.
- sort_order: then by this, smallest first, then by name. Null for none.
- links: the VJ's own pages, such as {"facebook": "https://…"}. The API
  checks the names and that each is an https address.

Admins may delete a VJ: one with no titles, or one merged into another,
whose titles moved first.
"""

from alembic import op

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"
EDITOR_ROLE = "veloraug_editor"

UPGRADE = [
    """
    alter table public.vjs
      add column active boolean not null default true,
      add column featured boolean not null default false,
      add column sort_order integer check (sort_order between 1 and 9999),
      add column links jsonb not null default '{}'
        check (jsonb_typeof(links) = 'object')
    """,
    f"grant select (active, featured, sort_order, links) on table public.vjs "
    f"to {APP_ROLE}",
    f"grant delete on table public.vjs to {EDITOR_ROLE}",
]

# For local test databases only. Never downgrade a hosted branch.
DOWNGRADE = [
    f"revoke delete on table public.vjs from {EDITOR_ROLE}",
    f"revoke select (active, featured, sort_order, links) on table public.vjs "
    f"from {APP_ROLE}",
    """
    alter table public.vjs
      drop column links, drop column sort_order, drop column featured,
      drop column active
    """,
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
