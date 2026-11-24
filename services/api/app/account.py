"""The signed-in viewer's account hub: watch history, notifications, and
deleting the account. Every function runs inside Database.as_user, so
row-level security limits it to the viewer's own rows, and each also
filters on the viewer's ID.

Notifications aren't stored. They are built from the viewer's own records,
so only real events appear, each with a stable ID: a confirmed payment, a
refund, a pass ending soon or ended, a device an admin removed. Only which
ones were read is stored. They carry a plan's name or a device's label at
most: never an amount, a phone number, an email or a payment reference.
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Protocol
from uuid import UUID

import psycopg

from app import audit
from app.viewer import _FROM, _SUMMARY, EditionSummary

# --- Watch history -----------------------------------------------------------

# A position this close to the start isn't worth resuming from.
RESUME_FROM_SECONDS = 30


@dataclass(frozen=True)
class HistoryEntry:
    item_id: UUID
    season: int | None
    episode: int | None
    episode_title: str | None
    last_watched_at: datetime
    position_seconds: int | None
    finished: bool
    edition: EditionSummary

    @property
    def resume_at(self) -> int | None:
        """Where to resume, when a reliable position was saved."""
        if self.finished or self.position_seconds is None:
            return None
        if self.position_seconds < RESUME_FROM_SECONDS:
            return None
        return self.position_seconds


def record_playback_grant(
    conn: psycopg.Connection, user_id: UUID, item_id: UUID
) -> None:
    """Allow progress reports for this item without marking it watched."""
    conn.execute(
        """
        insert into public.watch_history (user_id, item_id) values (%s, %s)
        on conflict (user_id, item_id) do nothing
        """,
        (user_id, item_id),
    )


def save_position(
    conn: psycopg.Connection,
    user_id: UUID,
    item_id: UUID,
    position_seconds: int,
    *,
    finished: bool,
) -> bool:
    """Saves where the viewer got to in an item they were granted. False if
    they never started it."""
    row = conn.execute(
        """
        update public.watch_history
        set position_seconds = %s, position_at = now(), finished = %s,
            last_watched_at = now()
        where user_id = %s and item_id = %s
        returning item_id
        """,
        (None if finished else position_seconds, finished, user_id, item_id),
    ).fetchone()
    return row is not None


def history(conn: psycopg.Connection, user_id: UUID, limit: int) -> list[HistoryEntry]:
    """What the viewer watched, latest first. Titles no longer published
    are left out, because the API's role can't see them."""
    rows = conn.execute(
        f"""
        select h.item_id, i.season, i.episode, i.episode_title,
               h.last_watched_at, h.position_seconds, h.finished, {_SUMMARY}
        from public.watch_history h
        join public.items i on i.id = h.item_id
        join public.editions e on e.id = i.edition_id
        {_FROM_REST}
        where h.user_id = %s and h.position_at is not null
        order by h.last_watched_at desc
        limit %s
        """,
        (user_id, limit),
    ).fetchall()
    return [HistoryEntry(*row[:7], edition=EditionSummary(*row[7:])) for row in rows]


# _FROM starts "from public.editions e"; history joins editions itself.
_FROM_REST = _FROM.split("public.editions e", 1)[1]


@dataclass(frozen=True)
class SavedItem:
    item_id: UUID
    season: int | None
    episode: int | None
    episode_title: str | None
    edition: EditionSummary


def watch_list(conn: psycopg.Connection, user_id: UUID) -> list[SavedItem]:
    rows = conn.execute(
        f"""
        select w.item_id, i.season, i.episode, i.episode_title, {_SUMMARY}
        from public.watch_list w
        join public.items i on i.id = w.item_id
        join public.editions e on e.id = i.edition_id
        {_FROM_REST}
        where w.user_id = %s
        order by w.added_at desc, w.item_id
        """,
        (user_id,),
    ).fetchall()
    return [SavedItem(*row[:4], edition=EditionSummary(*row[4:])) for row in rows]


def saved_item_ids(
    conn: psycopg.Connection, user_id: UUID, edition_id: UUID
) -> list[UUID]:
    rows = conn.execute(
        """
        select w.item_id from public.watch_list w
        join public.items i on i.id = w.item_id
        where w.user_id = %s and i.edition_id = %s
        """,
        (user_id, edition_id),
    ).fetchall()
    return [row[0] for row in rows]


def add_to_watch_list(conn: psycopg.Connection, user_id: UUID, item_id: UUID) -> None:
    conn.execute(
        """
        insert into public.watch_list (user_id, item_id)
        select %s, i.id from public.items i where i.id = %s
        on conflict (user_id, item_id) do nothing
        """,
        (user_id, item_id),
    )


def remove_from_watch_list(
    conn: psycopg.Connection, user_id: UUID, item_id: UUID
) -> None:
    conn.execute(
        "delete from public.watch_list where user_id = %s and item_id = %s",
        (user_id, item_id),
    )


# --- Notifications -----------------------------------------------------------

# Older events aren't shown.
NOTIFICATIONS_FOR = timedelta(days=90)
# A pass this close to its end, with nothing bought to follow it, is worth
# a reminder.
ENDING_SOON = timedelta(days=3)
MAX_NOTIFICATIONS = 50

KINDS = (
    "payment_completed",
    "payment_refunded",
    "pass_ending",
    "pass_ended",
    "device_removed",
)


@dataclass(frozen=True)
class Notification:
    id: str
    kind: str
    at: datetime
    plan_name: str | None
    device_label: str | None
    read: bool


_NOTIFICATIONS = """
with events as (
  select 'payment.completed:' || p.id as id, 'payment_completed' as kind,
         p.completed_at as at, p.plan_name, null::text as device_label
  from public.payments p
  where p.user_id = %(user)s and p.state in ('completed', 'refunded')
    and p.completed_at is not null
  union all
  select 'payment.refunded:' || p.id, 'payment_refunded', p.refunded_at,
         p.plan_name, null
  from public.payments p
  where p.user_id = %(user)s and p.state = 'refunded' and p.refunded_at is not null
  union all
  select 'pass.ending:' || s.id, 'pass_ending', s.ends_at - %(soon)s,
         p.plan_name, null
  from public.passes s join public.payments p on p.id = s.payment_id
  where s.user_id = %(user)s and s.revoked_at is null
    and s.ends_at > %(now)s and s.ends_at - %(soon)s <= %(now)s
    and not exists (
      select from public.passes later
      where later.user_id = s.user_id and later.revoked_at is null
        and later.starts_at >= s.ends_at
    )
  union all
  select 'pass.ended:' || s.id, 'pass_ended', s.ends_at, p.plan_name, null
  from public.passes s join public.payments p on p.id = s.payment_id
  where s.user_id = %(user)s and s.revoked_at is null and s.ends_at <= %(now)s
  union all
  select 'device.removed:' || d.id, 'device_removed', d.revoked_at, null, d.label
  from public.devices d
  where d.user_id = %(user)s and d.revoked_by = 'admin'
)
select e.id, e.kind, e.at, e.plan_name, e.device_label, r.notification_id is not null
from events e
left join public.notification_reads r
  on r.user_id = %(user)s and r.notification_id = e.id
where e.at > %(since)s and e.at <= %(now)s
order by e.at desc, e.id
limit %(limit)s
"""


def notifications(
    conn: psycopg.Connection, user_id: UUID, now: datetime
) -> list[Notification]:
    rows = conn.execute(
        _NOTIFICATIONS,
        {
            "user": user_id,
            "now": now,
            "since": now - NOTIFICATIONS_FOR,
            "soon": ENDING_SOON,
            "limit": MAX_NOTIFICATIONS,
        },
    ).fetchall()
    return [Notification(*row) for row in rows]


def mark_read(conn: psycopg.Connection, user_id: UUID, ids: list[str]) -> None:
    """Marks the viewer's notifications read. IDs that aren't theirs now are
    ignored."""
    if not ids:
        return
    conn.execute(
        """
        insert into public.notification_reads (user_id, notification_id)
        select %s, unnest(%s::text[])
        on conflict (user_id, notification_id) do nothing
        """,
        (user_id, ids),
    )


# --- Account deletion --------------------------------------------------------

# Deleting the account needs a sign-in this recent.
RECENT_SIGN_IN = timedelta(minutes=10)


class IdentityDeletionFailed(Exception):
    """The identity provider didn't confirm the sign-in account was removed."""


class IdentityDeleter(Protocol):
    """Removes a sign-in account at the identity provider. Must succeed, or
    raise IdentityDeletionFailed, and treat an account already gone as
    removed, so a retry is safe."""

    def delete(self, user_id: UUID) -> None: ...


@dataclass(frozen=True)
class Deletion:
    requested_at: datetime
    attempts: int
    data_removed_at: datetime | None
    identity_removed_at: datetime | None
    completed_at: datetime | None


def get_deletion(conn: psycopg.Connection, user_id: UUID) -> Deletion | None:
    row = conn.execute(
        """
        select requested_at, attempts, data_removed_at, identity_removed_at,
               completed_at
        from public.account_deletions where user_id = %s
        """,
        (user_id,),
    ).fetchone()
    return Deletion(*row) if row else None


def start_deletion(conn: psycopg.Connection, user_id: UUID) -> Deletion:
    """Records the request, or one more attempt at it."""
    row = conn.execute(
        """
        insert into public.account_deletions (user_id) values (%s)
        on conflict (user_id) do update
          set attempts = least(public.account_deletions.attempts + 1, 1000)
        returning requested_at, attempts, data_removed_at, identity_removed_at,
                  completed_at
        """,
        (user_id,),
    ).fetchone()
    return Deletion(*row)


def remove_account_data(conn: psycopg.Connection, user_id: UUID, now: datetime) -> None:
    """Removes what VeloraUG keeps about the viewer, as agreed so far: the
    profile, watch history and notification read marks are deleted; every
    device is removed and anything playing is stopped. Payments and passes
    are kept, for payment reconciliation and the records the law requires.
    Running it again changes nothing more."""
    conn.execute(
        """
        update public.playback_sessions set ended_at = %s, end_reason = 'owner'
        where user_id = %s and ended_at is null
        """,
        (now, user_id),
    )
    conn.execute(
        """
        update public.devices set revoked_at = %s, revoked_by = 'owner'
        where user_id = %s and revoked_at is null
        """,
        (now, user_id),
    )
    conn.execute("delete from public.watch_history where user_id = %s", (user_id,))
    conn.execute("delete from public.watch_list where user_id = %s", (user_id,))
    conn.execute("delete from public.notification_reads where user_id = %s", (user_id,))
    conn.execute("delete from public.profiles where user_id = %s", (user_id,))
    conn.execute(
        """
        update public.account_deletions
        set data_removed_at = coalesce(data_removed_at, %s)
        where user_id = %s
        """,
        (now, user_id),
    )


def finish_deletion(conn: psycopg.Connection, user_id: UUID, now: datetime) -> None:
    conn.execute(
        """
        update public.account_deletions
        set identity_removed_at = coalesce(identity_removed_at, %s),
            completed_at = coalesce(completed_at, %s)
        where user_id = %s
        """,
        (now, now, user_id),
    )
    audit.event("account.deleted", user_id=user_id)
