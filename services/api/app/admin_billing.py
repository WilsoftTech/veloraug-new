"""Admins' view of subscriptions, Milestone 10: metrics, payments,
subscribers, one subscriber's passes and devices, and price history.

Every route needs an admin, checked on each request, and connects as
veloraug_editor. That role can read payments, passes, devices and sessions,
and can remove a device or end a session. The one change it can make to a
payment is to mark a completed one refunded, which ends its pass: the
database refuses anything else, so history can't be rewritten from here.
Contact details are masked: enough to recognise a customer, not to copy.
"""

import csv
import io
import logging
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Annotated, Literal
from uuid import UUID

import psycopg
from fastapi import APIRouter, HTTPException, Query, Request, Response, status
from pydantic import BaseModel, Field, StringConstraints

from app import app_settings, audit, devices, passes
from app.admin import AdminUser, EditorDatabase
from app.pesapal import PesapalUnavailable
from app.viewer_routes import AppDatabase

logger = logging.getLogger("veloraug.admin")
router = APIRouter(prefix="/api/v1/admin/billing", tags=["admin"])

State = Literal[
    "started", "pending", "completed", "failed", "reversed", "abandoned", "refunded"
]


def _now() -> datetime:
    return datetime.now(UTC)


# Days, such as "today", are Kampala's.
ZONE = "Africa/Kampala"
# Stale payments settled each time an admin opens Payments or Overview.
SETTLE_BATCH = 20
# A pass ending within this many days, with nothing after it, is ending soon.
ENDING_SOON_DAYS = 3
CSV_MOST = 10_000


def _timeout(request: Request, conn: psycopg.Connection) -> timedelta:
    """The timeout admins set in Settings, or the server's."""
    return app_settings.payment_timeout(
        app_settings.safe_read(conn),
        request.app.state.settings.payment_timeout_minutes,
    )


def settle_stale_payments(
    request: Request, app_db, editor_db, admin_id: UUID, now: datetime
) -> passes.Settled | None:
    """Settles payments left started or pending past the timeout, a batch
    at a time, as the admin looks. See passes.settle_stale."""
    with editor_db.as_user(admin_id) as conn:
        after = _timeout(request, conn)
        stale = passes.stale_payments(conn, now, after, SETTLE_BATCH)
    if not stale:
        return None
    settled = passes.settle_stale(app_db, request.app.state.pesapal, stale, now, after)
    if settled.checked:
        audit.event("admin.payments_settled", admin_id=admin_id, count=settled.checked)
        logger.info(
            "Settled %s stale payments: %s",
            settled.checked,
            ", ".join(sorted(set(settled.states.values()))),
        )
    return settled


def mask_email(email: str | None) -> str | None:
    if not email or "@" not in email:
        return None
    name, _, domain = email.partition("@")
    return f"{name[:1]}***@{domain}"


def mask_phone(phone: str | None) -> str | None:
    if not phone:
        return None
    return f"{phone[:4]}***{phone[-3:]}" if len(phone) > 7 else "***"


# --- Shapes ------------------------------------------------------------------


class PlanCount(BaseModel):
    plan_id: str
    plan_name: str
    subscribers: int


class DayRevenue(BaseModel):
    day: date
    revenue_ugx: int
    completed: int


class Metrics(BaseModel):
    active_subscribers: int
    by_plan: list[PlanCount]
    revenue_today_ugx: int = 0
    revenue_7_days_ugx: int = 0
    revenue_30_days_ugx: int
    completed_30_days: int
    failed_30_days: int
    reversed_30_days: int
    refunded_30_days: int
    abandoned_30_days: int
    pending_now: int
    active_devices: int
    live_sessions: int
    # Completed of those settled in the last 30 days; None with none.
    success_rate_30_days: float | None = None
    # Passes ending within ENDING_SOON_DAYS with nothing after them.
    ending_soon: int = 0
    granted_30_days: int = 0
    # The last 30 days in Kampala, oldest first, every day listed.
    daily: list[DayRevenue] = []
    payment_timeout_minutes: int = 60


class AdminPayment(BaseModel):
    id: UUID
    user_id: UUID
    plan_id: str
    plan_name: str
    amount_ugx: int
    state: str
    created_at: datetime
    completed_at: datetime | None
    payment_method: str | None
    provider_reference: str | None
    tracking_id: str | None
    reason: str | None
    contact: str | None


class Subscriber(BaseModel):
    user_id: UUID
    plan_id: str
    plan_name: str
    starts_at: datetime
    ends_at: datetime
    max_devices: int
    active_devices: int
    contact: str | None


class AdminPass(BaseModel):
    id: UUID
    # One or the other: a payment's pass, or an admin's grant.
    payment_id: UUID | None
    plan_id: str
    plan_name: str
    starts_at: datetime
    ends_at: datetime
    max_devices: int
    max_streams: int
    revoked_at: datetime | None
    grant_id: UUID | None = None


class AdminGrant(BaseModel):
    id: UUID
    plan_id: str
    plan_name: str
    days: int
    reason: str
    granted_by: UUID
    granted_by_email: str | None
    created_at: datetime


class AdminDevice(BaseModel):
    id: UUID
    label: str
    platform: str
    registered_at: datetime
    last_active_at: datetime
    revoked_at: datetime | None
    revoked_by: str | None


class AdminSession(BaseModel):
    id: UUID
    device_id: UUID
    started_at: datetime
    last_seen_at: datetime


class SubscriberDetail(BaseModel):
    user_id: UUID
    passes: list[AdminPass]
    payments: list[AdminPayment]
    grants: list[AdminGrant] = []
    devices: list[AdminDevice]
    live_sessions: list[AdminSession]


class PlanChange(BaseModel):
    plan_id: str
    changed_by: UUID | None
    changed_at: datetime
    old_price_ugx: int | None
    new_price_ugx: int | None
    old_for_sale: bool
    new_for_sale: bool
    old_featured: bool
    new_featured: bool


# --- Queries -----------------------------------------------------------------

PAYMENT_COLUMNS = (
    "id, user_id, plan_id, plan_name, amount_ugx, state, created_at, "
    "completed_at, payment_method, confirmation_code, tracking_id, reason, "
    "email, phone"
)


def _payment(row) -> AdminPayment:
    (*fields, email, phone) = row
    names = list(AdminPayment.model_fields)[:-1]
    return AdminPayment(
        **dict(zip(names, fields, strict=True)),
        contact=mask_email(email) or mask_phone(phone),
    )


@dataclass(frozen=True)
class _Counts:
    states: dict[str, int]
    revenue: int


def _counts(conn: psycopg.Connection, since: datetime) -> _Counts:
    rows = conn.execute(
        """
        select state, count(*),
          coalesce(sum(amount_ugx) filter (where state = 'completed'), 0)
        from public.payments where created_at > %s group by state
        """,
        (since,),
    ).fetchall()
    return _Counts(
        states={state: count for state, count, _ in rows},
        revenue=sum(revenue for *_, revenue in rows),
    )


# --- Routes ------------------------------------------------------------------


@router.get("/metrics")
def metrics(
    request: Request, user: AdminUser, db: EditorDatabase, app_db: AppDatabase
) -> Metrics:
    now = _now()
    settle_stale_payments(request, app_db, db, user.user_id, now)
    with db.as_user(user.user_id) as conn:
        timeout = _timeout(request, conn)
        by_plan = conn.execute(
            """
            select s.plan_id, pp.display_name, count(distinct s.user_id)
            from public.passes s join public.pass_plans pp on pp.id = s.plan_id
            where s.revoked_at is null and s.starts_at <= %s and s.ends_at > %s
            group by s.plan_id, pp.display_name, pp.display_order
            order by pp.display_order
            """,
            (now, now),
        ).fetchall()
        (active,) = conn.execute(
            """
            select count(distinct user_id) from public.passes
            where revoked_at is null and starts_at <= %s and ends_at > %s
            """,
            (now, now),
        ).fetchone()
        counts = _counts(conn, now - timedelta(days=30))
        # Every payment still open: stale ones were settled above.
        (pending,) = conn.execute(
            "select count(*) from public.payments where state in ('started', 'pending')"
        ).fetchone()
        today, week = conn.execute(
            f"""
            select
              coalesce(sum(amount_ugx) filter (where (completed_at at time zone
                '{ZONE}')::date = (%(now)s at time zone '{ZONE}')::date), 0),
              coalesce(sum(amount_ugx) filter (where completed_at
                > %(now)s - interval '7 days'), 0)
            from public.payments
            where state = 'completed' and completed_at > %(now)s - interval '8 days'
            """,
            {"now": now},
        ).fetchone()
        daily = conn.execute(
            f"""
            select d::date,
              coalesce(sum(p.amount_ugx), 0)::int, count(p.id)::int
            from generate_series(
              (%(now)s at time zone '{ZONE}')::date - 29,
              (%(now)s at time zone '{ZONE}')::date, interval '1 day') d
            left join public.payments p on p.state = 'completed'
              and (p.completed_at at time zone '{ZONE}')::date = d::date
            group by d order by d
            """,
            {"now": now},
        ).fetchall()
        (ending_soon,) = conn.execute(
            """
            select count(distinct s.user_id) from public.passes s
            where s.revoked_at is null and s.starts_at <= %(now)s
              and s.ends_at > %(now)s and s.ends_at <= %(soon)s
              and not exists (
                select from public.passes later
                where later.user_id = s.user_id and later.revoked_at is null
                  and later.starts_at >= s.ends_at)
            """,
            {"now": now, "soon": now + timedelta(days=ENDING_SOON_DAYS)},
        ).fetchone()
        (granted,) = conn.execute(
            "select count(*) from public.pass_grants where created_at > %s",
            (now - timedelta(days=30),),
        ).fetchone()
        (device_count,) = conn.execute(
            "select count(*) from public.devices where revoked_at is null"
        ).fetchone()
        (session_count,) = conn.execute(
            "select count(*) from public.playback_sessions "
            "where ended_at is null and last_seen_at > %s",
            (now - devices.IDLE,),
        ).fetchone()
    settled_count = sum(
        counts.states.get(s, 0)
        for s in ("completed", "failed", "abandoned", "reversed", "refunded")
    )
    paid = sum(counts.states.get(s, 0) for s in ("completed", "refunded"))
    return Metrics(
        revenue_today_ugx=today,
        revenue_7_days_ugx=week,
        success_rate_30_days=round(paid / settled_count, 3) if settled_count else None,
        ending_soon=ending_soon,
        granted_30_days=granted,
        daily=[DayRevenue(day=d, revenue_ugx=r, completed=c) for d, r, c in daily],
        payment_timeout_minutes=int(timeout.total_seconds() // 60),
        active_subscribers=active,
        by_plan=[
            PlanCount(plan_id=a, plan_name=b, subscribers=c) for a, b, c in by_plan
        ],
        revenue_30_days_ugx=counts.revenue,
        completed_30_days=counts.states.get("completed", 0),
        failed_30_days=counts.states.get("failed", 0),
        reversed_30_days=counts.states.get("reversed", 0),
        refunded_30_days=counts.states.get("refunded", 0),
        abandoned_30_days=counts.states.get("abandoned", 0),
        pending_now=pending,
        active_devices=device_count,
        live_sessions=session_count,
    )


@router.get("/payments")
def payments(
    user: AdminUser,
    db: EditorDatabase,
    state: State | None = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> list[AdminPayment]:
    """Payments, newest first: all, or in one state, such as failed or
    reversed. Read only."""
    with db.as_user(user.user_id) as conn:
        rows = conn.execute(
            f"""
            select {PAYMENT_COLUMNS} from public.payments
            where %s::text is null or state = %s
            order by created_at desc limit %s
            """,
            (state, state, limit),
        ).fetchall()
    return [_payment(row) for row in rows]


@router.post(
    "/payments/{payment_id}/refund",
    responses={
        404: {"description": "No such payment."},
        409: {"description": "Only a completed payment can be marked refunded."},
    },
)
def refund_payment(
    payment_id: UUID, user: AdminUser, db: EditorDatabase
) -> AdminPayment:
    """Marks a completed payment refunded in full, once it has been refunded
    on Pesapal, which never tells VeloraUG. Its pass ends at once and what
    it was playing stops. It can't be undone."""
    with db.as_user(user.user_id) as conn:
        try:
            passes.refund(conn, payment_id, user.user_id, _now())
        except LookupError:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND, "There's no such payment."
            ) from None
        except passes.NotRefundable as error:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "Only a completed payment can be marked refunded. "
                f"This one is {error}.",
            ) from None
        row = conn.execute(
            f"select {PAYMENT_COLUMNS} from public.payments where id = %s",
            (payment_id,),
        ).fetchone()
    return _payment(row)


@router.get("/subscribers")
def subscribers(
    user: AdminUser,
    db: EditorDatabase,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
    q: Annotated[str | None, Query(max_length=120)] = None,
    ending_within_days: Annotated[int | None, Query(ge=1, le=60)] = None,
) -> list[Subscriber]:
    """Accounts with a pass running now, ending soonest first. Searched by
    account ID, email or phone; or only those ending within some days, with
    nothing after it."""
    now = _now()
    where, params = [], {"now": now, "limit": limit}
    if q and q.strip():
        where.append(
            "(s.user_id::text = %(q)s or lower(p.email) like %(like)s "
            "or p.phone like %(digits)s)"
        )
        text = q.strip().lower()
        params |= {
            "q": text,
            "like": f"%{text}%",
            "digits": "%" + "".join(c for c in text if c.isdigit()) + "%"
            if any(c.isdigit() for c in text)
            else "-",
        }
    if ending_within_days:
        where.append(
            "s.ends_at <= %(soon)s and not exists (select from public.passes later "
            "where later.user_id = s.user_id and later.revoked_at is null "
            "and later.starts_at >= s.ends_at)"
        )
        params["soon"] = now + timedelta(days=ending_within_days)
    with db.as_user(user.user_id) as conn:
        rows = conn.execute(
            f"""
            select s.user_id, s.plan_id, coalesce(p.plan_name, pp.display_name),
              s.starts_at, s.ends_at,
              s.max_devices,
              (select count(*) from public.devices d
               where d.user_id = s.user_id and d.revoked_at is null),
              p.email, p.phone
            from public.passes s left join public.payments p on p.id = s.payment_id
        left join public.pass_plans pp on pp.id = s.plan_id
            where s.revoked_at is null and s.starts_at <= %(now)s
              and s.ends_at > %(now)s {"".join(" and " + w for w in where)}
            order by s.ends_at limit %(limit)s
            """,
            params,
        ).fetchall()
    return [
        Subscriber(
            user_id=r[0],
            plan_id=r[1],
            plan_name=r[2],
            starts_at=r[3],
            ends_at=r[4],
            max_devices=r[5],
            active_devices=r[6],
            contact=mask_email(r[7]) or mask_phone(r[8]),
        )
        for r in rows
    ]


@router.get("/users/{user_id}")
def subscriber(user_id: UUID, user: AdminUser, db: EditorDatabase) -> SubscriberDetail:
    """One account's passes, payments, devices and what is playing now."""
    now = _now()
    with db.as_user(user.user_id) as conn:
        pass_rows = conn.execute(
            """
            select s.id, s.payment_id, s.plan_id,
              coalesce(p.plan_name, pp.display_name), s.starts_at,
              s.ends_at, s.max_devices, s.max_streams, s.revoked_at, s.grant_id
            from public.passes s left join public.payments p on p.id = s.payment_id
        left join public.pass_plans pp on pp.id = s.plan_id
            where s.user_id = %s order by s.starts_at desc limit 50
            """,
            (user_id,),
        ).fetchall()
        payment_rows = conn.execute(
            f"select {PAYMENT_COLUMNS} from public.payments where user_id = %s "
            "order by created_at desc limit 50",
            (user_id,),
        ).fetchall()
        device_rows = conn.execute(
            """
            select id, label, platform, registered_at, last_active_at, revoked_at,
              revoked_by
            from public.devices where user_id = %s order by registered_at desc
            limit 50
            """,
            (user_id,),
        ).fetchall()
        grant_rows = conn.execute(
            """
            select g.id, g.plan_id, pp.display_name, g.days, g.reason,
              g.granted_by, a.email, g.created_at
            from public.pass_grants g
            join public.pass_plans pp on pp.id = g.plan_id
            left join public.admins a on a.user_id = g.granted_by
            where g.user_id = %s order by g.created_at desc limit 50
            """,
            (user_id,),
        ).fetchall()
        session_rows = conn.execute(
            """
            select id, device_id, started_at, last_seen_at
            from public.playback_sessions
            where user_id = %s and ended_at is null and last_seen_at > %s
            """,
            (user_id, now - devices.IDLE),
        ).fetchall()
    logger.info("Admin %s looked at account %s's billing", user.user_id, user_id)
    names = list(AdminPass.model_fields)
    return SubscriberDetail(
        user_id=user_id,
        passes=[AdminPass(**dict(zip(names, r, strict=True))) for r in pass_rows],
        payments=[_payment(r) for r in payment_rows],
        grants=[
            AdminGrant(**dict(zip(AdminGrant.model_fields, r, strict=True)))
            for r in grant_rows
        ],
        devices=[
            AdminDevice(**dict(zip(AdminDevice.model_fields, r, strict=True)))
            for r in device_rows
        ],
        live_sessions=[
            AdminSession(**dict(zip(AdminSession.model_fields, r, strict=True)))
            for r in session_rows
        ],
    )


@router.delete(
    "/users/{user_id}/devices/{device_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={404: {"description": "No such active device."}},
)
def remove_device(
    user_id: UUID, device_id: UUID, user: AdminUser, db: EditorDatabase
) -> Response:
    """Removes one of an account's devices, for example at the account
    holder's request. What it was playing stops within a minute."""
    with db.as_user(user.user_id) as conn:
        removed = devices.revoke(conn, user_id, device_id, _now(), by="admin")
    if not removed:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "There's no such device.")
    audit.event("admin.device_removed", admin_id=user.user_id, device_id=device_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/plan-changes")
def plan_changes(
    user: AdminUser,
    db: EditorDatabase,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> list[PlanChange]:
    """Every change to a plan's price, sale or featured flag, newest first,
    as the database recorded it."""
    with db.as_user(user.user_id) as conn:
        rows = conn.execute(
            """
            select plan_id, changed_by, changed_at, old_price_ugx, new_price_ugx,
              old_for_sale, new_for_sale, old_featured, new_featured
            from public.plan_changes order by changed_at desc, id desc limit %s
            """,
            (limit,),
        ).fetchall()
    return [
        PlanChange(**dict(zip(PlanChange.model_fields, r, strict=True))) for r in rows
    ]


# --- Transactions, Step 13H ------------------------------------------------------


class TransactionPage(BaseModel):
    payments: list[AdminPayment]
    total: int


def _transaction_filters(
    state: str | None,
    plan: str | None,
    since: date | None,
    until: date | None,
    q: str | None,
) -> tuple[str, dict]:
    where = ["true"]
    params: dict = {}
    if state:
        where.append("state = %(state)s")
        params["state"] = state
    if plan:
        where.append("plan_id = %(plan)s")
        params["plan"] = plan
    if since:
        where.append(f"(created_at at time zone '{ZONE}')::date >= %(since)s")
        params["since"] = since
    if until:
        where.append(f"(created_at at time zone '{ZONE}')::date <= %(until)s")
        params["until"] = until
    if q and q.strip():
        text = q.strip().lower()
        digits = "".join(c for c in text if c.isdigit())
        # A local number, 0772…, is stored as +256772….
        if digits.startswith("0"):
            digits = digits[1:]
        where.append(
            "(id::text like %(start)s or user_id::text like %(start)s "
            "or lower(tracking_id) = %(text)s or lower(confirmation_code) = %(text)s "
            "or lower(email) like %(like)s"
            + (" or phone like %(digits)s" if len(digits) >= 4 else "")
            + ")"
        )
        params |= {
            "text": text,
            "start": f"{text}%",
            "like": f"%{text}%",
            "digits": f"%{digits}%",
        }
    return " and ".join(where), params


Since = Annotated[date | None, Query()]


@router.get("/transactions")
def transactions(
    request: Request,
    user: AdminUser,
    db: EditorDatabase,
    app_db: AppDatabase,
    state: State | None = None,
    plan: Annotated[str | None, Query(pattern=r"^[a-z_]{2,20}$")] = None,
    since: Since = None,
    until: Since = None,
    q: Annotated[str | None, Query(max_length=120)] = None,
    offset: Annotated[int, Query(ge=0, le=100_000)] = 0,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> TransactionPage:
    """Payments, newest first, filtered by state, plan and Kampala dates,
    and searched by payment, account, Pesapal tracking ID or confirmation
    code, email or phone. Stale payments are settled first."""
    settle_stale_payments(request, app_db, db, user.user_id, _now())
    where, params = _transaction_filters(state, plan, since, until, q)
    with db.as_user(user.user_id) as conn:
        rows = conn.execute(
            f"""
            select {PAYMENT_COLUMNS}, count(*) over () from public.payments
            where {where} order by created_at desc
            limit %(limit)s offset %(offset)s
            """,
            {**params, "limit": limit, "offset": offset},
        ).fetchall()
        if rows:
            total = rows[0][-1]
        else:
            (total,) = conn.execute(
                f"select count(*) from public.payments where {where}", params
            ).fetchone()
    return TransactionPage(payments=[_payment(r[:-1]) for r in rows], total=total)


def _cell(value: object) -> str:
    """One CSV cell. Text a spreadsheet would run as a formula is quoted."""
    text = "" if value is None else str(value)
    return "'" + text if text[:1] in ("=", "+", "-", "@", "\t", "\r") else text


@router.get("/transactions.csv")
def transactions_csv(
    user: AdminUser,
    db: EditorDatabase,
    state: State | None = None,
    plan: Annotated[str | None, Query(pattern=r"^[a-z_]{2,20}$")] = None,
    since: Since = None,
    until: Since = None,
    q: Annotated[str | None, Query(max_length=120)] = None,
) -> Response:
    """The same payments as a spreadsheet, up to 10,000, contacts masked."""
    where, params = _transaction_filters(state, plan, since, until, q)
    with db.as_user(user.user_id) as conn:
        rows = conn.execute(
            f"""
            select {PAYMENT_COLUMNS} from public.payments where {where}
            order by created_at desc limit %(most)s
            """,
            {**params, "most": CSV_MOST},
        ).fetchall()
    out = io.StringIO()
    writer = csv.writer(out)
    writer.writerow(
        [
            "created_at",
            "state",
            "plan",
            "amount_ugx",
            "completed_at",
            "payment_method",
            "confirmation_code",
            "tracking_id",
            "payment_id",
            "account_id",
            "contact",
            "reason",
        ]
    )
    for row in rows:
        p = _payment(row)
        writer.writerow(
            _cell(v)
            for v in (
                p.created_at.isoformat(),
                "expired" if p.state == "abandoned" else p.state,
                p.plan_name,
                p.amount_ugx,
                p.completed_at.isoformat() if p.completed_at else "",
                p.payment_method,
                p.provider_reference,
                p.tracking_id,
                p.id,
                p.user_id,
                p.contact,
                p.reason,
            )
        )
    audit.event("admin.payments_exported", admin_id=user.user_id, count=len(rows))
    name = f"veloraug-payments-{_now():%Y-%m-%d}.csv"
    return Response(
        out.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{name}"'},
    )


class TimelineStep(BaseModel):
    # started, sent, completed, failed, expired, reversed, refunded.
    step: str
    # None when the time wasn't recorded, such as being sent to Pesapal.
    at: datetime | None


class PaymentDetail(BaseModel):
    payment: AdminPayment
    timeline: list[TimelineStep]
    pass_: AdminPass | None = Field(default=None, alias="pass")
    refunded_at: datetime | None
    refunded_by: UUID | None

    model_config = {"populate_by_name": True}


def _detail(conn: psycopg.Connection, payment_id: UUID) -> PaymentDetail:
    row = conn.execute(
        f"select {PAYMENT_COLUMNS}, updated_at, refunded_at, refunded_by "
        "from public.payments where id = %s",
        (payment_id,),
    ).fetchone()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "There's no such payment.")
    *fields, updated_at, refunded_at, refunded_by = row
    payment = _payment(fields)
    timeline = [TimelineStep(step="started", at=payment.created_at)]
    if payment.tracking_id:
        timeline.append(TimelineStep(step="sent", at=None))
    if payment.completed_at:
        timeline.append(TimelineStep(step="completed", at=payment.completed_at))
    ended = {"failed": "failed", "abandoned": "expired", "reversed": "reversed"}
    if payment.state in ended:
        timeline.append(TimelineStep(step=ended[payment.state], at=updated_at))
    if refunded_at:
        timeline.append(TimelineStep(step="refunded", at=refunded_at))
    pass_row = conn.execute(
        """
        select s.id, s.payment_id, s.plan_id, %s, s.starts_at, s.ends_at,
          s.max_devices, s.max_streams, s.revoked_at, s.grant_id
        from public.passes s where s.payment_id = %s
        """,
        (payment.plan_name, payment_id),
    ).fetchone()
    return PaymentDetail(
        payment=payment,
        timeline=timeline,
        pass_=AdminPass(**dict(zip(AdminPass.model_fields, pass_row, strict=True)))
        if pass_row
        else None,
        refunded_at=refunded_at,
        refunded_by=refunded_by,
    )


@router.get("/payments/{payment_id}", response_model_by_alias=True)
def payment_detail(
    payment_id: UUID, user: AdminUser, db: EditorDatabase
) -> PaymentDetail:
    """One payment: what is known of it, step by step, and its pass."""
    with db.as_user(user.user_id) as conn:
        return _detail(conn, payment_id)


@router.post(
    "/payments/{payment_id}/recheck",
    response_model_by_alias=True,
    responses={503: {"description": "Pesapal isn't set up, or isn't answering."}},
)
def recheck_payment(
    payment_id: UUID,
    request: Request,
    user: AdminUser,
    db: EditorDatabase,
    app_db: AppDatabase,
) -> PaymentDetail:
    """Asks Pesapal about one payment now and records its answer. A payment
    given up on that was paid after all is completed, with its pass."""
    client = request.app.state.pesapal
    with db.as_user(user.user_id) as conn:
        after = _timeout(request, conn)
        row = conn.execute(
            "select user_id, tracking_id, state from public.payments where id = %s",
            (payment_id,),
        ).fetchone()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "There's no such payment.")
    owner, tracking_id, state = row
    if tracking_id is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, "This payment never reached Pesapal."
        )
    if client is None:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, "Pesapal isn't set up on this server."
        )
    try:
        answer = client.status(tracking_id)
    except PesapalUnavailable:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Pesapal isn't answering. Try again in a few minutes.",
        ) from None
    except passes.PesapalError:
        answer = passes.NO_ANSWER
    with app_db.as_user(owner) as conn:
        now_state = passes.apply_status(
            conn, payment_id, answer, _now(), give_up_after=after
        )
    audit.event("admin.payment_rechecked", admin_id=user.user_id, payment_id=payment_id)
    logger.info(
        "Admin %s rechecked payment %s: %s -> %s",
        user.user_id,
        payment_id,
        state,
        now_state,
    )
    with db.as_user(user.user_id) as conn:
        return _detail(conn, payment_id)


class GrantIn(BaseModel):
    plan_id: Annotated[str, StringConstraints(pattern=r"^[a-z_]{2,20}$")]
    days: int = Field(ge=1, le=90)
    reason: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=3, max_length=300)
    ]


@router.post(
    "/users/{user_id}/grants",
    status_code=status.HTTP_201_CREATED,
    responses={404: {"description": "No such plan."}},
)
def grant_days(
    user_id: UUID, body: GrantIn, user: AdminUser, db: EditorDatabase
) -> AdminPass:
    """Gives an account free days on a plan, with a reason. They start when
    the account's passes end, or now: so it extends a pass, or starts one.
    Never a payment: revenue is untouched."""
    with db.as_user(user.user_id) as conn:
        try:
            (pass_id,) = conn.execute(
                "select public.grant_pass(%s, %s, %s, %s, %s)",
                (user_id, body.plan_id, body.days, body.reason, user.user_id),
            ).fetchone()
        except psycopg.errors.NoDataFound:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND, "There's no such plan."
            ) from None
        row = conn.execute(
            """
            select s.id, s.payment_id, s.plan_id, pp.display_name, s.starts_at,
              s.ends_at, s.max_devices, s.max_streams, s.revoked_at, s.grant_id
            from public.passes s join public.pass_plans pp on pp.id = s.plan_id
            where s.id = %s
            """,
            (pass_id,),
        ).fetchone()
    audit.event(
        "admin.pass_granted",
        admin_id=user.user_id,
        user_id=user_id,
        plan_id=body.plan_id,
        count=body.days,
    )
    logger.info(
        "Admin %s gave account %s %s days of %s",
        user.user_id,
        user_id,
        body.days,
        body.plan_id,
    )
    return AdminPass(**dict(zip(AdminPass.model_fields, row, strict=True)))
