"""Passes: pass prices, payments through Pesapal, and the passes they buy.

Revision ID: 0006
Revises: 0005
Create Date: 2026-11-19

Hand-written SQL, from docs/step-10a-payments-plan.md, "Database".

The API's role adds and changes only the signed-in viewer's own payments,
and adds only their passes, under row-level security as for profiles.
Pesapal's notifications have no viewer: the API finds a payment's owner by
its tracking ID, which it sets as app.tracking_id for that one transaction.
A trigger refuses any pass that doesn't match a completed payment of the
same viewer, of the right length, so a bug in the API can't give passes
away. The editor role changes prices only.
"""

from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"
EDITOR_ROLE = "veloraug_editor"

UPGRADE = [
    # --- Tables -------------------------------------------------------------
    """
    create table public.pass_plans (
      id text primary key check (id in ('day', 'week', 'month')),
      days integer not null check (days between 1 and 366),
      -- Whole Uganda shillings. Null: not for sale.
      price_ugx integer check (price_ugx between 500 and 10000000),
      updated_at timestamptz not null default now()
    )
    """,
    "insert into public.pass_plans (id, days) values "
    "('day', 1), ('week', 7), ('month', 30)",
    """
    create table public.payments (
      -- Sent to Pesapal as the merchant reference.
      id uuid primary key default gen_random_uuid(),
      user_id uuid not null,
      plan_id text not null references public.pass_plans (id),
      -- The pass's length and price when it was bought.
      days integer not null check (days between 1 and 366),
      amount_ugx integer not null check (amount_ugx between 500 and 10000000),
      state text not null default 'started' check (state in
        ('started', 'pending', 'completed', 'failed', 'reversed', 'abandoned')),
      tracking_id text unique
        check (tracking_id ~ '^[0-9A-Za-z-]{8,64}$'),
      email text check (char_length(email) <= 320),
      phone text check (phone ~ '^\\+?[0-9]{9,15}$'),
      payment_method text check (char_length(payment_method) <= 50),
      confirmation_code text check (char_length(confirmation_code) <= 100),
      reason text check (char_length(reason) <= 300),
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      completed_at timestamptz,
      check (email is not null or phone is not null),
      check ((state = 'completed') = (completed_at is not null)
             or state = 'reversed')
    )
    """,
    "create index payments_user_idx on public.payments (user_id, created_at desc)",
    """
    create table public.passes (
      id uuid primary key default gen_random_uuid(),
      user_id uuid not null,
      payment_id uuid not null unique references public.payments (id),
      starts_at timestamptz not null,
      ends_at timestamptz not null check (ends_at > starts_at),
      revoked_at timestamptz,
      created_at timestamptz not null default now()
    )
    """,
    "create index passes_user_idx on public.passes (user_id, ends_at desc)",
    # A pass only for a completed payment of the same viewer, exactly as
    # long as the payment's days.
    """
    create function public.check_pass_payment()
    returns trigger
    language plpgsql
    set search_path = ''
    as $$
    declare
      paid record;
    begin
      select p.user_id, p.state, p.days into paid
        from public.payments p where p.id = new.payment_id;
      if paid is null
         or paid.state <> 'completed'
         or paid.user_id <> new.user_id
         or new.ends_at <> new.starts_at + make_interval(days => paid.days) then
        raise exception 'a pass needs a completed payment of the same length'
          using errcode = 'check_violation';
      end if;
      return new;
    end
    $$
    """,
    """
    create trigger passes_match_payment before insert on public.passes
      for each row execute function public.check_pass_payment()
    """,
    # --- Row-level security -------------------------------------------------
    *(
        statement
        for table in ("pass_plans", "payments", "passes")
        for statement in (
            f"alter table public.{table} enable row level security",
            f"alter table public.{table} force row level security",
        )
    ),
    # The API's role.
    f"grant select on table public.pass_plans to {APP_ROLE}",
    f"create policy pass_plans_app on public.pass_plans for select to {APP_ROLE} "
    "using (true)",
    f"grant select, insert on table public.payments to {APP_ROLE}",
    f"""
    grant update (state, tracking_id, payment_method, confirmation_code, reason,
                  updated_at, completed_at)
      on table public.payments to {APP_ROLE}
    """,
    f"""
    create policy payments_app_own on public.payments for all to {APP_ROLE}
      using (user_id = public.current_app_user_id())
      with check (user_id = public.current_app_user_id())
    """,
    # Pesapal's notifications: one payment, by the tracking ID set for the
    # transaction. Reading only, and Pesapal's IDs aren't guessable.
    f"""
    create policy payments_app_by_tracking on public.payments for select
      to {APP_ROLE}
      using (tracking_id = nullif(current_setting('app.tracking_id', true), ''))
    """,
    f"grant select, insert on table public.passes to {APP_ROLE}",
    f"grant update (revoked_at) on table public.passes to {APP_ROLE}",
    f"""
    create policy passes_app_own on public.passes for all to {APP_ROLE}
      using (user_id = public.current_app_user_id())
      with check (user_id = public.current_app_user_id())
    """,
    # Whether the signed-in viewer is an admin, and nothing else.
    f"grant select (user_id) on table public.admins to {APP_ROLE}",
    f"""
    create policy admins_app_self on public.admins for select to {APP_ROLE}
      using (user_id = public.current_app_user_id())
    """,
    # The admin routes' role: prices only.
    f"grant select on table public.pass_plans to {EDITOR_ROLE}",
    f"grant update (price_ugx, updated_at) on table public.pass_plans to {EDITOR_ROLE}",
    f"create policy pass_plans_editor on public.pass_plans for all "
    f"to {EDITOR_ROLE} using (true) with check (true)",
]

# For local test databases only. Never downgrade a hosted branch: fix
# mistakes with a new migration. Payments and passes are lost.
DOWNGRADE = [
    "drop policy admins_app_self on public.admins",
    f"revoke select (user_id) on table public.admins from {APP_ROLE}",
    "drop table public.passes",
    "drop function public.check_pass_payment()",
    "drop table public.payments",
    "drop table public.pass_plans",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
