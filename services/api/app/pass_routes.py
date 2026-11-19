"""Passes and payments, Step 10B. See docs/step-10a-payments-plan.md, "The API".

Viewers' routes act only on the signed-in viewer's own payments. Pesapal's
return and notification routes need no sign-in: they only make the API ask
Pesapal for the payment's status, which is what decides.

The log names payments by VeloraUG's ID, never a phone, an email, a token or
Pesapal's keys.
"""

import html
import logging
import re
from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, Field, field_validator

from app import passes
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
DESCRIPTIONS = {
    "day": "VeloraUG pass, 1 day",
    "week": "VeloraUG pass, 1 week",
    "month": "VeloraUG pass, 1 month",
}


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


class PassOut(BaseModel):
    # A pass is running now.
    active: bool
    # When the running pass ends, and when the last one bought ends.
    current_ends_at: datetime | None
    ends_at: datetime | None
    # A payment is still being checked with Pesapal.
    checking: bool


class CheckoutIn(BaseModel):
    plan_id: Literal["day", "week", "month"]
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
    amount_ugx: int
    # started, pending, completed, failed, reversed or abandoned.
    state: str
    # Once completed: when the viewer's last pass ends.
    pass_ends_at: datetime | None


class PlanPrice(BaseModel):
    id: str
    days: int
    price_ugx: int | None


class PriceIn(BaseModel):
    # Whole shillings, or null to stop selling the pass.
    price_ugx: int | None = Field(default=None, ge=500, le=10_000_000)


# --- Viewers -----------------------------------------------------------------


@router.get("/passes/plans")
def list_plans(db: AppDatabase) -> list[PlanOut]:
    """The passes for sale, with their prices. No sign-in needed."""
    with db.anonymous() as conn:
        return [
            PlanOut(id=p.id, days=p.days, price_ugx=p.price_ugx)
            for p in passes.plans(conn)
        ]


@router.get("/me/pass")
def my_pass(request: Request, user: Viewer, db: AppDatabase) -> PassOut:
    """Whether the viewer has a pass. Their unfinished payments of the last
    24 hours are checked with Pesapal first, in case a notification never
    came."""
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
        checking = any(
            p.state in ("started", "pending") for p in passes.open_payments(conn, now)
        )
    return PassOut(
        active=found.current_ends_at is not None,
        current_ends_at=found.current_ends_at,
        ends_at=found.ends_at,
        checking=checking,
    )


@router.post(
    "/passes/checkout",
    status_code=status.HTTP_201_CREATED,
    responses={
        409: {"description": NOT_FOR_SALE},
        422: {"description": "No email or phone, or one that isn't valid."},
        502: {"description": PESAPAL_REFUSED},
        503: {"description": PAYMENTS_OFF},
    },
)
def checkout(
    body: CheckoutIn,
    request: Request,
    user: Viewer,
    db: AppDatabase,
    client: Pesapal,
) -> CheckoutOut:
    """Starts paying for one pass. Answers Pesapal's page, where the viewer
    pays. Nothing is bought until Pesapal reports it completed."""
    if body.email is None and body.phone is None:
        raise HTTPException(422, "An email or a phone number is needed.")
    settings = request.app.state.settings
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
            description=DESCRIPTIONS[payment.plan_id],
            callback_url=f"{settings.public_api_url}/api/v1/passes/return",
            notification_id=settings.pesapal_ipn_id,
            email=payment.email,
            phone=payment.phone,
        )
    except PesapalError as error:
        with db.as_user(user.user_id) as conn:
            passes.refused_by_pesapal(conn, payment.id, str(error))
        logger.warning("payment %s not started: %s", payment.id, error)
        if isinstance(error, PesapalUnavailable):
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE, PESAPAL_DOWN
            ) from None
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, PESAPAL_REFUSED) from None
    with db.as_user(user.user_id) as conn:
        passes.sent_to_pesapal(conn, payment.id, order.tracking_id)
    logger.info("payment %s started: a %s pass", payment.id, payment.plan_id)
    return CheckoutOut(payment_id=payment.id, redirect_url=order.redirect_url)


@router.get(
    "/passes/payments/{payment_id}", responses={404: {"description": NOT_FOUND}}
)
def get_payment(
    payment_id: UUID, request: Request, user: Viewer, db: AppDatabase
) -> PaymentOut:
    """One of the viewer's payments, checked with Pesapal first if it isn't
    settled. The app asks this every few seconds while the viewer pays."""
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
    payment succeeded: the app, still open, shows that once it's checked."""
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
            "Your pass is ready. You can close this tab and go back to VeloraUG.",
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
    Pesapal asks for: status 200 once checked, 500 if it couldn't be."""
    if not _TRACKING.fullmatch(tracking_id):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Not a tracking ID.")
    try:
        state = _check_by_tracking(db, client, tracking_id, notified=True)
        done = state is not None
        if not done:
            logger.warning("Pesapal notified an unknown payment")
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
    with db.as_user(user.user_id) as conn:
        return [
            PlanPrice(id=p.id, days=p.days, price_ugx=p.price_ugx)
            for p in passes.plans(conn, for_sale_only=False)
        ]


@router.patch("/admin/pass-plans/{plan_id}", tags=["admin"])
def admin_set_price(
    plan_id: Literal["day", "week", "month"],
    body: PriceIn,
    user: AdminUser,
    db: EditorDatabase,
) -> PlanPrice:
    """A pass's price in whole shillings, or null to stop selling it."""
    with db.as_user(user.user_id) as conn:
        plan = passes.set_price(conn, plan_id, body.price_ugx)
    logger.info("Admin %s set the %s pass to %s", user.user_id, plan_id, plan.price_ugx)
    return PlanPrice(id=plan.id, days=plan.days, price_ugx=plan.price_ugx)
