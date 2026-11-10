"""The catalogue: VeloraUG's movies, and a copy of their TMDB details.

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-10

Hand-written SQL, from docs/step-06a-catalogue-plan.md, "Database". The
owner's catalogue script adds, publishes and removes movies. The API's role
reads published movies only, and can refresh their TMDB copies but not delete
them.
"""

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None

UPGRADE = [
    """
    create table public.movies (
      id uuid primary key default gen_random_uuid(),
      tmdb_id integer not null unique check (tmdb_id > 0),
      published boolean not null default false,
      added_at timestamptz not null default now(),
      published_at timestamptz,
      check (published = (published_at is not null))
    )
    """,
    # Only the fields the app shows. TMDB's terms forbid keeping any of it
    # for more than 6 months: the API stops serving a copy at 150 days, and
    # the owner's refresh deletes one at 180.
    """
    create table public.tmdb_movie_details (
      tmdb_id integer primary key
        references public.movies (tmdb_id) on delete cascade,
      title text not null check (char_length(title) between 1 and 500),
      original_title text,
      overview text,
      release_date date,
      runtime_minutes integer check (runtime_minutes is null or runtime_minutes > 0),
      genres text[] not null default '{}',
      poster_path text,
      backdrop_path text,
      fetched_at timestamptz not null default now()
    )
    """,
    """
    create index tmdb_movie_details_title_idx
      on public.tmdb_movie_details (lower(title) text_pattern_ops)
    """,
    "alter table public.movies enable row level security",
    "alter table public.movies force row level security",
    "alter table public.tmdb_movie_details enable row level security",
    "alter table public.tmdb_movie_details force row level security",
    "revoke all on table public.movies, public.tmdb_movie_details from public",
    # The API sees published movies only, signed in or not.
    "grant select on table public.movies to veloraug_app",
    """
    create policy movies_select_published on public.movies
      for select to veloraug_app
      using (published)
    """,
    # The API reads and refreshes copies of published movies. It can't
    # delete them.
    """
    grant select, insert, update on table public.tmdb_movie_details
      to veloraug_app
    """,
    """
    create policy details_of_published on public.tmdb_movie_details
      for all to veloraug_app
      using (exists (
        select from public.movies m
        where m.tmdb_id = tmdb_movie_details.tmdb_id and m.published
      ))
      with check (exists (
        select from public.movies m
        where m.tmdb_id = tmdb_movie_details.tmdb_id and m.published
      ))
    """,
]

# For local test databases only. Never downgrade a hosted branch: fix
# mistakes with a new migration.
DOWNGRADE = [
    "drop table public.tmdb_movie_details",
    "drop table public.movies",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
