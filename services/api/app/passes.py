"""Passes and their payments, Step 10B. See docs/step-10a-payments-plan.md.

Everything here runs in Database.as_user, so row-level security limits it
to the viewer's own payments and passes. Pesapal's notifications find a
payment's owner with `owner_of`, by the tracking ID alone.

Only `apply_status` turns a payment into a pass, and only on Pesapal's own
status: COMPLETED, for this payment's reference, its exact amount, in UGX.
The database refuses a pass that doesn't match its payment as well.
"""

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

import psycopg

from app import pesapal
from app.pesapal import PesapalClient, PesapalError, Status

logger = logging.getLogger("veloraug.passes")

CURRENCY = "UGX"
# A payment not completed within this long is given up on.
GIVE_UP_AFTER = timedelta(hours=24)
# Payments that can still change when Pesapal is asked. A completed one
# can still be reversed, but only a notification checks it again.
OPEN = ("started", "pending", "failed")
NAMES = {"day": "1 day", "week": "1 week", "month": "1 month"}


class NotForSale(Exception):
    pass


@dataclass(frozen=True)
class Plan:
    id: str
    days: int
    price_ugx: int | None


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


@dataclass(frozen=True)
class PassStatus:
    # The pass running now, if any, and when it ends.
    current_ends_at: datetime | None
    # The end of the last pass bought, if any is still to come.
    ends_at: datetime | None


PAYMENT_COLUMNS = (
    "id, user_id, plan_id, days, amount_ugx, state, tracking_id, email, phone, "
    "created_at"
)


# --- Plans -------------------------------------------------------------------


def plans(conn: psycopg.Connection, *, for_sale_only: bool = True) -> list[Plan]:
    rows = conn.execute(
        "select id, days, price_ugx from public.pass_plans order by days"
    ).fetchall()
    found = [Plan(*row) for row in rows]
    return [p for p in found if p.price_ugx is not None] if for_sale_only else found


def set_price(conn: psycopg.Connection, plan_id: str, price_ugx: int | None) -> Plan:
    row = conn.execute(
        """
        update public.pass_plans set price_ugx = %s, updated_at = now()
        where id = %s returning id, days, price_ugx
        """,
        (price_ugx, plan_id),
    ).fetchone()
    if row is None:
        raise LookupError(plan_id)
    return Plan(*row)


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
    row = conn.execute(
        f"""
        insert into public.payments (user_id, plan_id, days, amount_ugx, email, phone)
        values (%s, %s, %s, %s, %s, %s)
        returning {PAYMENT_COLUMNS}
        """,
        (user_id, plan.id, plan.days, plan.price_ugx, email, phone),
    ).fetchone()
    return Payment(*row)


def sent_to_pesapal(conn: psycopg.Connection, payment_id: UUID, tracking_id: str):
    conn.execute(
        """
        update public.payments
        set state = 'pending', tracking_id = %s, updated_at = now()
        where id = %s and state = 'started'
        """,
        (tracking_id, payment_id),
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
    return None


def apply_status(
    conn: psycopg.Connection, payment_id: UUID, status: Status, now: datetime
) -> str:
    """Records Pesapal's status of one payment, in the viewer's transaction.
    Answers the payment's state afterwards. Seeing the same status again
    changes nothing, so a notification and the app checking together make
    one pass."""
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
        _make_pass(conn, payment, now)
        logger.info("payment %s completed: a %s pass", payment.id, payment.plan_id)
        return "completed"

    if status.code == pesapal.REVERSED:
        if payment.state == "reversed":
            return "reversed"
        conn.execute(
            "update public.payments set state = 'reversed', updated_at = now() "
            "where id = %s",
            (payment.id,),
        )
        conn.execute(
            """
            update public.passes set revoked_at = %s
            where payment_id = %s and revoked_at is null
            """,
            (now, payment.id),
        )
        logger.info("payment %s reversed: its pass has ended", payment.id)
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
        return "failed"
    # INVALID, or anything else: not paid yet.
    return payment.state


def _make_pass(conn: psycopg.Connection, payment: Payment, now: datetime) -> None:
    # One viewer's passes are made one at a time, so two completions never
    # both start from the same end.
    conn.execute(
        "select pg_advisory_xact_lock(hashtextextended(%s, 6))",
        (str(payment.user_id),),
    )
    (last_end,) = conn.execute(
        """
        select max(ends_at) from public.passes
        where user_id = %s and revoked_at is null and ends_at > %s
        """,
        (payment.user_id, now),
    ).fetchone()
    starts = max(now, last_end) if last_end else now
    conn.execute(
        """
        insert into public.passes (user_id, payment_id, starts_at, ends_at)
        values (%s, %s, %s, %s::timestamptz + make_interval(days => %s))
        on conflict (payment_id) do nothing
        """,
        (payment.user_id, payment.id, starts, starts, payment.days),
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


def pass_status(conn: psycopg.Connection, user_id: UUID, now: datetime) -> PassStatus:
    rows = conn.execute(
        """
        select starts_at, ends_at from public.passes
        where user_id = %s and revoked_at is null and ends_at > %s
        order by starts_at
        """,
        (user_id, now),
    ).fetchall()
    current = next((end for start, end in rows if start <= now), None)
    return PassStatus(
        current_ends_at=current,
        ends_at=max(end for _, end in rows) if rows and current else None,
    )


def is_admin(conn: psycopg.Connection, user_id: UUID) -> bool:
    """Under the API's role the database shows only the viewer's own row."""
    return (
        conn.execute(
            "select 1 from public.admins where user_id = %s", (user_id,)
        ).fetchone()
        is not None
    )
