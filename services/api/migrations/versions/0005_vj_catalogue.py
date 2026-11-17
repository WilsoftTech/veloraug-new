"""The VJ catalogue: VJs, source titles, editions, playable items and admins.

Revision ID: 0005
Revises: 0004
Create Date: 2026-11-17

Hand-written SQL, from docs/step-09a-vj-catalogue-plan.md, "Database".

A source title (a film or series, usually from TMDB) can have several VJ
editions. A movie edition has one playable item; a series edition has one
per episode. Upload keys and originals now belong to an item, and an item
keeps the role a movie had: R2 paths stay movies/<item ID>/<original ID>/,
and a grant's "m" names the item. Today's films move across with the same
IDs, so their files, grants and unused keys keep working.

The new editor role is what the API's admin routes connect as. The API's own
role still sees only what is published.
"""

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"
MEDIA_ROLE = "veloraug_media"
EDITOR_ROLE = "veloraug_editor"

NEW_TABLES = (
    "languages",
    "vjs",
    "sources",
    "editions",
    "items",
    "tmdb_matches",
    "admins",
)

UPGRADE = [
    # Without a login until the owner runs create_app_role.py --role editor.
    # No special rights, as for the other two roles.
    f"""
    do $$ begin
      if not exists (select from pg_roles where rolname = '{EDITOR_ROLE}') then
        create role {EDITOR_ROLE} nologin nosuperuser nocreatedb nocreaterole
          noinherit noreplication nobypassrls connection limit 10;
      end if;
    end $$
    """,
    # --- Tables -------------------------------------------------------------
    """
    create table public.languages (
      code text primary key check (code ~ '^[a-z]{2,3}$'),
      name text not null unique check (char_length(name) between 1 and 50),
      added_at timestamptz not null default now()
    )
    """,
    "insert into public.languages (code, name) values ('lg', 'Luganda')",
    """
    create table public.vjs (
      id uuid primary key default gen_random_uuid(),
      name text not null check (char_length(name) between 1 and 80),
      slug text not null unique
        check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 80),
      match_names text[] not null default '{}'
        check (cardinality(match_names) <= 20),
      photo_path text check (photo_path ~ '^vjs/[A-Za-z0-9._/-]{1,200}$'),
      bio text check (char_length(bio) <= 1000),
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
    """,
    "create unique index vjs_name_idx on public.vjs (lower(name))",
    # The details of a source title, from TMDB or typed in by an admin.
    """
    create table public.sources (
      id uuid primary key default gen_random_uuid(),
      kind text not null check (kind in ('movie', 'series')),
      tmdb_id integer check (tmdb_id > 0),
      title text not null check (char_length(title) between 1 and 500),
      original_title text check (char_length(original_title) <= 500),
      overview text check (char_length(overview) <= 5000),
      release_date date,
      runtime_minutes integer check (runtime_minutes is null or runtime_minutes > 0),
      genres text[] not null default '{}',
      poster_path text check (char_length(poster_path) <= 300),
      backdrop_path text check (char_length(backdrop_path) <= 300),
      trailer_key text check (trailer_key ~ '^[A-Za-z0-9_-]{1,20}$'),
      details_from text not null check (details_from in ('tmdb', 'manual')),
      fetched_at timestamptz,
      created_at timestamptz not null default now(),
      unique (kind, tmdb_id),
      unique (id, kind),
      check ((details_from = 'tmdb') = (tmdb_id is not null))
    )
    """,
    """
    create index sources_title_idx
      on public.sources (lower(title) text_pattern_ops)
    """,
    # A VJ's edition of a source title. While it is a draft, its source and
    # VJ may still be unknown.
    """
    create table public.editions (
      id uuid primary key default gen_random_uuid(),
      kind text not null check (kind in ('movie', 'series')),
      source_id uuid,
      vj_id uuid references public.vjs (id),
      language text not null default 'lg' references public.languages (code),
      display_title text not null
        check (char_length(display_title) between 1 and 200),
      submitted_year integer check (submitted_year between 1900 and 2100),
      poster_path text check (char_length(poster_path) <= 300),
      status text not null default 'draft'
        check (status in ('draft', 'published', 'hidden')),
      tmdb_lookup text
        check (tmdb_lookup in
               ('clear', 'choose', 'none', 'failed', 'chosen', 'manual')),
      tmdb_lookup_at timestamptz,
      published_at timestamptz,
      test boolean not null default false,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      foreign key (source_id, kind) references public.sources (id, kind),
      unique (id, kind),
      check (status <> 'published' or published_at is not null),
      check (status <> 'published' or test
             or (source_id is not null and vj_id is not null
                 and poster_path is not null))
    )
    """,
    # One edition per source title per VJ.
    """
    create unique index editions_one_per_vj_idx on public.editions (source_id, vj_id)
      where source_id is not null and vj_id is not null
    """,
    "create index editions_published_idx on public.editions (published_at desc) "
    "where status = 'published'",
    # What a grant, an upload key and an original belong to. A movie
    # edition's one item has no season or episode.
    """
    create table public.items (
      id uuid primary key default gen_random_uuid(),
      edition_id uuid not null,
      kind text not null check (kind in ('movie', 'series')),
      season integer check (season between 0 and 999),
      episode integer check (episode between 1 and 9999),
      episode_title text check (char_length(episode_title) <= 200),
      approved_at timestamptz,
      created_at timestamptz not null default now(),
      foreign key (edition_id, kind) references public.editions (id, kind),
      check ((kind = 'movie') = (season is null and episode is null)),
      check (kind = 'movie' or (season is not null and episode is not null))
    )
    """,
    "create unique index items_one_per_movie_idx on public.items (edition_id) "
    "where kind = 'movie'",
    "create unique index items_episode_idx on public.items "
    "(edition_id, season, episode) where kind = 'series'",
    # TMDB's candidates for an edition whose match wasn't clear.
    """
    create table public.tmdb_matches (
      edition_id uuid not null references public.editions (id) on delete cascade,
      tmdb_id integer not null check (tmdb_id > 0),
      title text not null check (char_length(title) between 1 and 500),
      original_title text check (char_length(original_title) <= 500),
      year integer,
      overview text check (char_length(overview) <= 5000),
      poster_path text check (char_length(poster_path) <= 300),
      position smallint not null check (position between 0 and 49),
      primary key (edition_id, tmdb_id)
    )
    """,
    """
    create table public.admins (
      user_id uuid primary key,
      email text check (char_length(email) <= 320),
      added_by uuid,
      added_at timestamptz not null default now()
    )
    """,
    # The last admin can't be removed, by anyone, so the catalogue can't be
    # locked out by mistake. The owner can still add one from the terminal.
    """
    create function public.keep_one_admin()
    returns trigger language plpgsql set search_path = '' as $$
    begin
      if exists (select from removed) and not exists (select from public.admins)
      then
        raise exception 'The last admin can''t be removed'
          using errcode = 'check_violation';
      end if;
      return null;
    end;
    $$
    """,
    "revoke all on function public.keep_one_admin() from public",
    # After the whole statement, so deleting several at once is judged by
    # what is left.
    """
    create trigger admins_keep_one after delete on public.admins
      referencing old table as removed
      for each statement execute function public.keep_one_admin()
    """,
    # --- Today's films, moved across with their IDs ------------------------
    """
    create temporary table moved on commit drop as
    select m.id, m.tmdb_id, m.published, m.published_at, m.added_at,
           gen_random_uuid() as source_id
    from public.movies m
    """,
    """
    insert into public.sources (
      id, kind, tmdb_id, title, original_title, overview, release_date,
      runtime_minutes, genres, poster_path, backdrop_path, details_from,
      fetched_at, created_at
    )
    select v.source_id, 'movie', v.tmdb_id,
           coalesce(d.title, 'TMDB ' || v.tmdb_id), d.original_title, d.overview,
           d.release_date, d.runtime_minutes, coalesce(d.genres, '{}'),
           d.poster_path, d.backdrop_path, 'tmdb', d.fetched_at, v.added_at
    from moved v
    left join public.tmdb_movie_details d on d.tmdb_id = v.tmdb_id
    """,
    """
    insert into public.editions (
      id, kind, source_id, display_title, poster_path, status, tmdb_lookup,
      published_at, test, created_at
    )
    select v.id, 'movie', v.source_id, s.title, s.poster_path,
           case when v.published then 'published' else 'hidden' end,
           'chosen', v.published_at, true, v.added_at
    from moved v join public.sources s on s.id = v.source_id
    """,
    """
    insert into public.items (id, edition_id, kind, approved_at, created_at)
    select v.id, v.id, 'movie', coalesce(v.published_at, v.added_at), v.added_at
    from moved v
    """,
    # --- Keys and originals belong to items --------------------------------
    # 0004's rule names public.movies, so it goes before the table does.
    "drop policy originals_app_ready on public.media_originals",
    "alter table public.upload_keys rename column movie_id to item_id",
    "alter table public.media_originals rename column movie_id to item_id",
    "alter table public.upload_keys drop constraint upload_keys_movie_id_fkey",
    "alter table public.media_originals drop constraint media_originals_movie_id_fkey",
    """
    alter table public.upload_keys add constraint upload_keys_item_id_fkey
      foreign key (item_id) references public.items (id)
    """,
    """
    alter table public.media_originals add constraint media_originals_item_id_fkey
      foreign key (item_id) references public.items (id)
    """,
    "alter index public.media_originals_one_ready_idx "
    "rename to media_originals_one_ready_per_item_idx",
    # What FFprobe found in the file's own tags, for VJ credit suggestions.
    """
    alter table public.media_originals add column credit_hints text
      check (char_length(credit_hints) <= 500)
    """,
    "drop table public.tmdb_movie_details",
    "drop table public.movies",
    # --- Row-level security -------------------------------------------------
    *(
        statement
        for table in NEW_TABLES
        for statement in (
            f"alter table public.{table} enable row level security",
            f"alter table public.{table} force row level security",
            f"revoke all on table public.{table} from public",
        )
    ),
    # The API's role: only what is published. Each rule's subquery runs under
    # the role's own rule on editions, which shows published editions only.
    f"grant select on table public.languages to {APP_ROLE}",
    f"create policy languages_app on public.languages for select to {APP_ROLE} "
    "using (true)",
    f"grant select on table public.editions to {APP_ROLE}",
    f"""
    create policy editions_app_published on public.editions
      for select to {APP_ROLE}
      using (status = 'published')
    """,
    f"grant select (id, name, slug, photo_path, bio) on table public.vjs to {APP_ROLE}",
    f"""
    create policy vjs_app_published on public.vjs
      for select to {APP_ROLE}
      using (exists (
        select from public.editions e where e.vj_id = vjs.id
      ))
    """,
    # The API refreshes TMDB details of published sources, as it did for
    # movies. It can't add or delete sources.
    f"grant select on table public.sources to {APP_ROLE}",
    f"""
    grant update (title, original_title, overview, release_date,
                  runtime_minutes, genres, poster_path, backdrop_path,
                  trailer_key, fetched_at)
      on table public.sources to {APP_ROLE}
    """,
    f"""
    create policy sources_app_published on public.sources
      for all to {APP_ROLE}
      using (exists (
        select from public.editions e where e.source_id = sources.id
      ))
      with check (exists (
        select from public.editions e where e.source_id = sources.id
      ))
    """,
    f"""
    grant select (id, edition_id, kind, season, episode, episode_title)
      on table public.items to {APP_ROLE}
    """,
    f"""
    create policy items_app_approved on public.items
      for select to {APP_ROLE}
      using (approved_at is not null and exists (
        select from public.editions e where e.id = items.edition_id
      ))
    """,
    f"grant select (id, item_id, state) on table public.media_originals to {APP_ROLE}",
    f"""
    create policy originals_app_ready on public.media_originals
      for select to {APP_ROLE}
      using (state = 'ready' and exists (
        select from public.items i where i.id = media_originals.item_id
      ))
    """,
    # The editor role: the admin routes. The catalogue, keys (by hash only)
    # and admins. Never profiles, Neon Auth or the schema, and it deletes
    # nothing but TMDB candidates and admins.
    *(
        statement
        for table in ("languages", "vjs", "sources", "editions", "items")
        for statement in (
            f"grant select, insert, update on table public.{table} to {EDITOR_ROLE}",
            f"create policy {table}_editor on public.{table} for all "
            f"to {EDITOR_ROLE} using (true) with check (true)",
        )
    ),
    f"""
    grant select, insert, update, delete on table public.tmdb_matches
      to {EDITOR_ROLE}
    """,
    f"create policy tmdb_matches_editor on public.tmdb_matches for all "
    f"to {EDITOR_ROLE} using (true) with check (true)",
    f"grant select, insert, delete on table public.admins to {EDITOR_ROLE}",
    f"create policy admins_editor on public.admins for all "
    f"to {EDITOR_ROLE} using (true) with check (true)",
    f"""
    grant select (id, item_id, label, created_at, expires_at, used_at, revoked_at)
      on table public.upload_keys to {EDITOR_ROLE}
    """,
    f"""
    grant insert (item_id, key_hash, label, expires_at)
      on table public.upload_keys to {EDITOR_ROLE}
    """,
    f"grant update (revoked_at) on table public.upload_keys to {EDITOR_ROLE}",
    f"create policy keys_editor on public.upload_keys for all "
    f"to {EDITOR_ROLE} using (true) with check (true)",
    f"grant select on table public.media_originals to {EDITOR_ROLE}",
    f"create policy originals_editor on public.media_originals for select "
    f"to {EDITOR_ROLE} using (true)",
    f"grant select on table public.media_renditions to {EDITOR_ROLE}",
    f"create policy renditions_editor on public.media_renditions for select "
    f"to {EDITOR_ROLE} using (true)",
    # The media role also records what FFprobe found in the file's tags.
    f"grant update (credit_hints) on table public.media_originals to {MEDIA_ROLE}",
]

# For local test databases only. Never downgrade a hosted branch: fix
# mistakes with a new migration. Editions and items made after the upgrade
# are lost; moved films come back as movies.
DOWNGRADE = [
    "drop policy originals_app_ready on public.media_originals",
    "drop policy originals_editor on public.media_originals",
    "drop policy renditions_editor on public.media_renditions",
    "drop policy keys_editor on public.upload_keys",
    f"revoke all on table public.media_originals, public.media_renditions, "
    f"public.upload_keys from {EDITOR_ROLE}",
    f"revoke update (credit_hints) on table public.media_originals from {MEDIA_ROLE}",
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
    """
    insert into public.movies (id, tmdb_id, published, added_at, published_at)
    select e.id, s.tmdb_id, e.status = 'published', e.created_at,
           case when e.status = 'published' then e.published_at end
    from public.editions e join public.sources s on s.id = e.source_id
    where e.test and s.tmdb_id is not null
    """,
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
    insert into public.tmdb_movie_details
    select s.tmdb_id, s.title, s.original_title, s.overview, s.release_date,
           s.runtime_minutes, s.genres, s.poster_path, s.backdrop_path, s.fetched_at
    from public.sources s join public.movies m on m.tmdb_id = s.tmdb_id
    where s.fetched_at is not null
    """,
    "delete from public.media_renditions where original_id in (select id from "
    "public.media_originals where item_id not in (select id from public.movies))",
    "delete from public.media_originals where item_id not in "
    "(select id from public.movies)",
    "delete from public.upload_keys where item_id not in "
    "(select id from public.movies)",
    "alter table public.media_originals drop column credit_hints",
    "alter table public.upload_keys drop constraint upload_keys_item_id_fkey",
    "alter table public.media_originals drop constraint media_originals_item_id_fkey",
    "alter table public.upload_keys rename column item_id to movie_id",
    "alter table public.media_originals rename column item_id to movie_id",
    "alter index public.media_originals_one_ready_per_item_idx "
    "rename to media_originals_one_ready_idx",
    """
    alter table public.upload_keys add constraint upload_keys_movie_id_fkey
      foreign key (movie_id) references public.movies (id)
    """,
    """
    alter table public.media_originals add constraint media_originals_movie_id_fkey
      foreign key (movie_id) references public.movies (id)
    """,
    *(f"drop table public.{table} cascade" for table in reversed(NEW_TABLES)),
    "drop function public.keep_one_admin()",
    # As 0002 and 0004 left them.
    "alter table public.movies enable row level security",
    "alter table public.movies force row level security",
    "alter table public.tmdb_movie_details enable row level security",
    "alter table public.tmdb_movie_details force row level security",
    "revoke all on table public.movies, public.tmdb_movie_details from public",
    f"grant select on table public.movies to {APP_ROLE}",
    f"""
    create policy movies_select_published on public.movies
      for select to {APP_ROLE} using (published)
    """,
    f"grant select, insert, update on table public.tmdb_movie_details to {APP_ROLE}",
    f"""
    create policy details_of_published on public.tmdb_movie_details
      for all to {APP_ROLE}
      using (exists (
        select from public.movies m
        where m.tmdb_id = tmdb_movie_details.tmdb_id and m.published
      ))
      with check (exists (
        select from public.movies m
        where m.tmdb_id = tmdb_movie_details.tmdb_id and m.published
      ))
    """,
    f"""
    create policy originals_app_ready on public.media_originals
      for select to {APP_ROLE}
      using (state = 'ready' and exists (
        select from public.movies m
        where m.id = media_originals.movie_id and m.published
      ))
    """,
    f"drop role if exists {EDITOR_ROLE}",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
