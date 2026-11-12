"""Uploads: one-time upload keys, originals, and the qualities made from them.

Revision ID: 0003
Revises: 0002
Create Date: 2026-11-12

Hand-written SQL, from docs/step-07a-uploads-plan.md, "Database". The owner's
catalogue script issues and revokes keys. The media role, used by the upload
hooks and the media worker, claims a key once, moves originals through their
states, and records the qualities it makes. The API's role can't see any of
it.
"""

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None

MEDIA_ROLE = "veloraug_media"

ORIGINAL_STATES = (
    "uploading",
    "received",
    "checking",
    "refused",
    "converting",
    "publishing",
    "ready",
    "failed",
    "removing",
    "removed",
)
HEIGHTS = (360, 480, 720, 1080)

UPGRADE = [
    # Without a login until Step 7C gives it a password. Created here so the
    # grants below have a role to name. No special rights, as for
    # veloraug_app.
    f"""
    do $$ begin
      if not exists (select from pg_roles where rolname = '{MEDIA_ROLE}') then
        create role {MEDIA_ROLE} nologin nosuperuser nocreatedb nocreaterole
          noinherit noreplication nobypassrls connection limit 10;
      end if;
    end $$
    """,
    # A key is stored only as the SHA-256 of the text the owner was shown.
    # One key uploads one file, for one movie.
    """
    create table public.upload_keys (
      id uuid primary key default gen_random_uuid(),
      movie_id uuid not null references public.movies (id),
      key_hash bytea not null unique check (octet_length(key_hash) = 32),
      label text not null check (char_length(label) between 1 and 100),
      created_at timestamptz not null default now(),
      expires_at timestamptz not null,
      used_at timestamptz,
      revoked_at timestamptz,
      check (expires_at > created_at)
    )
    """,
    # One per upload. Its ID is also tusd's upload ID.
    f"""
    create table public.media_originals (
      id uuid primary key,
      movie_id uuid not null references public.movies (id),
      upload_key_id uuid not null unique references public.upload_keys (id),
      state text not null default 'uploading'
        check (state in ({", ".join(f"'{s}'" for s in ORIGINAL_STATES)})),
      size_bytes bigint not null check (size_bytes > 0),
      filename text check (char_length(filename) <= 255),
      width integer check (width > 0),
      height integer check (height > 0),
      duration_seconds numeric check (duration_seconds > 0),
      video_codec text check (char_length(video_codec) <= 50),
      audio_codec text check (char_length(audio_codec) <= 50),
      reason text check (char_length(reason) <= 500),
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      ready_at timestamptz,
      check (state <> 'ready' or ready_at is not null)
    )
    """,
    # At most one original per movie is the one viewers get.
    """
    create unique index media_originals_one_ready_idx
      on public.media_originals (movie_id) where state = 'ready'
    """,
    """
    create index media_originals_waiting_idx on public.media_originals (created_at)
      where state in ('received', 'removing')
    """,
    # One per quality made from an original, added as each is published.
    f"""
    create table public.media_renditions (
      original_id uuid not null references public.media_originals (id),
      height integer not null check (height in ({", ".join(map(str, HEIGHTS))})),
      width integer not null check (width > 0),
      bandwidth integer not null check (bandwidth > 0),
      size_bytes bigint not null check (size_bytes > 0),
      created_at timestamptz not null default now(),
      primary key (original_id, height)
    )
    """,
    "alter table public.upload_keys enable row level security",
    "alter table public.upload_keys force row level security",
    "alter table public.media_originals enable row level security",
    "alter table public.media_originals force row level security",
    "alter table public.media_renditions enable row level security",
    "alter table public.media_renditions force row level security",
    """
    revoke all on table public.upload_keys, public.media_originals,
      public.media_renditions from public
    """,
    # The media role finds a key by its hash and marks it used, once, while
    # it is still valid. It can't create, revoke or relabel keys.
    f"""
    grant select (id, movie_id, key_hash, expires_at, used_at, revoked_at)
      on table public.upload_keys to {MEDIA_ROLE}
    """,
    f"grant update (used_at) on table public.upload_keys to {MEDIA_ROLE}",
    f"""
    create policy keys_media_select on public.upload_keys
      for select to {MEDIA_ROLE}
      using (true)
    """,
    f"""
    create policy keys_media_claim on public.upload_keys
      for update to {MEDIA_ROLE}
      using (used_at is null and revoked_at is null and expires_at > now())
      with check (used_at is not null)
    """,
    # An original can only be created from a claimed key, for that key's
    # movie. The media role can't delete originals: the owner marks one
    # 'removing', and the worker deletes its files and marks it 'removed'.
    f"grant select on table public.media_originals to {MEDIA_ROLE}",
    f"""
    grant insert (id, movie_id, upload_key_id, size_bytes, filename)
      on table public.media_originals to {MEDIA_ROLE}
    """,
    f"""
    grant update (state, width, height, duration_seconds, video_codec,
                  audio_codec, reason, updated_at, ready_at)
      on table public.media_originals to {MEDIA_ROLE}
    """,
    f"""
    create policy originals_media_select on public.media_originals
      for select to {MEDIA_ROLE}
      using (true)
    """,
    f"""
    create policy originals_media_insert on public.media_originals
      for insert to {MEDIA_ROLE}
      with check (exists (
        select from public.upload_keys k
        where k.id = upload_key_id
          and k.movie_id = media_originals.movie_id
          and k.used_at is not null
          and k.revoked_at is null
      ))
    """,
    f"""
    create policy originals_media_update on public.media_originals
      for update to {MEDIA_ROLE}
      using (state <> 'removed')
      with check (true)
    """,
    # Qualities are added while an original is being published, and deleted
    # while it is being removed.
    f"grant select, insert, delete on table public.media_renditions to {MEDIA_ROLE}",
    f"""
    create policy renditions_media_select on public.media_renditions
      for select to {MEDIA_ROLE}
      using (true)
    """,
    f"""
    create policy renditions_media_insert on public.media_renditions
      for insert to {MEDIA_ROLE}
      with check (exists (
        select from public.media_originals o
        where o.id = original_id and o.state = 'publishing'
      ))
    """,
    f"""
    create policy renditions_media_delete on public.media_renditions
      for delete to {MEDIA_ROLE}
      using (exists (
        select from public.media_originals o
        where o.id = original_id and o.state = 'removing'
      ))
    """,
]

# For local test databases only. Never downgrade a hosted branch: fix
# mistakes with a new migration.
DOWNGRADE = [
    "drop table public.media_renditions",
    "drop table public.media_originals",
    "drop table public.upload_keys",
    f"drop role if exists {MEDIA_ROLE}",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
