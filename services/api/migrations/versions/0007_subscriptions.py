"""Subscriptions: six tiers, device registration and playback sessions.

Revision ID: 0007
Revises: 0006
Create Date: 2026-11-21

Hand-written SQL, from docs/step-10a-payments-plan.md, "Milestone 10
subscriptions". Forward only on hosted branches: 0006 is never rewritten.

- `pass_plans` gains a name, a description, device and stream allowances,
  an order, a featured flag and an on-sale flag. The six approved tiers are
  seeded idempotently. `day`, `week` and `month` stay, marked legacy and off
  sale, so earlier payments and passes keep their plan.
- Every payment and pass keeps a snapshot of what was bought: days, price,
  devices and streams. Existing rows get one device and one stream, which
  is what a legacy pass allowed in practice.
- The database refuses a payment that doesn't match its plan as it is on
  sale now, and a pass that doesn't match its completed payment.
- `devices`: one row per installation, identified by a server-made secret
  kept only as a SHA-256 hash. At most three active per account, enforced
  here as well as in the API, under a per-account lock.
- `playback_sessions`: one live session per device, at most three per
  account. The media gateway asks `playback_session_status`, which answers a
  yes or no and nothing else.
- `plan_changes`: every change to a plan's price or sale flags, kept by a
  trigger. Admins can read it, never change it.
"""

from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"
EDITOR_ROLE = "veloraug_editor"

LEGACY = ("day", "week", "month")
# id, name, price, days, devices, streams, order, featured, description
TIERS = (
    (
        "velora_start",
        "Velora Start",
        6000,
        7,
        1,
        1,
        10,
        False,
        "A week of everything, on one device.",
    ),
    (
        "velora_flex",
        "Velora Flex",
        10000,
        14,
        1,
        1,
        20,
        False,
        "Two weeks of everything, on one device.",
    ),
    (
        "velora_prime",
        "Velora Prime",
        18000,
        30,
        1,
        1,
        30,
        True,
        "A full month of everything, on one device.",
    ),
    (
        "velora_duo",
        "Velora Duo",
        50000,
        90,
        2,
        2,
        40,
        False,
        "Three months, on two devices at once.",
    ),
    (
        "velora_pro",
        "Velora Pro",
        90000,
        180,
        2,
        2,
        50,
        False,
        "Six months, on two devices at once.",
    ),
    (
        "velora_max",
        "Velora Max",
        150000,
        365,
        3,
        3,
        60,
        False,
        "A whole year, on three devices at once.",
    ),
)
ALL_IDS = ", ".join(f"'{i}'" for i in (*LEGACY, *(t[0] for t in TIERS)))


def _seed() -> str:
    rows = ",\n      ".join(
        f"('{i}', '{name}', '{text}', {price}, {days}, {devices}, {streams}, "
        f"{order}, {'true' if featured else 'false'}, true, false)"
        for i, name, price, days, devices, streams, order, featured, text in TIERS
    )
    # Idempotent: a plan already there keeps what an admin set.
    return f"""
    insert into public.pass_plans (id, display_name, description, price_ugx,
      days, max_devices, max_streams, display_order, featured, for_sale, legacy)
    values
      {rows}
    on conflict (id) do nothing
    """


UPGRADE = [
    # --- Plans --------------------------------------------------------------
    "alter table public.pass_plans drop constraint pass_plans_id_check",
    f"alter table public.pass_plans add constraint pass_plans_id_check "
    f"check (id in ({ALL_IDS}))",
    """
    alter table public.pass_plans
      add column display_name text check (char_length(display_name) between 1 and 60),
      add column description text check (char_length(description) <= 300),
      add column max_devices smallint not null default 1
        check (max_devices between 1 and 3),
      add column max_streams smallint not null default 1
        check (max_streams between 1 and 3),
      add column display_order smallint not null default 100
        check (display_order between 0 and 1000),
      add column featured boolean not null default false,
      add column for_sale boolean not null default false,
      add column legacy boolean not null default false
    """,
    "alter table public.pass_plans add constraint pass_plans_streams_check "
    "check (max_streams <= max_devices)",
    # The legacy passes leave the catalogue. Their prices stay, for history.
    """
    update public.pass_plans set legacy = true, for_sale = false,
      display_name = case id when 'day' then '1 day' when 'week' then '1 week'
                             else '1 month' end,
      display_order = case id when 'day' then 900 when 'week' then 901
                              else 902 end
    where id in ('day', 'week', 'month')
    """,
    "alter table public.pass_plans alter column display_name set not null",
    # On sale needs a price and a current plan. Featured needs on sale.
    """
    alter table public.pass_plans add constraint pass_plans_sale_check
      check (not for_sale or (price_ugx is not null and not legacy))
    """,
    "alter table public.pass_plans add constraint pass_plans_featured_check "
    "check (not featured or for_sale)",
    "create unique index pass_plans_one_featured on public.pass_plans (featured) "
    "where featured",
    _seed(),
    # --- What each payment and pass bought ---------------------------------
    """
    alter table public.payments
      add column plan_name text check (char_length(plan_name) between 1 and 60),
      add column max_devices smallint not null default 1
        check (max_devices between 1 and 3),
      add column max_streams smallint not null default 1
        check (max_streams between 1 and 3),
      add column redirect_url text check (char_length(redirect_url) <= 2000)
    """,
    """
    update public.payments p set plan_name = pp.display_name
    from public.pass_plans pp where pp.id = p.plan_id
    """,
    "alter table public.payments alter column plan_name set not null",
    # New payments must say what they bought: no defaults.
    "alter table public.payments alter column max_devices drop default",
    "alter table public.payments alter column max_streams drop default",
    "create index payments_state_idx on public.payments (state, created_at desc)",
    """
    alter table public.passes
      add column plan_id text references public.pass_plans (id),
      add column max_devices smallint check (max_devices between 1 and 3),
      add column max_streams smallint check (max_streams between 1 and 3)
    """,
    """
    update public.passes s set plan_id = p.plan_id, max_devices = p.max_devices,
      max_streams = p.max_streams
    from public.payments p where p.id = s.payment_id
    """,
    "alter table public.passes alter column plan_id set not null",
    "alter table public.passes alter column max_devices set not null",
    "alter table public.passes alter column max_streams set not null",
    "create index passes_live_idx on public.passes (user_id, starts_at) "
    "where revoked_at is null",
    # A new payment matches its plan as it's on sale now: the API can't
    # charge a made-up price or hand out more devices than were paid for.
    """
    create function public.check_payment_plan()
    returns trigger language plpgsql set search_path = '' as $$
    declare
      plan record;
    begin
      select pp.* into plan from public.pass_plans pp where pp.id = new.plan_id;
      if plan is null or not plan.for_sale
         or new.amount_ugx <> plan.price_ugx or new.days <> plan.days
         or new.max_devices <> plan.max_devices
         or new.max_streams <> plan.max_streams
         or new.plan_name <> plan.display_name then
        raise exception 'a payment must match its plan as it is on sale'
          using errcode = 'check_violation';
      end if;
      return new;
    end
    $$
    """,
    """
    create trigger payments_match_plan before insert on public.payments
      for each row execute function public.check_payment_plan()
    """,
    # What a payment bought never changes afterwards, through the API's
    # roles. The database's owner, by hand, is trusted, as for any table.
    """
    create function public.keep_payment_snapshot()
    returns trigger language plpgsql set search_path = '' as $$
    begin
      if current_user not in ('veloraug_app', 'veloraug_editor') then
        return new;
      end if;
      if new.user_id <> old.user_id or new.plan_id <> old.plan_id
         or new.days <> old.days or new.amount_ugx <> old.amount_ugx
         or new.plan_name <> old.plan_name
         or new.max_devices <> old.max_devices
         or new.max_streams <> old.max_streams
         or new.created_at <> old.created_at then
        raise exception 'what a payment bought can''t change'
          using errcode = 'check_violation';
      end if;
      return new;
    end
    $$
    """,
    """
    create trigger payments_keep_snapshot before update on public.payments
      for each row execute function public.keep_payment_snapshot()
    """,
    # A pass matches its completed payment, tier and all. Replaces 0006's.
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
    # Through the API's roles, a pass can be moved only before it starts,
    # only to now or later, and only as a whole: after a reversal, the passes
    # queued behind it move up. The owner, by hand, is trusted, so a run
    # sheet can end a test viewer's pass.
    """
    create function public.check_pass_move()
    returns trigger language plpgsql set search_path = '' as $$
    begin
      if current_user not in ('veloraug_app', 'veloraug_editor') then
        return new;
      end if;
      if new.user_id <> old.user_id or new.payment_id <> old.payment_id
         or new.plan_id <> old.plan_id or new.max_devices <> old.max_devices
         or new.max_streams <> old.max_streams then
        raise exception 'a pass''s owner and plan can''t change'
          using errcode = 'check_violation';
      end if;
      if old.revoked_at is not null and new.revoked_at is null then
        raise exception 'a revoked pass stays revoked'
          using errcode = 'check_violation';
      end if;
      if new.starts_at <> old.starts_at or new.ends_at <> old.ends_at then
        if old.starts_at <= now() or new.starts_at < now() - interval '1 minute'
           or new.ends_at - new.starts_at <> old.ends_at - old.starts_at then
          raise exception 'only a pass still to come can move, kept whole'
            using errcode = 'check_violation';
        end if;
      end if;
      return new;
    end
    $$
    """,
    """
    create trigger passes_move_whole before update on public.passes
      for each row execute function public.check_pass_move()
    """,
    # --- Devices ------------------------------------------------------------
    """
    create table public.devices (
      id uuid primary key default gen_random_uuid(),
      user_id uuid not null,
      -- SHA-256 of the secret the device holds. The secret itself is never
      -- stored: it is shown to the device once, when it registers.
      secret_hash bytea not null unique check (octet_length(secret_hash) = 32),
      label text not null check (char_length(label) between 1 and 60),
      platform text not null check (platform in ('web', 'android', 'ios', 'other')),
      registered_at timestamptz not null default now(),
      last_active_at timestamptz not null default now(),
      revoked_at timestamptz,
      revoked_by text check (revoked_by in ('owner', 'admin')),
      check ((revoked_at is null) = (revoked_by is null))
    )
    """,
    "create index devices_user_idx on public.devices (user_id, registered_at desc)",
    "create index devices_active_idx on public.devices (user_id) "
    "where revoked_at is null",
    # Three active devices at most, whatever the plan, one account at a time.
    """
    create function public.check_device_cap()
    returns trigger language plpgsql set search_path = '' as $$
    begin
      perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 7));
      if (tg_op = 'UPDATE' and old.revoked_at is not null
          and new.revoked_at is null) then
        raise exception 'a removed device stays removed'
          using errcode = 'check_violation';
      end if;
      if tg_op = 'INSERT' and (
        select count(*) from public.devices d
        where d.user_id = new.user_id and d.revoked_at is null
      ) >= 3 then
        raise exception 'an account has at most three devices'
          using errcode = 'check_violation';
      end if;
      return new;
    end
    $$
    """,
    """
    create trigger devices_cap before insert or update on public.devices
      for each row execute function public.check_device_cap()
    """,
    # --- Playback sessions --------------------------------------------------
    """
    create table public.playback_sessions (
      id uuid primary key default gen_random_uuid(),
      user_id uuid not null,
      device_id uuid not null references public.devices (id),
      pass_id uuid not null references public.passes (id),
      item_id uuid not null,
      started_at timestamptz not null default now(),
      last_seen_at timestamptz not null default now(),
      ended_at timestamptz,
      end_reason text check (end_reason in
        ('replaced', 'idle', 'owner', 'admin', 'device_removed', 'pass_ended')),
      check ((ended_at is null) = (end_reason is null))
    )
    """,
    # One stream per device.
    "create unique index playback_sessions_one_per_device "
    "on public.playback_sessions (device_id) where ended_at is null",
    "create index playback_sessions_live_idx on public.playback_sessions "
    "(user_id) where ended_at is null",
    "create index playback_sessions_user_idx on public.playback_sessions "
    "(user_id, started_at desc)",
    # Three streams at most, whatever the plan; a session matches its
    # device and pass.
    """
    create function public.check_session()
    returns trigger language plpgsql set search_path = '' as $$
    begin
      perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 7));
      if not exists (
        select from public.devices d where d.id = new.device_id
          and d.user_id = new.user_id and d.revoked_at is null
      ) or not exists (
        select from public.passes p where p.id = new.pass_id
          and p.user_id = new.user_id and p.revoked_at is null
      ) then
        raise exception 'a session needs the account''s own device and pass'
          using errcode = 'check_violation';
      end if;
      if (
        select count(*) from public.playback_sessions s
        where s.user_id = new.user_id and s.ended_at is null
      ) >= 3 then
        raise exception 'an account has at most three streams'
          using errcode = 'check_violation';
      end if;
      return new;
    end
    $$
    """,
    """
    create trigger playback_sessions_cap before insert on public.playback_sessions
      for each row execute function public.check_session()
    """,
    # For the media gateway, through the API: is this session still allowed
    # to fetch video, and until when. Nothing else about it. Runs as the
    # migration's owner, so the API's role needs no rights over sessions it
    # isn't acting for.
    """
    create function public.playback_session_status(
      session uuid, idle_seconds integer
    )
    returns table (live boolean, until timestamptz)
    language sql stable security definer set search_path = '' as $$
      select s.ended_at is null
             and s.last_seen_at > now() - make_interval(secs => idle_seconds)
             and d.revoked_at is null
             and p.revoked_at is null
             and p.starts_at <= now() and p.ends_at > now(),
             p.ends_at
      from public.playback_sessions s
      join public.devices d on d.id = s.device_id
      join public.passes p on p.id = s.pass_id
      where s.id = session
    $$
    """,
    "revoke all on function public.playback_session_status(uuid, integer) from public",
    f"grant execute on function public.playback_session_status(uuid, integer) "
    f"to {APP_ROLE}",
    # --- Price history ------------------------------------------------------
    """
    create table public.plan_changes (
      id bigint generated always as identity primary key,
      plan_id text not null references public.pass_plans (id),
      changed_by uuid,
      changed_at timestamptz not null default now(),
      old_price_ugx integer,
      new_price_ugx integer,
      old_for_sale boolean not null,
      new_for_sale boolean not null,
      old_featured boolean not null,
      new_featured boolean not null
    )
    """,
    """
    create function public.record_plan_change()
    returns trigger language plpgsql security definer set search_path = '' as $$
    begin
      if new.price_ugx is distinct from old.price_ugx
         or new.for_sale <> old.for_sale or new.featured <> old.featured then
        insert into public.plan_changes (plan_id, changed_by, old_price_ugx,
          new_price_ugx, old_for_sale, new_for_sale, old_featured, new_featured)
        values (new.id, public.current_app_user_id(), old.price_ugx,
          new.price_ugx, old.for_sale, new.for_sale, old.featured, new.featured);
      end if;
      return new;
    end
    $$
    """,
    "revoke all on function public.record_plan_change() from public",
    """
    create trigger pass_plans_record_change after update on public.pass_plans
      for each row execute function public.record_plan_change()
    """,
    # --- Row-level security -------------------------------------------------
    *(
        statement
        for table in ("devices", "playback_sessions", "plan_changes")
        for statement in (
            f"alter table public.{table} enable row level security",
            f"alter table public.{table} force row level security",
        )
    ),
    # The API's role: its viewer's own devices and sessions only.
    f"grant select, insert on table public.devices to {APP_ROLE}",
    f"grant update (label, last_active_at, revoked_at, revoked_by) "
    f"on table public.devices to {APP_ROLE}",
    f"""
    create policy devices_app_own on public.devices for all to {APP_ROLE}
      using (user_id = public.current_app_user_id())
      with check (user_id = public.current_app_user_id())
    """,
    f"grant select, insert on table public.playback_sessions to {APP_ROLE}",
    f"grant update (last_seen_at, ended_at, end_reason) "
    f"on table public.playback_sessions to {APP_ROLE}",
    f"""
    create policy playback_sessions_app_own on public.playback_sessions
      for all to {APP_ROLE}
      using (user_id = public.current_app_user_id())
      with check (user_id = public.current_app_user_id())
    """,
    # Moving queued passes up after a reversal, kept whole by the trigger.
    f"grant update (starts_at, ends_at) on table public.passes to {APP_ROLE}",
    f"grant update (redirect_url) on table public.payments to {APP_ROLE}",
    # The admin routes' role: reads billing, changes prices and sale flags,
    # and can remove a device. It never changes a payment or a pass.
    f"grant update (for_sale, featured) on table public.pass_plans to {EDITOR_ROLE}",
    f"grant select on table public.payments, public.passes, "
    f"public.plan_changes to {EDITOR_ROLE}",
    f"grant select on table public.devices, public.playback_sessions to {EDITOR_ROLE}",
    f"grant update (revoked_at, revoked_by) on table public.devices to {EDITOR_ROLE}",
    f"grant update (ended_at, end_reason) on table public.playback_sessions "
    f"to {EDITOR_ROLE}",
    *(
        f"create policy {table}_editor_read on public.{table} for select "
        f"to {EDITOR_ROLE} using (true)"
        for table in ("payments", "passes", "plan_changes", "playback_sessions")
    ),
    f"create policy devices_editor on public.devices for all to {EDITOR_ROLE} "
    "using (true) with check (true)",
    f"create policy playback_sessions_editor_end on public.playback_sessions "
    f"for update to {EDITOR_ROLE} using (true) with check (true)",
]

# For local test databases only. Never downgrade a hosted branch: fix
# mistakes with a new migration. Devices, sessions and every payment or pass
# of the six tiers are lost.
DOWNGRADE = [
    "drop trigger pass_plans_record_change on public.pass_plans",
    "drop table public.plan_changes",
    "drop function public.record_plan_change()",
    "drop function public.playback_session_status(uuid, integer)",
    "drop table public.playback_sessions",
    "drop function public.check_session()",
    "drop table public.devices",
    "drop function public.check_device_cap()",
    "drop trigger passes_move_whole on public.passes",
    "drop function public.check_pass_move()",
    "drop trigger payments_keep_snapshot on public.payments",
    "drop function public.keep_payment_snapshot()",
    "drop trigger payments_match_plan on public.payments",
    "drop function public.check_payment_plan()",
    *(
        f"drop policy {table}_editor_read on public.{table}"
        for table in ("payments", "passes")
    ),
    f"revoke select on table public.payments, public.passes from {EDITOR_ROLE}",
    f"revoke update (starts_at, ends_at) on table public.passes from {APP_ROLE}",
    f"revoke update (redirect_url) on table public.payments from {APP_ROLE}",
    f"revoke update (for_sale, featured) on table public.pass_plans from {EDITOR_ROLE}",
    "delete from public.passes where plan_id not in ('day', 'week', 'month')",
    "delete from public.payments where plan_id not in ('day', 'week', 'month')",
    """
    create or replace function public.check_pass_payment()
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
    "drop index public.passes_live_idx",
    "alter table public.passes drop column plan_id, drop column max_devices, "
    "drop column max_streams",
    "drop index public.payments_state_idx",
    "alter table public.payments drop column plan_name, drop column max_devices, "
    "drop column max_streams, drop column redirect_url",
    "delete from public.pass_plans where id not in ('day', 'week', 'month')",
    "drop index public.pass_plans_one_featured",
    "alter table public.pass_plans drop constraint pass_plans_featured_check",
    "alter table public.pass_plans drop constraint pass_plans_sale_check",
    "alter table public.pass_plans drop constraint pass_plans_streams_check",
    "alter table public.pass_plans drop column display_name, "
    "drop column description, drop column max_devices, drop column max_streams, "
    "drop column display_order, drop column featured, drop column for_sale, "
    "drop column legacy",
    "alter table public.pass_plans drop constraint pass_plans_id_check",
    "alter table public.pass_plans add constraint pass_plans_id_check "
    "check (id in ('day', 'week', 'month'))",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
