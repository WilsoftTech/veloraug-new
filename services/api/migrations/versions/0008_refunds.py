"""Refunds: an admin marks a completed payment refunded, which ends its pass.

Revision ID: 0008
Revises: 0007
Create Date: 2026-11-23

Hand-written SQL. Forward only on hosted branches: 0007 is never rewritten.

Pesapal reports a payment refunded from its dashboard as still completed,
and sends no notification, so VeloraUG can't learn of a refund by itself.
An admin, having refunded the payment in full on Pesapal, marks it refunded
here, and its pass ends.

- `payments` gains the state `refunded`, with when and by which admin. A
  refunded payment keeps its `completed_at`: it was paid before it was
  refunded.
- The admin routes' role may change a payment only from completed to
  refunded, and only those columns. It may end a pass and move the passes
  queued behind it up, which `check_pass_move` from 0007 keeps whole.
- Through the API's roles, a refunded payment stays refunded: a later
  notification from Pesapal can't make it completed or reversed again.
"""

from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None

EDITOR_ROLE = "veloraug_editor"

UPGRADE = [
    "alter table public.payments add column refunded_at timestamptz",
    "alter table public.payments add column refunded_by uuid",
    "alter table public.payments drop constraint payments_state_check",
    """
    alter table public.payments add constraint payments_state_check check (state in
      ('started', 'pending', 'completed', 'failed', 'reversed', 'abandoned',
       'refunded'))
    """,
    "alter table public.payments drop constraint payments_check1",
    """
    alter table public.payments add constraint payments_completed_check
      check ((state = 'completed') = (completed_at is not null)
             or state in ('reversed', 'refunded'))
    """,
    """
    alter table public.payments add constraint payments_refunded_check
      check ((state = 'refunded')
               = (refunded_at is not null and refunded_by is not null)
             and (state <> 'refunded' or completed_at is not null))
    """,
    """
    create function public.keep_refund()
    returns trigger language plpgsql set search_path = '' as $$
    begin
      if current_user not in ('veloraug_app', 'veloraug_editor') then
        return new;
      end if;
      if old.state = 'refunded' and new.state <> 'refunded' then
        raise exception 'a refunded payment stays refunded'
          using errcode = 'check_violation';
      end if;
      return new;
    end
    $$
    """,
    """
    create trigger payments_keep_refund before update on public.payments
      for each row execute function public.keep_refund()
    """,
    f"grant update (state, reason, updated_at, refunded_at, refunded_by) "
    f"on table public.payments to {EDITOR_ROLE}",
    f"""
    create policy payments_editor_refund on public.payments for update
      to {EDITOR_ROLE}
      using (state = 'completed')
      with check (state = 'refunded')
    """,
    f"grant update (revoked_at, starts_at, ends_at) on table public.passes "
    f"to {EDITOR_ROLE}",
    f"create policy passes_editor_update on public.passes for update "
    f"to {EDITOR_ROLE} using (true) with check (true)",
]

# For local test databases only. Never downgrade a hosted branch: fix
# mistakes with a new migration. Refunded payments become reversed, which
# 0007 allows without a completed_at check and which also has no pass.
DOWNGRADE = [
    "drop policy passes_editor_update on public.passes",
    f"revoke update (revoked_at, starts_at, ends_at) on table public.passes "
    f"from {EDITOR_ROLE}",
    "drop policy payments_editor_refund on public.payments",
    f"revoke update (state, reason, updated_at, refunded_at, refunded_by) "
    f"on table public.payments from {EDITOR_ROLE}",
    "drop trigger payments_keep_refund on public.payments",
    "drop function public.keep_refund()",
    "alter table public.payments drop constraint payments_refunded_check",
    "update public.payments set state = 'reversed' where state = 'refunded'",
    "alter table public.payments drop constraint payments_completed_check",
    """
    alter table public.payments add constraint payments_check1
      check ((state = 'completed') = (completed_at is not null)
             or state = 'reversed')
    """,
    "alter table public.payments drop constraint payments_state_check",
    """
    alter table public.payments add constraint payments_state_check check (state in
      ('started', 'pending', 'completed', 'failed', 'reversed', 'abandoned'))
    """,
    "alter table public.payments drop column refunded_by",
    "alter table public.payments drop column refunded_at",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
