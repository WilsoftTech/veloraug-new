"""Passes and payments: Step 10B, and the six tiers of Milestone 10. See
docs/step-10a-payments-plan.md, "The API".

Viewers' routes act only on the signed-in viewer's own payments. Pesapal's
return and notification routes need no sign-in: they only make the API ask
Pesapal for the payment's status, which is what decides.

Prices, lengths and device allowances come from the database, never from
the app. The log names payments by VeloraUG's ID, never a phone, an email,
a token or Pesapal's keys.
"""

import html
import logging
import re
from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Path,
    Query,
    Request,
    Response,
    status,
)
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, Field, field_validator

from app import audit, passes, ratelimit
from app.admin import AdminUser, EditorDatabase
from app.auth import VerifiedUser, current_user
from app.db import Database
from app.pesapal import PesapalClient, PesapalError, PesapalUnavailable
from app.viewer_routes import AppDatabase

logger = logging.getLogger("veloraug.passes")
router = APIRouter(prefix="/api/v1", tags=["passes"])

PAYMENTS_OFF = "Buying passes isn't set up on this server."
NOT_FOR_SALE = "This pass isn't for sale."
PESAPAL_DOWN = "Pesapal isn't answering. Try again in a few minutes."
PESAPAL_REFUSED = "Pesapal couldn't start this payment. Try again later."
NOT_FOUND = "There's no such payment."
_TRACKING = re.compile(r"[0-9A-Za-z-]{8,64}")
_EMAIL = re.compile(r"[^@\s]{1,64}@[^@\s]{1,255}")
PLAN_ID = r"^[a-z_]{2,20}$"


def pesapal_client(request: Request) -> PesapalClient:
    client: PesapalClient | None = request.app.state.pesapal
    if client is None:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, PAYMENTS_OFF)
    return client


Pesapal = Annotated[PesapalClient, Depends(pesapal_client)]
Viewer = Annotated[VerifiedUser, Depends(current_user)]


def _now() -> datetime:
    return datetime.now(UTC)


# --- Models ------------------------------------------------------------------


class PlanOut(BaseModel):
    id: str
    days: int
    price_ugx: int
    # Milestone 10: the tier's name and allowances, from the server only.
    display_name: str
    description: str | None
    max_devices: int
    max_streams: int
    featured: bool


def _plan_out(p: passes.Plan) -> PlanOut:
    return PlanOut(
        id=p.id,
        days=p.days,
        price_ugx=p.price_ugx,
        display_name=p.display_name,
        description=p.description,
        max_devices=p.max_devices,
        max_streams=p.max_streams,
        featured=p.featured,
    )


class EntitlementOut(BaseModel):
    id: UUID
    plan_id: str
    plan_name: str
    starts_at: datetime
    ends_at: datetime
    max_devices: int
    max_streams: int


def _entitlement_out(e: passes.Entitlement) -> EntitlementOut:
    return EntitlementOut(
        id=e.id,
        plan_id=e.plan_id,
        plan_name=e.plan_name,
        starts_at=e.starts_at,
        ends_at=e.ends_at,
        max_devices=e.max_devices,
        max_streams=e.max_streams,
    )


class PassOut(BaseModel):
    # A pass is running now.
    active: bool
    # When the running pass ends, and when the last one bought ends.
    current_ends_at: datetime | None
    ends_at: datetime | None
    # A payment is still being checked with Pesapal.
    checking: bool
    # Milestone 10: the pass running now, and each one queued after it,
    # with its own start, end, plan and allowances.
    current: EntitlementOut | None = None
    queued: list[EntitlementOut] = []


class PaymentRow(BaseModel):
    id: UUID
    plan_id: str
    plan_name: str
    amount_ugx: int
    state: str
    created_at: datetime
    completed_at: datetime | None
    # Pesapal's confirmation code once paid, for the viewer's own records.
    provider_reference: str | None


class CheckoutIn(BaseModel):
    # Checked against the plans on sale, in the database.
    plan_id: str = Field(pattern=PLAN_ID)
    # Pesapal needs one of them. The app sends the email the viewer signed
    # in with, or asks for a phone number.
    email: str | None = Field(default=None, max_length=320)
    phone: str | None = Field(default=None, max_length=20)

    @field_validator("email")
    @classmethod
    def check_email(cls, email: str | None) -> str | None:
        if email is None or not email.strip():
            return None
        email = email.strip()
        if not _EMAIL.fullmatch(email):
            raise ValueError("That isn't an email address")
        return email

    @field_validator("phone")
    @classmethod
    def check_phone(cls, phone: str | None) -> str | None:
        if phone is None or not phone.strip():
            return None
        phone = re.sub(r"[\s-]", "", phone)
        # 07XX XXX XXX becomes +2567XX XXX XXX.
        if re.fullmatch(r"0[0-9]{9}", phone):
            phone = "+256" + phone[1:]
        if not re.fullmatch(r"\+?[0-9]{9,15}", phone):
            raise ValueError("That isn't a phone number")
        return phone


class CheckoutOut(BaseModel):
    payment_id: UUID
    redirect_url: str


class PaymentOut(BaseModel):
    id: UUID
    plan_id: str
    plan_name: str
    amount_ugx: int
    # started, pending, completed, failed, reversed or abandoned.
    state: str
    # Once completed: when the viewer's last pass ends.
    pass_ends_at: datetime | None


class PlanPrice(BaseModel):
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


def _plan_price(p: passes.Plan) -> PlanPrice:
    return PlanPrice(**p.__dict__)


class PriceIn(BaseModel):
    # Whole shillings, or null to stop selling the pass. A field left out
    # stays as it is.
    price_ugx: int | None = Field(default=None, ge=500, le=10_000_000)
    for_sale: bool | None = None
    featured: bool | None = None


# --- Viewers -----------------------------------------------------------------


@router.get("/passes/plans")
def list_plans(db: AppDatabase) -> list[PlanOut]:
    """The plans for sale, in display order, with their prices and
    allowances. No sign-in needed."""
    with db.anonymous() as conn:
        return [_plan_out(p) for p in passes.plans(conn)]


@router.get("/me/pass")
def my_pass(request: Request, user: Viewer, db: AppDatabase) -> PassOut:
    """The viewer's membership: the pass running now and those queued after
    it. Their unfinished payments of the last 24 hours are checked with
    Pesapal first, in case a notification never came."""
    now = _now()
    client: PesapalClient | None = request.app.state.pesapal
    with db.as_user(user.user_id) as conn:
        waiting = passes.open_payments(conn, now)
    if client is not None:
        for payment in waiting:
            try:
                passes.refresh(db, client, user.user_id, payment, now)
            except PesapalUnavailable:
                break
    with db.as_user(user.user_id) as conn:
        found = passes.pass_status(conn, user.user_id, now)
        schedule = passes.entitlements(conn, user.user_id, now)
        checking = any(
            p.state in ("started", "pending") for p in passes.open_payments(conn, now)
        )
    current = next((e for e in schedule if e.starts_at <= now), None)
    return PassOut(
        active=found.current_ends_at is not None,
        current_ends_at=found.current_ends_at,
        ends_at=found.ends_at,
        checking=checking,
        current=_entitlement_out(current) if current else None,
        queued=[_entitlement_out(e) for e in schedule if e.starts_at > now],
    )


@router.get("/me/payments")
def my_payments(user: Viewer, db: AppDatabase) -> list[PaymentRow]:
    """The viewer's last 20 payments, newest first. A payment shows as
    completed only once the API has confirmed it with Pesapal."""
    with db.as_user(user.user_id) as conn:
        found = passes.recent_payments(conn)
    return [
        PaymentRow(
            id=p.id,
            plan_id=p.plan_id,
            plan_name=p.plan_name,
            amount_ugx=p.amount_ugx,
            state=p.state,
            created_at=p.created_at,
            completed_at=p.completed_at,
            provider_reference=p.confirmation_code,
        )
        for p in found
    ]


@router.post(
    "/passes/checkout",
    status_code=status.HTTP_201_CREATED,
    responses={
        200: {"description": "A checkout retried within minutes: the same one."},
        409: {"description": NOT_FOR_SALE},
        422: {"description": "No email or phone, or one that isn't valid."},
        429: {"description": ratelimit.TOO_MANY},
        502: {"description": PESAPAL_REFUSED},
        503: {"description": PAYMENTS_OFF},
    },
)
def checkout(
    body: CheckoutIn,
    request: Request,
    response: Response,
    user: Viewer,
    db: AppDatabase,
    client: Pesapal,
) -> CheckoutOut:
    """Starts paying for one plan. Answers Pesapal's page, where the viewer
    pays. Nothing is bought until Pesapal reports it completed. Retried
    within a few minutes for the same plan, it answers the same payment,
    so a double tap never makes two orders."""
    if body.email is None and body.phone is None:
        raise HTTPException(422, "An email or a phone number is needed.")
    settings = request.app.state.settings
    with db.as_user(user.user_id) as conn:
        again = passes.reusable_checkout(conn, body.plan_id, _now())
    if again is not None:
        response.status_code = status.HTTP_200_OK
        return CheckoutOut(payment_id=again.id, redirect_url=again.redirect_url)
    request.app.state.rate_limiter.check(
        "checkout", str(user.user_id), ratelimit.CHECKOUT
    )
    with db.as_user(user.user_id) as conn:
        try:
            payment = passes.start_payment(
                conn, user.user_id, body.plan_id, email=body.email, phone=body.phone
            )
        except passes.NotForSale:
            raise HTTPException(status.HTTP_409_CONFLICT, NOT_FOR_SALE) from None
    try:
        order = client.submit_order(
            reference=str(payment.id),
            amount=payment.amount_ugx,
            currency=passes.CURRENCY,
            description=f"VeloraUG {payment.plan_name}, {payment.days} days",
            callback_url=f"{settings.public_api_url}/api/v1/passes/return",
            notification_id=settings.pesapal_ipn_id,
            email=payment.email,
            phone=payment.phone,
        )
    except PesapalError as error:
        with db.as_user(user.user_id) as conn:
            passes.refused_by_pesapal(conn, payment.id, str(error))
        logger.warning("payment %s not started: %s", payment.id, error)
        audit.event("payment.not_started", payment_id=payment.id, user_id=user.user_id)
        if isinstance(error, PesapalUnavailable):
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE, PESAPAL_DOWN
            ) from None
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, PESAPAL_REFUSED) from None
    with db.as_user(user.user_id) as conn:
        passes.sent_to_pesapal(conn, payment.id, order.tracking_id, order.redirect_url)
    logger.info("payment %s started: a %s pass", payment.id, payment.plan_id)
    audit.event(
        "payment.started",
        payment_id=payment.id,
        user_id=user.user_id,
        plan_id=payment.plan_id,
        amount_ugx=payment.amount_ugx,
    )
    return CheckoutOut(payment_id=payment.id, redirect_url=order.redirect_url)


@router.get(
    "/passes/payments/{payment_id}",
    responses={
        404: {"description": NOT_FOUND},
        429: {"description": ratelimit.TOO_MANY},
    },
)
def get_payment(
    payment_id: UUID, request: Request, user: Viewer, db: AppDatabase
) -> PaymentOut:
    """One of the viewer's payments, checked with Pesapal first if it isn't
    settled. The app asks this every few seconds while the viewer pays."""
    request.app.state.rate_limiter.check(
        "payment", str(user.user_id), ratelimit.PAYMENT_STATUS
    )
    now = _now()
    with db.as_user(user.user_id) as conn:
        payment = passes.get_payment(conn, payment_id)
    if payment is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
    state = payment.state
    client: PesapalClient | None = request.app.state.pesapal
    if client is not None and state in passes.OPEN:
        try:
            state = passes.refresh(db, client, user.user_id, payment, now)
        except PesapalUnavailable:
            pass
    ends_at = None
    if state == "completed":
        with db.as_user(user.user_id) as conn:
            ends_at = passes.pass_status(conn, user.user_id, now).ends_at
    return PaymentOut(
        id=payment.id,
        plan_id=payment.plan_id,
        plan_name=payment.plan_name,
        amount_ugx=payment.amount_ugx,
        state=state,
        pass_ends_at=ends_at,
    )


# --- Pesapal -----------------------------------------------------------------


def _check_by_tracking(
    db: Database, client: PesapalClient, tracking_id: str, *, notified: bool
) -> str | None:
    """Asks Pesapal about the payment with this tracking ID. Answers its
    state, or None if there's no such payment. Raises PesapalUnavailable."""
    with db.anonymous() as conn:
        owner = passes.owner_of(conn, tracking_id)
    if owner is None:
        return None
    with db.as_user(owner) as conn:
        found = conn.execute(
            "select id from public.payments where tracking_id = %s", (tracking_id,)
        ).fetchone()
        payment = passes.get_payment(conn, found[0]) if found else None
    if payment is None:
        return None
    return passes.refresh(
        db, client, owner, payment, _now(), even_if_completed=notified
    )


RETURN_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>VeloraUG</title>
<style>
body {{ font-family: system-ui, sans-serif; background: #0b0b10; color: #f2f2f5;
  display: grid; place-items: center; min-height: 100vh; margin: 0; padding: 16px; }}
main {{ max-width: 28rem; text-align: center; }}
</style></head>
<body><main><h1>{title}</h1><p>{message}</p></main></body></html>
"""


@router.get("/passes/return", response_class=HTMLResponse, include_in_schema=False)
def pesapal_return(
    request: Request,
    db: AppDatabase,
    tracking_id: Annotated[str | None, Query(alias="OrderTrackingId")] = None,
) -> HTMLResponse:
    """Where Pesapal sends the viewer after paying. The page never says the
    payment succeeded on Pesapal's word: only once the API has checked."""
    client: PesapalClient | None = request.app.state.pesapal
    state = None
    if client is not None and tracking_id and _TRACKING.fullmatch(tracking_id):
        try:
            state = _check_by_tracking(db, client, tracking_id, notified=False)
        except PesapalUnavailable:
            pass
    if state == "completed":
        title, message = (
            "Payment received",
            "Your membership is ready. You can close this tab and go back to VeloraUG.",
        )
    else:
        title, message = (
            "Thank you",
            "You can close this tab and go back to VeloraUG, which shows when "
            "your payment has gone through.",
        )
    return HTMLResponse(
        RETURN_PAGE.format(title=html.escape(title), message=html.escape(message)),
        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"},
    )


@router.get("/passes/ipn", include_in_schema=False)
def pesapal_notification(
    request: Request,
    db: AppDatabase,
    client: Pesapal,
    tracking_id: Annotated[str, Query(alias="OrderTrackingId")],
    kind: Annotated[str | None, Query(alias="OrderNotificationType")] = None,
    reference: Annotated[str | None, Query(alias="OrderMerchantReference")] = None,
) -> JSONResponse:
    """Pesapal's notification that a payment changed. Answered in the JSON
    Pesapal asks for: status 200 once checked, 500 if it couldn't be, so
    Pesapal tries again. Safe to repeat: a second notification changes
    nothing."""
    if not _TRACKING.fullmatch(tracking_id):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Not a tracking ID.")
    try:
        state = _check_by_tracking(db, client, tracking_id, notified=True)
        done = state is not None
        if not done:
            logger.warning("Pesapal notified an unknown payment")
            audit.event("payment.unknown_notification")
    except PesapalUnavailable as error:
        logger.warning("Pesapal notification not checked: %s", error)
        done = False
    return JSONResponse(
        {
            "orderNotificationType": "IPNCHANGE",
            "orderTrackingId": tracking_id,
            "orderMerchantReference": reference
            if reference and _TRACKING.fullmatch(reference)
            else "",
            "status": 200 if done else 500,
        }
    )


# --- Admins ------------------------------------------------------------------


@router.get("/admin/pass-plans", tags=["admin"])
def admin_plans(user: AdminUser, db: EditorDatabase) -> list[PlanPrice]:
    """Every plan, legacy passes included, in display order."""
    with db.as_user(user.user_id) as conn:
        return [_plan_price(p) for p in passes.plans(conn, for_sale_only=False)]


@router.patch(
    "/admin/pass-plans/{plan_id}",
    tags=["admin"],
    responses={404: {"description": "No such plan."}, 409: {"description": "Refused."}},
)
def admin_set_price(
    plan_id: Annotated[str, Path(pattern=PLAN_ID)],
    body: PriceIn,
    user: AdminUser,
    db: EditorDatabase,
) -> PlanPrice:
    """A plan's price in whole shillings, whether it's on sale, and whether
    it's the featured plan. Payments already made keep what they paid for,
    and the database records every change. A null price takes it off sale."""
    given = body.model_fields_set
    try:
        with db.as_user(user.user_id) as conn:
            plan = passes.update_plan(
                conn,
                plan_id,
                price_ugx=body.price_ugx,
                change_price="price_ugx" in given,
                for_sale=(
                    False
                    if "price_ugx" in given and body.price_ugx is None
                    else body.for_sale
                ),
                featured=body.featured,
            )
    except LookupError:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, "There's no such plan."
        ) from None
    except passes.PlanChangeRefused as refused:
        raise HTTPException(status.HTTP_409_CONFLICT, str(refused)) from None
    logger.info("Admin %s changed the %s plan", user.user_id, plan_id)
    audit.event(
        "plan.changed",
        admin_id=user.user_id,
        plan_id=plan_id,
        price_ugx=plan.price_ugx,
        for_sale=plan.for_sale,
        featured=plan.featured,
    )
    return _plan_price(plan)
