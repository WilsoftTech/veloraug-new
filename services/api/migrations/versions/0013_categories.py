"""Categories: VeloraUG's own labels for titles, such as Indian or Kids.

Revision ID: 0013
Revises: 0012
Create Date: 2026-11-25

Genres come from TMDB and belong to the source film. Categories are typed by
admins and belong to each VJ's edition, so they are never cleared with the
TMDB copy.

A lookup table rather than a text array on editions, because:
- a category can exist before any title has it, so the seeds below and
  autocomplete can offer it;
- each category has one spelling: "indian" or "INDIAN" reuses "Indian";
- filtering and Home's rows look categories up by their link rows, which a
  plain b-tree index serves, and renaming later is one row.

A title has at most 10 categories, checked by the API and by a trigger.
The API's role sees only categories, and links, of published editions.
"""

from alembic import op

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"
EDITOR_ROLE = "veloraug_editor"

MAX_PER_EDITION = 10

SEEDS = (
    ("Indian", "indian"),
    ("Nollywood", "nollywood"),
    ("Korean", "korean"),
    ("Chinese", "chinese"),
    ("Action Classics", "action-classics"),
    ("Kids", "kids"),
)

UPGRADE = [
    # A name is trimmed, with single spaces, 1 to 40 characters.
    """
    create table public.categories (
      id uuid primary key default gen_random_uuid(),
      name text not null
        check (char_length(name) between 1 and 40
               and name = btrim(regexp_replace(name, '\\s+', ' ', 'g'))),
      slug text not null unique
        check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 60),
      created_at timestamptz not null default now()
    )
    """,
    "create unique index categories_name_idx on public.categories (lower(name))",
    """
    create table public.edition_categories (
      edition_id uuid not null references public.editions (id) on delete cascade,
      category_id uuid not null references public.categories (id) on delete cascade,
      added_at timestamptz not null default now(),
      primary key (edition_id, category_id)
    )
    """,
    # A category's titles, for filtering and Home's rows.
    """
    create index edition_categories_category_idx
      on public.edition_categories (category_id, edition_id)
    """,
    f"""
    create function public.limit_edition_categories()
    returns trigger language plpgsql set search_path = '' as $$
    begin
      if (select count(*) from public.edition_categories
          where edition_id = new.edition_id) > {MAX_PER_EDITION} then
        raise exception 'A title has at most {MAX_PER_EDITION} categories'
          using errcode = 'check_violation';
      end if;
      return null;
    end;
    $$
    """,
    "revoke all on function public.limit_edition_categories() from public",
    """
    create trigger edition_categories_limit
      after insert or update on public.edition_categories
      for each row execute function public.limit_edition_categories()
    """,
    "insert into public.categories (name, slug) values "
    + ", ".join(f"('{name}', '{slug}')" for name, slug in SEEDS),
    "alter table public.categories enable row level security",
    "alter table public.categories force row level security",
    "alter table public.edition_categories enable row level security",
    "alter table public.edition_categories force row level security",
    # The API reads categories and links of published editions only.
    f"grant select on table public.categories to {APP_ROLE}",
    f"""
    create policy categories_app_published on public.categories
      for select to {APP_ROLE} using (exists (
        select from public.edition_categories ec
        join public.editions e on e.id = ec.edition_id
        where ec.category_id = categories.id
      ))
    """,
    f"grant select on table public.edition_categories to {APP_ROLE}",
    # editions' own rule already shows the API published editions only.
    f"""
    create policy edition_categories_app_published on public.edition_categories
      for select to {APP_ROLE} using (exists (
        select from public.editions e where e.id = edition_categories.edition_id
      ))
    """,
    f"grant select, insert, update on table public.categories to {EDITOR_ROLE}",
    f"create policy categories_editor on public.categories for all "
    f"to {EDITOR_ROLE} using (true) with check (true)",
    f"""
    grant select, insert, delete on table public.edition_categories
      to {EDITOR_ROLE}
    """,
    f"create policy edition_categories_editor on public.edition_categories "
    f"for all to {EDITOR_ROLE} using (true) with check (true)",
]

# For local test databases only. Never downgrade a hosted branch.
DOWNGRADE = [
    "drop policy categories_app_published on public.categories",
    "drop table public.edition_categories",
    "drop function public.limit_edition_categories()",
    "drop table public.categories",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
