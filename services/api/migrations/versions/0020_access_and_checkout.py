"""Security Phase 1: downloads, checkout attempts and admin removals.

Revision ID: 0020
Revises: 0019
Create Date: 2026-11-27

VUG-SEC-001. A download grant no longer opens the master playlist, so the
API tells the app which qualities an item has. The API's role reads each
quality's height for a ready original it can already see, and nothing more.

VUG-SEC-004. A checkout is reserved in the database before Pesapal is asked
for an order. The app names each attempt, and one viewer's attempt makes at
most one payment. A submission whose answer was lost is matched later by
Pesapal's notification, which carries the payment's ID as its reference:
the API's role may read that one payment, only while it is still waiting
for a tracking ID, by the reference set for the transaction.

VUG-SEC-011. Removing admins takes one lock first, so two removals at once
are judged one after the other and the last admin always stays.

Additive only: the new column is nullable and old rows keep working.
"""

from alembic import op

revision = "0020"
down_revision = "0019"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"

UPGRADE = [
    # --- VUG-SEC-001 ---------------------------------------------------------
    f"grant select (original_id, height) on table public.media_renditions "
    f"to {APP_ROLE}",
    f"""
    create policy renditions_app_ready on public.media_renditions
      for select to {APP_ROLE}
      using (exists (
        select from public.media_originals o
        where o.id = media_renditions.original_id
      ))
    """,
    # --- VUG-SEC-004 ---------------------------------------------------------
    "alter table public.payments add column attempt_id uuid",
    """
    create unique index payments_attempt_idx
      on public.payments (user_id, attempt_id) where attempt_id is not null
    """,
    f"""
    create policy payments_app_by_reference on public.payments for select
      to {APP_ROLE}
      using (
        state = 'started' and tracking_id is null
        and id = nullif(current_setting('app.payment_reference', true), '')::uuid
      )
    """,
    # --- VUG-SEC-011 ---------------------------------------------------------
    # Before the statement, so a second removal waits for the first to
    # commit. keep_one_admin, after it, then sees what the first removed.
    """
    create function public.lock_admin_removals()
    returns trigger language plpgsql set search_path = '' as $$
    begin
      perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('veloraug.admins.remove', 0));
      return null;
    end;
    $$
    """,
    "revoke all on function public.lock_admin_removals() from public",
    """
    create trigger admins_lock_removals before delete on public.admins
      for each statement execute function public.lock_admin_removals()
    """,
]

# For local test databases only. Never downgrade a hosted branch.
DOWNGRADE = [
    "drop trigger admins_lock_removals on public.admins",
    "drop function public.lock_admin_removals()",
    "drop policy payments_app_by_reference on public.payments",
    "drop index public.payments_attempt_idx",
    "alter table public.payments drop column attempt_id",
    "drop policy renditions_app_ready on public.media_renditions",
    f"revoke select on table public.media_renditions from {APP_ROLE}",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
