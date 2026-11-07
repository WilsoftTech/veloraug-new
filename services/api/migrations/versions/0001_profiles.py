"""Profiles, with row-level security for the API's role.

Revision ID: 0001
Revises:
Create Date: 2026-11-07

Hand-written SQL, from docs/step-05a-neon-plan.md, "First migration". The
veloraug_app role must exist first: see services/api/README.md, Database.
"""

from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

UPGRADE = [
    # Stop with a clear message rather than a failed grant.
    """
    do $$
    begin
      if not exists (select from pg_roles where rolname = 'veloraug_app') then
        raise exception 'Create the veloraug_app role first. See '
          'services/api/README.md, Database';
      end if;
    end
    $$
    """,
    # The user the API is acting for, set per transaction. Null when unset,
    # so nothing matches and no row is visible.
    """
    create function public.current_app_user_id()
    returns uuid language sql stable set search_path = '' as $$
      select nullif(current_setting('app.user_id', true), '')::uuid
    $$
    """,
    # No foreign key into neon_auth: that schema is Neon's.
    """
    create table public.profiles (
      user_id uuid primary key,
      display_name text check (
        display_name is null or char_length(display_name) between 1 and 80
      ),
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
    """,
    "alter table public.profiles enable row level security",
    "alter table public.profiles force row level security",
    "revoke all on table public.profiles from public",
    "grant select on table public.profiles to veloraug_app",
    "grant insert (user_id) on table public.profiles to veloraug_app",
    "grant update (display_name) on table public.profiles to veloraug_app",
    """
    create policy profiles_select_own on public.profiles
      for select to veloraug_app
      using (user_id = public.current_app_user_id())
    """,
    """
    create policy profiles_insert_own on public.profiles
      for insert to veloraug_app
      with check (user_id = public.current_app_user_id())
    """,
    """
    create policy profiles_update_own on public.profiles
      for update to veloraug_app
      using (user_id = public.current_app_user_id())
      with check (user_id = public.current_app_user_id())
    """,
    """
    create function public.set_profile_updated_at()
    returns trigger language plpgsql set search_path = '' as $$
    begin
      new.updated_at := now();
      return new;
    end;
    $$
    """,
    """
    create trigger profiles_set_updated_at
      before update on public.profiles
      for each row execute function public.set_profile_updated_at()
    """,
    "revoke all on function public.set_profile_updated_at() from public",
]

# For local test databases only. Never downgrade a hosted branch: fix
# mistakes with a new migration.
DOWNGRADE = [
    "drop table public.profiles",
    "drop function public.set_profile_updated_at()",
    "drop function public.current_app_user_id()",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
