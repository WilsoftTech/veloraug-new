"""Settings admins change in the app, Step 13H Phase 5.

Revision ID: 0019
Revises: 0018
Create Date: 2026-11-26

One row per setting, its value as JSON, with who changed it and when. The
API checks each key and value (app/app_settings.py); the database allows
only the known keys. A key with no row has its default.

Nothing secret is kept here: Pesapal's, TMDB's and R2's keys stay in the
server's environment. So the API's role may read every setting, which it
needs for support contacts, maintenance mode and pass reminders.
"""

from alembic import op

revision = "0019"
down_revision = "0018"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"
EDITOR_ROLE = "veloraug_editor"
KEYS = (
    "support_email",
    "support_phone",
    "support_whatsapp",
    "maintenance",
    "maintenance_message",
    "payment_timeout_minutes",
    "pass_reminder_days",
    "default_language",
)

UPGRADE = [
    f"""
    create table public.app_settings (
      key text primary key check (key in ({", ".join(f"'{k}'" for k in KEYS)})),
      value jsonb not null,
      updated_by uuid,
      updated_at timestamptz not null default now()
    )
    """,
    "alter table public.app_settings enable row level security",
    "alter table public.app_settings force row level security",
    "revoke all on table public.app_settings from public",
    f"grant select, insert, update, delete on table public.app_settings "
    f"to {EDITOR_ROLE}",
    f"create policy app_settings_editor on public.app_settings for all "
    f"to {EDITOR_ROLE} using (true) with check (true)",
    f"grant select on table public.app_settings to {APP_ROLE}",
    f"create policy app_settings_app on public.app_settings for select "
    f"to {APP_ROLE} using (true)",
    # Admins see which migration the database is at, in Settings' About.
    f"grant select on table public.alembic_version to {EDITOR_ROLE}",
]

# For local test databases only. Never downgrade a hosted branch.
DOWNGRADE = [
    f"revoke select on table public.alembic_version from {EDITOR_ROLE}",
    "drop table public.app_settings",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
