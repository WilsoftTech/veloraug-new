"""Account hub: watch history, notification read marks, account deletion.

Revision ID: 0009
Revises: 0008
Create Date: 2026-11-24

Hand-written SQL. Forward only on hosted branches.

- `watch_history`: one row per account and item, so replays and retries
  update the same row instead of adding more. The API writes it when it
  grants playback, and the player saves where it got to now and then.
  No foreign key to items: a title that is unpublished or deleted simply
  stops being listed, because the API's role can't see it.
- `notification_reads`: which notifications the viewer has read. The
  notifications themselves aren't stored: the API builds them from the
  viewer's own payments, passes and devices, so only real events appear.
- `account_deletions`: one row per account that asked to be deleted, so a
  deletion that stops part way can be retried safely, and finished once.
  It holds the account's ID and times only.
- The API's role may delete its own profile, history and read marks, for
  account deletion. Payments and passes are kept. See docs/viewer-app-upgrade.md.

Every table has row-level security: the API's role sees and changes the
signed-in viewer's rows only.
"""

from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"
OWN = "user_id = public.current_app_user_id()"

UPGRADE = [
    """
    create table public.watch_history (
      user_id uuid not null,
      item_id uuid not null,
      first_watched_at timestamptz not null default now(),
      last_watched_at timestamptz not null default now(),
      -- Where the player got to, in whole seconds, and when it said so.
      position_seconds integer check (position_seconds between 0 and 86400),
      position_at timestamptz,
      -- Played to the end: no Resume is offered.
      finished boolean not null default false,
      primary key (user_id, item_id)
    )
    """,
    "create index watch_history_recent_idx on public.watch_history "
    "(user_id, last_watched_at desc)",
    """
    create table public.notification_reads (
      user_id uuid not null,
      notification_id text not null
        check (notification_id ~ '^[a-z_.]{3,40}:[0-9a-f-]{36}$'),
      read_at timestamptz not null default now(),
      primary key (user_id, notification_id)
    )
    """,
    """
    create table public.account_deletions (
      user_id uuid primary key,
      requested_at timestamptz not null default now(),
      attempts integer not null default 1 check (attempts between 1 and 1000),
      -- VeloraUG's own rows removed: profile, history, read marks, devices
      -- and sessions ended.
      data_removed_at timestamptz,
      -- The sign-in account removed at the identity provider.
      identity_removed_at timestamptz,
      completed_at timestamptz,
      check (completed_at is null
             or (data_removed_at is not null and identity_removed_at is not null))
    )
    """,
    *(
        statement
        for table in ("watch_history", "notification_reads", "account_deletions")
        for statement in (
            f"alter table public.{table} enable row level security",
            f"alter table public.{table} force row level security",
            f"revoke all on table public.{table} from public",
        )
    ),
    f"grant select, insert, delete on table public.watch_history to {APP_ROLE}",
    f"grant update (last_watched_at, position_seconds, position_at, finished) "
    f"on table public.watch_history to {APP_ROLE}",
    f"create policy watch_history_app_own on public.watch_history for all "
    f"to {APP_ROLE} using ({OWN}) with check ({OWN})",
    f"grant select, insert, delete on table public.notification_reads to {APP_ROLE}",
    f"create policy notification_reads_app_own on public.notification_reads "
    f"for all to {APP_ROLE} using ({OWN}) with check ({OWN})",
    f"grant select, insert on table public.account_deletions to {APP_ROLE}",
    f"grant update (attempts, data_removed_at, identity_removed_at, completed_at) "
    f"on table public.account_deletions to {APP_ROLE}",
    f"create policy account_deletions_app_own on public.account_deletions "
    f"for all to {APP_ROLE} using ({OWN}) with check ({OWN})",
    # Account deletion removes the profile.
    f"grant delete on table public.profiles to {APP_ROLE}",
    f"create policy profiles_delete_own on public.profiles for delete "
    f"to {APP_ROLE} using ({OWN})",
]

# For local test databases only. Never downgrade a hosted branch: fix
# mistakes with a new migration.
DOWNGRADE = [
    "drop policy profiles_delete_own on public.profiles",
    f"revoke delete on table public.profiles from {APP_ROLE}",
    "drop table public.account_deletions",
    "drop table public.notification_reads",
    "drop table public.watch_history",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
