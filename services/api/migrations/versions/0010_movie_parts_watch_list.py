"""Allow shared movie metadata and store account-scoped Watch Lists."""

from alembic import op

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("drop index public.editions_one_per_vj_idx")
    op.execute("""
        create unique index editions_one_series_per_vj_idx
        on public.editions (source_id, vj_id)
        where kind = 'series' and source_id is not null and vj_id is not null
    """)
    op.execute(
        "create index editions_source_vj_idx on public.editions (source_id, vj_id)"
    )
    op.execute("""
        create table public.watch_list (
          user_id uuid not null,
          item_id uuid not null references public.items(id) on delete cascade,
          added_at timestamptz not null default now(),
          primary key (user_id, item_id)
        )
    """)
    op.execute("create index watch_list_item_idx on public.watch_list (item_id)")
    op.execute("alter table public.watch_list enable row level security")
    op.execute("alter table public.watch_list force row level security")
    op.execute("revoke all on public.watch_list from public")
    op.execute("grant select, insert, delete on public.watch_list to veloraug_app")
    op.execute("""
        create policy watch_list_app_own on public.watch_list for all
        to veloraug_app
        using (user_id = public.current_app_user_id())
        with check (user_id = public.current_app_user_id())
    """)


def downgrade() -> None:
    # Local tests only. Duplicate editions must be resolved before downgrading.
    op.execute("""
        create unique index editions_one_per_vj_idx
        on public.editions (source_id, vj_id)
        where source_id is not null and vj_id is not null
    """)
    op.execute("drop index public.editions_source_vj_idx")
    op.execute("drop index public.editions_one_series_per_vj_idx")
    op.execute("drop table public.watch_list")
