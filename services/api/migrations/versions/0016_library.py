"""The admin's Library: editing published titles, and hiding or deleting
single episodes.

Revision ID: 0016
Revises: 0015
Create Date: 2026-11-26

A VJ's edition can now have its own description, backdrop and trailer.
Each is null until an admin sets it, and viewers then see the source's, from
TMDB or typed in, as before. The source is shared by every VJ's edition of
the same film, so changing it there would change theirs too.

An episode can be hidden, apart from its series: viewers stop seeing it, and
it doesn't wait for approval in Drafts. It can also be deleted: as with a
whole edition in 0015, its videos are removed by the media worker first,
and its rows after them. A deleted episode keeps its number until then.

Admins can count each title's viewers, as the API's role already could.
"""

import importlib.util
from pathlib import Path

from alembic import op

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None

APP_ROLE = "veloraug_app"
EDITOR_ROLE = "veloraug_editor"
MEDIA_ROLE = "veloraug_media"


def _previous_purge() -> str:
    """0015's purge function, for downgrading."""
    path = Path(__file__).with_name("0015_draft_progress_and_deleting.py")
    spec = importlib.util.spec_from_file_location("migration_0015", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    [statement] = [
        s
        for s in module.UPGRADE
        if "create function public.purge_deleted_editions" in s
    ]
    return statement.replace("create function", "create or replace function", 1)


UPGRADE = [
    """
    alter table public.editions
      add column overview text check (char_length(overview) between 1 and 5000),
      add column backdrop_path text check (char_length(backdrop_path) <= 300),
      add column trailer_key text check (trailer_key ~ '^[A-Za-z0-9_-]{6,20}$')
    """,
    """
    alter table public.items
      add column hidden_at timestamptz,
      add column deleted_at timestamptz
    """,
    # Viewers see approved episodes that aren't hidden or being deleted.
    "drop policy items_app_approved on public.items",
    f"""
    create policy items_app_approved on public.items
      for select to {APP_ROLE}
      using (approved_at is not null and hidden_at is null and deleted_at is null
             and exists (
               select from public.editions e where e.id = items.edition_id
             ))
    """,
    f"grant execute on function public.edition_viewers(integer) to {EDITOR_ROLE}",
    # As in 0015, and also for single deleted episodes.
    """
    create or replace function public.purge_deleted_editions()
    returns integer language plpgsql volatile security definer
    set search_path = '' as $$
    declare
      done uuid[];
      sources uuid[];
      episodes uuid[];
    begin
      update public.media_originals o
      set state = 'removing', progress = null, updated_at = now()
      from public.items i join public.editions e on e.id = i.edition_id
      where o.item_id = i.id
        and (e.deleted_at is not null or i.deleted_at is not null)
        and o.state not in ('removing', 'removed', 'checking', 'converting');

      -- Single episodes whose videos are all gone.
      select coalesce(array_agg(i.id), '{}') into episodes
      from public.items i
      where i.deleted_at is not null and not exists (
        select from public.media_originals o
        where o.item_id = i.id and o.state <> 'removed');
      if cardinality(episodes) > 0 then
        delete from public.media_renditions r using public.media_originals o
        where r.original_id = o.id and o.item_id = any(episodes);
        delete from public.media_originals where item_id = any(episodes);
        delete from public.upload_keys where item_id = any(episodes);
        delete from public.watch_history where item_id = any(episodes);
        delete from public.items where id = any(episodes);
      end if;

      select coalesce(array_agg(e.id), '{}'),
             coalesce(array_agg(distinct e.source_id)
                      filter (where e.source_id is not null), '{}')
        into done, sources
      from public.editions e
      where e.deleted_at is not null and not exists (
        select from public.items i join public.media_originals o
          on o.item_id = i.id
        where i.edition_id = e.id and o.state <> 'removed');

      if cardinality(done) = 0 then
        return 0;
      end if;

      delete from public.media_renditions r using public.media_originals o,
        public.items i
      where r.original_id = o.id and o.item_id = i.id
        and i.edition_id = any(done);
      delete from public.media_originals o using public.items i
      where o.item_id = i.id and i.edition_id = any(done);
      delete from public.upload_keys k using public.items i
      where k.item_id = i.id and i.edition_id = any(done);
      delete from public.watch_history h using public.items i
      where h.item_id = i.id and i.edition_id = any(done);
      delete from public.items where edition_id = any(done);
      delete from public.editions where id = any(done);
      delete from public.sources s where s.id = any(sources)
        and not exists (select from public.editions e where e.source_id = s.id);
      return cardinality(done);
    end;
    $$
    """,
    # Deletes one episode, as delete_edition does a whole edition. False when
    # there is no such episode.
    """
    create function public.delete_item(target uuid)
    returns boolean language plpgsql volatile security definer
    set search_path = '' as $$
    begin
      update public.items
      set deleted_at = coalesce(deleted_at, now()),
          hidden_at = coalesce(hidden_at, now())
      where id = target;
      if not found then
        return false;
      end if;
      update public.upload_keys set revoked_at = coalesce(revoked_at, now())
      where item_id = target;
      perform public.purge_deleted_editions();
      return true;
    end;
    $$
    """,
    "revoke all on function public.delete_item(uuid) from public",
    f"grant execute on function public.delete_item(uuid) to {EDITOR_ROLE}",
]

# For local test databases only. Never downgrade a hosted branch.
DOWNGRADE = [
    "drop function public.delete_item(uuid)",
    _previous_purge,
    f"revoke execute on function public.edition_viewers(integer) from {EDITOR_ROLE}",
    "drop policy items_app_approved on public.items",
    f"""
    create policy items_app_approved on public.items
      for select to {APP_ROLE}
      using (approved_at is not null and exists (
        select from public.editions e where e.id = items.edition_id
      ))
    """,
    "alter table public.items drop column deleted_at, drop column hidden_at",
    """
    alter table public.editions
      drop column trailer_key, drop column backdrop_path, drop column overview
    """,
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement() if callable(statement) else statement)
