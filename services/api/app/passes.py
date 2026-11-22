"""Passes and their payments: Step 10B, and the six tiers of Milestone 10.
See docs/step-10a-payments-plan.md.

Everything here runs in Database.as_user, so row-level security limits it
to the viewer's own payments and passes. Pesapal's notifications find a
payment's owner with `owner_of`, by the tracking ID alone.

Only `apply_status` turns a payment into a pass, and only on Pesapal's own
status: COMPLETED, for this payment's reference, its exact amount, in UGX.
The database refuses a pass that doesn't match its payment as well.

Each pass is an entitlement of its own: a start, an end, a plan, and the
devices and streams that plan allowed when it was bought. Passes never
overlap: a new one starts when the last one ends, so buying early never
loses time, and two tiers' allowances are never added together. The pass
running now decides the limits.
"""

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

import psycopg

from app import audit, pesapal
from app.pesapal import PesapalClient, PesapalError, Status

logger = logging.getLogger("veloraug.passes")

CURRENCY = "UGX"
# A payment not completed within this long is given up on.
GIVE_UP_AFTER = timedelta(hours=24)
# Payments that can still change when Pesapal is asked. A completed one
# can still be reversed, but only a notification checks it again.
OPEN = ("started", "pending", "failed")
# Whatever the plan, an account never has more than this many devices or
# streams. The database enforces it too.
MAX_DEVICES = 3
MAX_STREAMS = 3
# A checkout retried this soon, for the same plan at the same price, reuses
# the payment already sent to Pesapal instead of making another.
REUSE_CHECKOUT_FOR = timedelta(minutes=10)
# The lock that serializes one viewer's passes.
_PASS_LOCK = 6


class NotForSale(Exception):
    pass


class PlanChangeRefused(Exception):
    pass


@dataclass(frozen=True)
class Plan:
    id: str
    days: int
    price_ugx: int | None
    display_name: str
    description: str | None
    max_devices: int
    max_streams: int
    display_order: int
    featured: bool
    for_sale: bool
    legacy: bool


@dataclass(frozen=True)
class Payment:
    id: UUID
    user_id: UUID
    plan_id: str
    days: int
    amount_ugx: int
    state: str
    tracking_id: str | None
    email: str | None
    phone: str | None
    created_at: datetime
    plan_name: str
    max_devices: int
    max_streams: int
    redirect_url: str | None
    confirmation_code: str | None
    completed_at: datetime | None
    reason: str | None


@dataclass(frozen=True)
class Entitlement:
    """One pass: its own start, end, plan and allowances."""

    id: UUID
    payment_id: UUID
    plan_id: str
    plan_name: str
    starts_at: datetime
    ends_at: datetime
    max_devices: int
    max_streams: int


@dataclass(frozen=True)
class PassStatus:
    # The pass running now, if any, and when it ends.
    current_ends_at: datetime | None
    # The end of the last pass bought, if any is still to come.
    ends_at: datetime | None


PAYMENT_COLUMNS = (
    "id, user_id, plan_id, days, amount_ugx, state, tracking_id, email, phone, "
    "created_at, plan_name, max_devices, max_streams, redirect_url, "
    "confirmation_code, completed_at, reason"
)
PLAN_COLUMNS = (
    "id, days, price_ugx, display_name, description, max_devices, max_streams, "
    "display_order, featured, for_sale, legacy"
)
ENTITLEMENT_COLUMNS = (
    "s.id, s.payment_id, s.plan_id, p.plan_name, s.starts_at, s.ends_at, "
    "s.max_devices, s.max_streams"
)


# --- Plans -------------------------------------------------------------------


def plans(conn: psycopg.Connection, *, for_sale_only: bool = True) -> list[Plan]:
    """The plans in their display order. For sale: on sale, with a price,
    and not a legacy pass."""
    rows = conn.execute(
        f"select {PLAN_COLUMNS} from public.pass_plans order by display_order, days"
    ).fetchall()
    found = [Plan(*row) for row in rows]
    if not for_sale_only:
        return found
    return [p for p in found if p.for_sale and p.price_ugx is not None and not p.legacy]


def update_plan(
    conn: psycopg.Connection,
    plan_id: str,
    *,
    price_ugx: int | None = None,
    change_price: bool = False,
    for_sale: bool | None = None,
    featured: bool | None = None,
) -> Plan:
    """An admin's change to one plan. Never touches a payment or a pass:
    what was bought keeps its own snapshot. The database records the
    change in plan_changes."""
    row = conn.execute(
        f"select {PLAN_COLUMNS} from public.pass_plans where id = %s for update",
        (plan_id,),
    ).fetchone()
    if row is None:
        raise LookupError(plan_id)
    plan = Plan(*row)
    price = price_ugx if change_price else plan.price_ugx
    sale = plan.for_sale if for_sale is None else for_sale
    feature = plan.featured if featured is None else featured
    if plan.legacy and sale:
        raise PlanChangeRefused("A legacy pass can't go back on sale.")
    if sale and price is None:
        raise PlanChangeRefused("A plan on sale needs a price.")
    if feature and not sale:
        if featured:
            raise PlanChangeRefused("Only a plan on sale can be featured.")
        feature = False
    if feature and not plan.featured:
        # One featured plan at a time.
        conn.execute(
            "update public.pass_plans set featured = false, updated_at = now() "
            "where featured and id <> %s",
            (plan_id,),
        )
    row = conn.execute(
        f"""
        update public.pass_plans
        set price_ugx = %s, for_sale = %s, featured = %s, updated_at = now()
        where id = %s returning {PLAN_COLUMNS}
        """,
        (price, sale, feature, plan_id),
    ).fetchone()
    return Plan(*row)


def set_price(conn: psycopg.Connection, plan_id: str, price_ugx: int | None) -> Plan:
    """Step 10B's price change. No price also takes the plan off sale."""
    return update_plan(
        conn,
        plan_id,
        price_ugx=price_ugx,
        change_price=True,
        for_sale=False if price_ugx is None else None,
    )


# --- Payments ----------------------------------------------------------------


def start_payment(
    conn: psycopg.Connection,
    user_id: UUID,
    plan_id: str,
    *,
    email: str | None,
    phone: str | None,
) -> Payment:
    plan = next((p for p in plans(conn) if p.id == plan_id), None)
    if plan is None or plan.price_ugx is None:
        raise NotForSale(plan_id)
    # The price, length and allowances are copied from the plan as it is on
    # sale now. The database checks they match, and never lets them change.
    row = conn.execute(
        f"""
        insert into public.payments (user_id, plan_id, days, amount_ugx, email,
          phone, plan_name, max_devices, max_streams)
        values (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        returning {PAYMENT_COLUMNS}
        """,
        (
            user_id,
            plan.id,
            plan.days,
            plan.price_ugx,
            email,
            phone,
            plan.display_name,
            plan.max_devices,
            plan.max_streams,
        ),
    ).fetchone()
    return Payment(*row)


def reusable_checkout(
    conn: psycopg.Connection, plan_id: str, now: datetime
) -> Payment | None:
    """The viewer's own pending payment for this plan, at today's price,
    started in the last few minutes: a retried checkout reuses it."""
    plan = next((p for p in plans(conn) if p.id == plan_id), None)
    if plan is None:
        return None
    row = conn.execute(
        f"""
        select {PAYMENT_COLUMNS} from public.payments
        where plan_id = %s and amount_ugx = %s and state = 'pending'
          and redirect_url is not null and created_at > %s
        order by created_at desc limit 1
        """,
        (plan_id, plan.price_ugx, now - REUSE_CHECKOUT_FOR),
    ).fetchone()
    return Payment(*row) if row else None


def sent_to_pesapal(
    conn: psycopg.Connection,
    payment_id: UUID,
    tracking_id: str,
    redirect_url: str | None = None,
):
    conn.execute(
        """
        update public.payments
        set state = 'pending', tracking_id = %s, redirect_url = %s,
          updated_at = now()
        where id = %s and state = 'started'
        """,
        (tracking_id, redirect_url, payment_id),
    )


def refused_by_pesapal(conn: psycopg.Connection, payment_id: UUID, reason: str):
    conn.execute(
        """
        update public.payments
        set state = 'abandoned', reason = %s, updated_at = now()
        where id = %s and state = 'started'
        """,
        (reason[:300], payment_id),
    )


def get_payment(conn: psycopg.Connection, payment_id: UUID) -> Payment | None:
    row = conn.execute(
        f"select {PAYMENT_COLUMNS} from public.payments where id = %s",
        (payment_id,),
    ).fetchone()
    return Payment(*row) if row else None


def recent_payments(conn: psycopg.Connection, limit: int = 20) -> list[Payment]:
    """The viewer's own payments, newest first."""
    rows = conn.execute(
        f"""
        select {PAYMENT_COLUMNS} from public.payments
        order by created_at desc limit %s
        """,
        (limit,),
    ).fetchall()
    return [Payment(*row) for row in rows]


def open_payments(conn: psycopg.Connection, now: datetime, limit: int = 3):
    """The viewer's own payments still worth asking Pesapal about."""
    rows = conn.execute(
        f"""
        select {PAYMENT_COLUMNS} from public.payments
        where state = any(%s) and tracking_id is not null and created_at > %s
        order by created_at desc limit %s
        """,
        (list(OPEN), now - GIVE_UP_AFTER, limit),
    ).fetchall()
    return [Payment(*row) for row in rows]


def owner_of(conn: psycopg.Connection, tracking_id: str) -> UUID | None:
    """Whose payment this tracking ID is. Run in Database.anonymous: the
    database shows only the payment with this exact tracking ID."""
    conn.execute("select set_config('app.tracking_id', %s, true)", (tracking_id,))
    row = conn.execute(
        "select user_id from public.payments where tracking_id = %s", (tracking_id,)
    ).fetchone()
    conn.execute("select set_config('app.tracking_id', '', true)")
    return row[0] if row else None


# --- Pesapal's answer --------------------------------------------------------


def _matches(payment: Payment, status: Status) -> str | None:
    """Why a COMPLETED status can't be trusted for this payment, if so."""
    if status.merchant_reference != str(payment.id):
        return "Pesapal's reference isn't this payment's"
    if (status.currency or "").upper() != CURRENCY:
        return f"paid in {status.currency or 'an unknown currency'}, not {CURRENCY}"
    if status.amount is None or round(status.amount) != payment.amount_ugx:
        return f"paid {status.amount}, not {payment.amount_ugx}"
    if abs(status.amount - payment.amount_ugx) > 0.001:
        return f"paid {status.amount}, not exactly {payment.amount_ugx}"
    return None


def apply_status(
    conn: psycopg.Connection, payment_id: UUID, status: Status, now: datetime
) -> str:
    """Records Pesapal's status of one payment, in the viewer's transaction.
    Answers the payment's state afterwards. Seeing the same status again
    changes nothing, so a notification and the app checking together make
    one pass: the payment's row is locked, and a pass is unique per
    payment."""
    row = conn.execute(
        f"select {PAYMENT_COLUMNS} from public.payments where id = %s for update",
        (payment_id,),
    ).fetchone()
    if row is None:
        raise LookupError(payment_id)
    payment = Payment(*row)
    details = (status.payment_method, status.confirmation_code)

    if status.code == pesapal.COMPLETED:
        if payment.state in ("completed", "reversed", "abandoned"):
            return payment.state
        problem = _matches(payment, status)
        if problem:
            logger.warning("payment %s not accepted: %s", payment.id, problem)
            audit.event(
                "payment.rejected", payment_id=payment.id, user_id=payment.user_id
            )
            conn.execute(
                """
                update public.payments set state = 'failed', reason = %s,
                  updated_at = now() where id = %s
                """,
                (f"Not accepted: {problem}"[:300], payment.id),
            )
            return "failed"
        conn.execute(
            """
            update public.payments set state = 'completed', completed_at = %s,
              payment_method = %s, confirmation_code = %s, reason = null,
              updated_at = now()
            where id = %s
            """,
            (now, *details, payment.id),
        )
        made = _make_pass(conn, payment, now)
        logger.info("payment %s completed: a %s pass", payment.id, payment.plan_id)
        audit.event(
            "payment.completed",
            payment_id=payment.id,
            user_id=payment.user_id,
            plan_id=payment.plan_id,
            amount_ugx=payment.amount_ugx,
            pass_starts_at=made.starts_at if made else None,
        )
        return "completed"

    if status.code == pesapal.REVERSED:
        if payment.state == "reversed":
            return "reversed"
        conn.execute(
            "update public.payments set state = 'reversed', updated_at = now() "
            "where id = %s",
            (payment.id,),
        )
        revoked = conn.execute(
            """
            update public.passes set revoked_at = %s
            where payment_id = %s and revoked_at is null
            returning id
            """,
            (now, payment.id),
        ).fetchall()
        if revoked:
            _end_sessions_of_passes(conn, [r[0] for r in revoked], now)
            _reschedule(conn, payment.user_id, now)
        logger.info("payment %s reversed: its pass has ended", payment.id)
        audit.event("payment.reversed", payment_id=payment.id, user_id=payment.user_id)
        return "reversed"

    if payment.state not in OPEN:
        return payment.state
    if now - payment.created_at > GIVE_UP_AFTER:
        conn.execute(
            """
            update public.payments set state = 'abandoned', updated_at = now(),
              reason = coalesce(reason, 'Not paid within 24 hours')
            where id = %s
            """,
            (payment.id,),
        )
        audit.event("payment.abandoned", payment_id=payment.id, user_id=payment.user_id)
        return "abandoned"
    if status.code == pesapal.FAILED:
        conn.execute(
            """
            update public.payments set state = 'failed', updated_at = now(),
              payment_method = coalesce(%s, payment_method),
              reason = %s
            where id = %s
            """,
            (status.payment_method, (status.description or "Failed")[:300], payment.id),
        )
        if payment.state != "failed":
            audit.event(
                "payment.failed", payment_id=payment.id, user_id=payment.user_id
            )
        return "failed"
    # INVALID, or anything else: not paid yet.
    return payment.state


def _lock_passes(conn: psycopg.Connection, user_id: UUID) -> None:
    # One viewer's passes are made and moved one transaction at a time, so
    # two completions never both start from the same end.
    conn.execute(
        "select pg_advisory_xact_lock(hashtextextended(%s, %s))",
        (str(user_id), _PASS_LOCK),
    )


def _make_pass(
    conn: psycopg.Connection, payment: Payment, now: datetime
) -> Entitlement | None:
    _lock_passes(conn, payment.user_id)
    (last_end,) = conn.execute(
        """
        select max(ends_at) from public.passes
        where user_id = %s and revoked_at is null and ends_at > %s
        """,
        (payment.user_id, now),
    ).fetchone()
    starts = max(now, last_end) if last_end else now
    row = conn.execute(
        """
        insert into public.passes (user_id, payment_id, starts_at, ends_at,
          plan_id, max_devices, max_streams)
        values (%s, %s, %s, %s::timestamptz + make_interval(days => %s), %s, %s, %s)
        on conflict (payment_id) do nothing
        returning id, starts_at, ends_at
        """,
        (
            payment.user_id,
            payment.id,
            starts,
            starts,
            payment.days,
            payment.plan_id,
            payment.max_devices,
            payment.max_streams,
        ),
    ).fetchone()
    if row is None:
        return None
    return Entitlement(
        id=row[0],
        payment_id=payment.id,
        plan_id=payment.plan_id,
        plan_name=payment.plan_name,
        starts_at=row[1],
        ends_at=row[2],
        max_devices=payment.max_devices,
        max_streams=payment.max_streams,
    )


def _reschedule(conn: psycopg.Connection, user_id: UUID, now: datetime) -> None:
    """After a reversal, the passes still to come move up, in the order they
    were queued, so no paid time is left behind a gap. A pass already
    running never moves."""
    _lock_passes(conn, user_id)
    rows = conn.execute(
        """
        select id, starts_at, ends_at from public.passes
        where user_id = %s and revoked_at is null and ends_at > %s
        order by starts_at, created_at
        """,
        (user_id, now),
    ).fetchall()
    cursor = now
    for pass_id, starts, ends in rows:
        if starts <= now:
            cursor = max(cursor, ends)
            continue
        if starts > cursor:
            length = ends - starts
            conn.execute(
                "update public.passes set starts_at = %s, ends_at = %s where id = %s",
                (cursor, cursor + length, pass_id),
            )
            ends = cursor + length
        cursor = ends


def _end_sessions_of_passes(
    conn: psycopg.Connection, pass_ids: list[UUID], now: datetime
) -> None:
    conn.execute(
        """
        update public.playback_sessions
        set ended_at = %s, end_reason = 'pass_ended'
        where pass_id = any(%s) and ended_at is null
        """,
        (now, pass_ids),
    )


# --- Asking Pesapal ----------------------------------------------------------


def refresh(
    db,
    client: PesapalClient,
    user_id: UUID,
    payment: Payment,
    now: datetime,
    *,
    even_if_completed: bool = False,
) -> str:
    """Asks Pesapal about one of the viewer's payments, outside any
    transaction, then records the answer. Answers the state afterwards.
    Raises PesapalUnavailable when Pesapal can't be asked."""
    settled = ("reversed", "abandoned") + (() if even_if_completed else ("completed",))
    if payment.state in settled or payment.tracking_id is None:
        return payment.state
    try:
        status = client.status(payment.tracking_id)
    except pesapal.PesapalUnavailable:
        raise
    except PesapalError as error:
        # Pesapal may refuse to report a payment nobody has paid yet.
        logger.info("payment %s not reported yet: %s", payment.id, error)
        status = Status(None, "", None, None, None, None, None)
    with db.as_user(user_id) as conn:
        return apply_status(conn, payment.id, status, now)


# --- Who may watch -----------------------------------------------------------


def entitlements(
    conn: psycopg.Connection, user_id: UUID, now: datetime
) -> list[Entitlement]:
    """The viewer's passes running now or still to come, in order."""
    rows = conn.execute(
        f"""
        select {ENTITLEMENT_COLUMNS}
        from public.passes s join public.payments p on p.id = s.payment_id
        where s.user_id = %s and s.revoked_at is null and s.ends_at > %s
        order by s.starts_at
        """,
        (user_id, now),
    ).fetchall()
    return [Entitlement(*row) for row in rows]


def current_entitlement(
    conn: psycopg.Connection, user_id: UUID, now: datetime
) -> Entitlement | None:
    """The pass running now, which decides the device and stream limits."""
    return next(
        (e for e in entitlements(conn, user_id, now) if e.starts_at <= now), None
    )


def history(conn: psycopg.Connection, user_id: UUID, limit: int = 20):
    """Every pass the viewer has had, newest first, with whether it was
    revoked."""
    rows = conn.execute(
        f"""
        select {ENTITLEMENT_COLUMNS}, s.revoked_at
        from public.passes s join public.payments p on p.id = s.payment_id
        where s.user_id = %s order by s.starts_at desc limit %s
        """,
        (user_id, limit),
    ).fetchall()
    return [(Entitlement(*row[:8]), row[8]) for row in rows]


def pass_status(conn: psycopg.Connection, user_id: UUID, now: datetime) -> PassStatus:
    found = entitlements(conn, user_id, now)
    current = next((e.ends_at for e in found if e.starts_at <= now), None)
    return PassStatus(
        current_ends_at=current,
        ends_at=max(e.ends_at for e in found) if found and current else None,
    )


def is_admin(conn: psycopg.Connection, user_id: UUID) -> bool:
    """Under the API's role the database shows only the viewer's own row."""
    return (
        conn.execute(
            "select 1 from public.admins where user_id = %s", (user_id,)
        ).fetchone()
        is not None
    )
