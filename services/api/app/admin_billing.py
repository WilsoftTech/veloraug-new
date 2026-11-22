"""Admins' view of subscriptions, Milestone 10: metrics, payments,
subscribers, one subscriber's passes and devices, and price history.

Every route needs an admin, checked on each request, and connects as
veloraug_editor. That role can read payments, passes, devices and sessions,
and can remove a device or end a session. It can't change a payment or a
pass: the database refuses, so history can't be rewritten from here.
Contact details are masked: enough to recognise a customer, not to copy.
"""

import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Annotated, Literal
from uuid import UUID

import psycopg
from fastapi import APIRouter, HTTPException, Query, Response, status
from pydantic import BaseModel

from app import audit, devices
from app.admin import AdminUser, EditorDatabase

logger = logging.getLogger("veloraug.admin")
router = APIRouter(prefix="/api/v1/admin/billing", tags=["admin"])

State = Literal["started", "pending", "completed", "failed", "reversed", "abandoned"]


def _now() -> datetime:
    return datetime.now(UTC)


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


class Metrics(BaseModel):
    active_subscribers: int
    by_plan: list[PlanCount]
    revenue_30_days_ugx: int
    completed_30_days: int
    failed_30_days: int
    reversed_30_days: int
    abandoned_30_days: int
    pending_now: int
    active_devices: int
    live_sessions: int


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
    payment_id: UUID
    plan_id: str
    plan_name: str
    starts_at: datetime
    ends_at: datetime
    max_devices: int
    max_streams: int
    revoked_at: datetime | None


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
def metrics(user: AdminUser, db: EditorDatabase) -> Metrics:
    now = _now()
    with db.as_user(user.user_id) as conn:
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
        (pending,) = conn.execute(
            "select count(*) from public.payments "
            "where state in ('started', 'pending') and created_at > %s",
            (now - timedelta(hours=24),),
        ).fetchone()
        (device_count,) = conn.execute(
            "select count(*) from public.devices where revoked_at is null"
        ).fetchone()
        (session_count,) = conn.execute(
            "select count(*) from public.playback_sessions "
            "where ended_at is null and last_seen_at > %s",
            (now - devices.IDLE,),
        ).fetchone()
    return Metrics(
        active_subscribers=active,
        by_plan=[
            PlanCount(plan_id=a, plan_name=b, subscribers=c) for a, b, c in by_plan
        ],
        revenue_30_days_ugx=counts.revenue,
        completed_30_days=counts.states.get("completed", 0),
        failed_30_days=counts.states.get("failed", 0),
        reversed_30_days=counts.states.get("reversed", 0),
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


@router.get("/subscribers")
def subscribers(
    user: AdminUser,
    db: EditorDatabase,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
) -> list[Subscriber]:
    """Accounts with a pass running now, ending soonest first."""
    now = _now()
    with db.as_user(user.user_id) as conn:
        rows = conn.execute(
            """
            select s.user_id, s.plan_id, p.plan_name, s.starts_at, s.ends_at,
              s.max_devices,
              (select count(*) from public.devices d
               where d.user_id = s.user_id and d.revoked_at is null),
              p.email, p.phone
            from public.passes s join public.payments p on p.id = s.payment_id
            where s.revoked_at is null and s.starts_at <= %s and s.ends_at > %s
            order by s.ends_at limit %s
            """,
            (now, now, limit),
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
            select s.id, s.payment_id, s.plan_id, p.plan_name, s.starts_at,
              s.ends_at, s.max_devices, s.max_streams, s.revoked_at
            from public.passes s join public.payments p on p.id = s.payment_id
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
