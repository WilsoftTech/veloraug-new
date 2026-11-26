"""Conversion progress, and deleting drafts for good.

Revision ID: 0015
Revises: 0014
Create Date: 2026-11-26

Progress: the media worker writes how far it has got converting or
publishing an original, as a whole percentage, with when it said so. The
admin's Drafts tab shows it as a bar. It is null in any other state.

Deleting: an admin deletes an edition with public.delete_edition. It is
marked deleted at once, so no screen lists it and viewers never see it, its
upload keys are revoked, and its videos are marked 'removing', so the media
worker deletes their files from R2 and this computer. Once none of its
videos is left, public.purge_deleted_editions deletes its rows: the
edition, its items, keys, originals and viewers' history of it. The API
calls it when Drafts loads and the worker calls it as it goes, so a deleted
edition is gone soon after its last file.

Both functions run as the owner, because the editor role can't change a
video's state or delete rows, and shouldn't be able to otherwise. They do
only this.
"""

from alembic import op

revision = "0015"
down_revision = "0014"
branch_labels = None
depends_on = None

EDITOR_ROLE = "veloraug_editor"
MEDIA_ROLE = "veloraug_media"

UPGRADE = [
    "alter table public.editions add column deleted_at timestamptz",
    """
    create index editions_deleted_idx on public.editions (deleted_at)
      where deleted_at is not null
    """,
    """
    alter table public.media_originals
      add column progress smallint check (progress between 0 and 100),
      add column progress_at timestamptz
    """,
    f"grant update (progress, progress_at) on table public.media_originals "
    f"to {MEDIA_ROLE}",
    # Marks every deleted edition's videos for removal, then deletes the rows
    # of those whose videos are all gone. One still being checked or
    # converted is left to finish, and marked on a later run. Answers how
    # many editions were deleted.
    """
    create function public.purge_deleted_editions()
    returns integer language plpgsql volatile security definer
    set search_path = '' as $$
    declare
      done uuid[];
      sources uuid[];
    begin
      update public.media_originals o
      set state = 'removing', progress = null, updated_at = now()
      from public.items i join public.editions e on e.id = i.edition_id
      where o.item_id = i.id and e.deleted_at is not null
        and o.state not in ('removing', 'removed', 'checking', 'converting');

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
      -- A source another edition still uses is kept.
      delete from public.sources s where s.id = any(sources)
        and not exists (select from public.editions e where e.source_id = s.id);
      return cardinality(done);
    end;
    $$
    """,
    # Deletes one edition, as above. False when there is no such edition.
    """
    create function public.delete_edition(target uuid)
    returns boolean language plpgsql volatile security definer
    set search_path = '' as $$
    begin
      update public.editions
      set deleted_at = coalesce(deleted_at, now()),
          status = case when status = 'published' then 'hidden' else status end,
          updated_at = now()
      where id = target;
      if not found then
        return false;
      end if;
      update public.upload_keys k set revoked_at = coalesce(k.revoked_at, now())
      from public.items i
      where k.item_id = i.id and i.edition_id = target;
      perform public.purge_deleted_editions();
      return true;
    end;
    $$
    """,
    "revoke all on function public.purge_deleted_editions() from public",
    "revoke all on function public.delete_edition(uuid) from public",
    f"grant execute on function public.purge_deleted_editions() to {EDITOR_ROLE}",
    f"grant execute on function public.purge_deleted_editions() to {MEDIA_ROLE}",
    f"grant execute on function public.delete_edition(uuid) to {EDITOR_ROLE}",
]

# For local test databases only. Never downgrade a hosted branch.
DOWNGRADE = [
    "drop function public.delete_edition(uuid)",
    "drop function public.purge_deleted_editions()",
    f"revoke update (progress, progress_at) on table public.media_originals "
    f"from {MEDIA_ROLE}",
    "alter table public.media_originals drop column progress_at",
    "alter table public.media_originals drop column progress",
    "drop index public.editions_deleted_idx",
    "alter table public.editions drop column deleted_at",
]


def upgrade() -> None:
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    for statement in DOWNGRADE:
        op.execute(statement)
