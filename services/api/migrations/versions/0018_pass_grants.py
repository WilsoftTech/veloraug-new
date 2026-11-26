"""Free days: an admin gives an account days on a plan, with a reason.

Revision ID: 0018
Revises: 0017
Create Date: 2026-11-26

A pass came only from a completed payment. Now it can come from a grant
instead: a row saying who gave how many days of which plan to whom, and
why. Grants are never payments, so revenue, success rates and refunds are
untouched by them. Each grant's pass starts when the account's passes end,
or now: so a grant to someone with a pass extends it, and to someone
without one starts one.

Admins grant through public.grant_pass, which checks the plan, the days and
the reason, takes the same lock as a payment's pass, and writes both rows.
The editor role can read grants but not write them any other way.
"""

from alembic import op

revision = "0018"
down_revision = "0017"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"
EDITOR_ROLE = "veloraug_editor"
# The lock that serializes one viewer's passes, as app/passes.py takes it.
PASS_LOCK = 6
MAX_DAYS = 90

UPGRADE = [
    f"""
    create table public.pass_grants (
      id uuid primary key default gen_random_uuid(),
      user_id uuid not null,
      plan_id text not null references public.pass_plans (id),
      days integer not null check (days between 1 and {MAX_DAYS}),
      reason text not null check (char_length(reason) between 3 and 300),
      granted_by uuid not null,
      created_at timestamptz not null default now()
    )
    """,
    "create index pass_grants_user_idx "
    "on public.pass_grants (user_id, created_at desc)",
    "alter table public.pass_grants enable row level security",
    "alter table public.pass_grants force row level security",
    "revoke all on table public.pass_grants from public",
    f"grant select on table public.pass_grants to {EDITOR_ROLE}",
    f"create policy pass_grants_editor on public.pass_grants for select "
    f"to {EDITOR_ROLE} using (true)",
    # A pass is a payment's or a grant's, never both.
    "alter table public.passes alter column payment_id drop not null",
    """
    alter table public.passes
      add column grant_id uuid unique references public.pass_grants (id),
      add constraint passes_paid_or_granted
        check ((payment_id is null) <> (grant_id is null))
    """,
    # As 0007's, and a granted pass matches its grant.
    """
    create or replace function public.check_pass_payment()
    returns trigger
    language plpgsql
    set search_path = ''
    as $$
    declare
      paid record;
      given record;
      plan record;
    begin
      if new.grant_id is not null then
        select g.user_id, g.plan_id, g.days into given
          from public.pass_grants g where g.id = new.grant_id;
        select pp.max_devices, pp.max_streams into plan
          from public.pass_plans pp where pp.id = new.plan_id;
        if given is null
           or given.user_id <> new.user_id
           or given.plan_id <> new.plan_id
           or plan.max_devices <> new.max_devices
           or plan.max_streams <> new.max_streams
           or new.ends_at <> new.starts_at + make_interval(days => given.days) then
          raise exception 'a granted pass matches its grant'
            using errcode = 'check_violation';
        end if;
        return new;
      end if;
      select p.user_id, p.state, p.days, p.plan_id, p.max_devices,
             p.max_streams
        into paid
        from public.payments p where p.id = new.payment_id;
      if paid is null
         or paid.state <> 'completed'
         or paid.user_id <> new.user_id
         or paid.plan_id <> new.plan_id
         or paid.max_devices <> new.max_devices
         or paid.max_streams <> new.max_streams
         or new.ends_at <> new.starts_at + make_interval(days => paid.days) then
        raise exception 'a pass needs a completed payment of the same plan and length'
          using errcode = 'check_violation';
      end if;
      return new;
    end
    $$
    """,
    f"""
    create function public.grant_pass(
      target uuid, plan text, days integer, why text, admin uuid
    )
    returns uuid language plpgsql volatile security definer
    set search_path = '' as $$
    declare
      chosen record;
      last_end timestamptz;
      starts timestamptz;
      grant_id uuid;
      pass_id uuid;
    begin
      select pp.id, pp.max_devices, pp.max_streams into chosen
        from public.pass_plans pp where pp.id = plan;
      if chosen is null then
        raise exception 'no plan %', plan using errcode = 'no_data_found';
      end if;
      perform pg_advisory_xact_lock(hashtextextended(target::text, {PASS_LOCK}));
      select max(s.ends_at) into last_end from public.passes s
        where s.user_id = target and s.revoked_at is null and s.ends_at > now();
      starts := greatest(now(), coalesce(last_end, now()));
      insert into public.pass_grants (user_id, plan_id, days, reason, granted_by)
        values (target, plan, days, btrim(why), admin)
        returning id into grant_id;
      insert into public.passes (user_id, grant_id, starts_at, ends_at, plan_id,
          max_devices, max_streams)
        values (target, grant_id, starts, starts + make_interval(days => days),
          plan, chosen.max_devices, chosen.max_streams)
        returning id into pass_id;
      return pass_id;
    end;
    $$
    """,
    "revoke all on function public.grant_pass(uuid, text, integer, text, uuid) "
    "from public",
    f"grant execute on function public.grant_pass(uuid, text, integer, text, uuid) "
    f"to {EDITOR_ROLE}",
]

# For local test databases only. Never downgrade a hosted branch.
DOWNGRADE = [
    "drop function public.grant_pass(uuid, text, integer, text, uuid)",
    "delete from public.passes where grant_id is not null",
    """
    create or replace function public.check_pass_payment()
    returns trigger
    language plpgsql
    set search_path = ''
    as $$
    declare
      paid record;
    begin
      select p.user_id, p.state, p.days, p.plan_id, p.max_devices,
             p.max_streams
        into paid
        from public.payments p where p.id = new.payment_id;
      if paid is null
         or paid.state <> 'completed'
         or paid.user_id <> new.user_id
         or paid.plan_id <> new.plan_id
         or paid.max_devices <> new.max_devices
         or paid.max_streams <> new.max_streams
         or new.ends_at <> new.starts_at + make_interval(days => paid.days) then
        raise exception 'a pass needs a completed payment of the same plan and length'
          using errcode = 'check_violation';
      end if;
      return new;
    end
    $$
    """,
    "alter table public.passes drop constraint passes_paid_or_granted",
    "alter table public.passes drop column grant_id",
    "alter table public.passes alter column payment_id set not null",
    "drop table public.pass_grants",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
