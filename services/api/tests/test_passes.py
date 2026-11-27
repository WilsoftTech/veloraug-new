"""Passes and payments, Step 10B, on a real Postgres with Pesapal faked.
Since Milestone 10 they run on the six tiers: Velora Start (7 days, UGX
6,000) stands in for Step 10B's day pass, Velora Flex (14 days, 10,000) for
its week, and Velora Prime for its month.

Skipped without a local test Postgres: see tests/db_support.py.
"""

import base64
import json
import uuid
from datetime import UTC, datetime, timedelta
from importlib import import_module

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.db import Database
from app.main import create_app
from app.pesapal import COMPLETED, FAILED, REVERSED
from app.playback import Granter
from tests.db_support import clear_admins, needs_database
from tests.test_database import FakeVerifier, as_user
from tests.test_pesapal import FakePesapal
from tests.test_viewer import GATEWAY, KEY, catalogue, owner  # noqa: F401

TIERS = import_module("migrations.versions.0007_subscriptions").TIERS

PUBLIC_API = "http://127.0.0.1:8000"


def settings(**changes) -> Settings:
    given = {
        "passes_required": True,
        "pesapal_consumer_key": "key",
        "pesapal_consumer_secret": "secret",
        "pesapal_ipn_id": "ipn-1234-5678",
        "public_api_url": PUBLIC_API,
    }
    return Settings(**(given | changes))


def clear_billing(conn) -> None:
    """No payments, passes, devices or sessions, and the six tiers as
    migration 0007 seeds them."""
    conn.execute("delete from public.playback_sessions")
    conn.execute("delete from public.devices")
    conn.execute("delete from public.passes")
    conn.execute("delete from public.payments")
    conn.execute("update public.pass_plans set featured = false")
    for i, _, price, *_, featured, _ in TIERS:
        conn.execute(
            "update public.pass_plans set price_ugx = %s, for_sale = true, "
            "featured = %s where id = %s",
            (price, featured, i),
        )
    conn.execute(
        "update public.pass_plans set price_ugx = null, for_sale = false where legacy"
    )
    conn.execute("delete from public.plan_changes")


@pytest.fixture
def prices(owner):  # noqa: F811
    clear_billing(owner)
    yield owner
    clear_billing(owner)


@pytest.fixture
def fake():
    return FakePesapal()


def make_api(app_url, fake, editor_url=None, **changes):
    return create_app(
        settings=settings(**changes),
        token_verifier=FakeVerifier(),
        database=Database(app_url),
        editor_database=Database(editor_url) if editor_url else None,
        granter=Granter(key=KEY.encode(), gateway_url=GATEWAY),
        pesapal=fake.client(),
    )


@pytest.fixture
def api(app_url, fake, prices):
    with TestClient(make_api(app_url, fake)) as client:
        yield client


def buy(api, user, plan="velora_start", **body):
    response = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": plan, "email": "viewer@example.com", **body},
        headers=as_user(user),
    )
    assert response.status_code == 201, response.text
    return response.json()


def tracking_of(fake, payment_id):
    return next(t for t, o in fake.orders.items() if o["id"] == payment_id)


def pay(api, fake, user, plan="velora_start", code=COMPLETED):
    """Buys a pass, has Pesapal report `code`, and checks as the app does."""
    payment = buy(api, user, plan)
    fake.statuses[tracking_of(fake, payment["payment_id"])] = code
    response = api.get(
        f"/api/v1/passes/payments/{payment['payment_id']}", headers=as_user(user)
    )
    assert response.status_code == 200, response.text
    return response.json()


def my_pass(api, user):
    response = api.get("/api/v1/me/pass", headers=as_user(user))
    assert response.status_code == 200, response.text
    return response.json()


_DEVICES: dict[uuid.UUID, str] = {}


def device_of(api, user) -> str:
    """The user's one registered device's credential, registered once."""
    if user not in _DEVICES:
        response = api.post(
            "/api/v1/me/devices",
            json={"label": "Test phone", "platform": "android"},
            headers=as_user(user),
        )
        assert response.status_code == 201, response.text
        _DEVICES[user] = response.json()["credential"]
    return _DEVICES[user]


def grant(api, item_id, user, *, device: bool = True):
    headers = as_user(user)
    if device:
        headers["X-Velora-Device"] = device_of(api, user)
    return api.post(f"/api/v1/items/{item_id}/playback", headers=headers)


def expiry(response) -> datetime:
    return datetime.fromisoformat(response.json()["expires_at"])


# --- Prices ------------------------------------------------------------------


@needs_database
def test_only_plans_on_sale_are_listed(api, prices):
    listed = api.get("/api/v1/passes/plans").json()
    assert [p["id"] for p in listed] == [t[0] for t in TIERS]
    prices.execute(
        "update public.pass_plans set for_sale = false, featured = false "
        "where id = 'velora_prime'"
    )
    listed = api.get("/api/v1/passes/plans").json()
    assert "velora_prime" not in [p["id"] for p in listed]
    response = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": "velora_prime", "email": "a@b.c"},
        headers=as_user(uuid.uuid4()),
    )
    assert response.status_code == 409


@needs_database
def test_admins_set_prices_and_viewers_cant(app_url, editor_url, fake, prices):
    admin = uuid.uuid4()
    clear_admins(prices)
    prices.execute("insert into public.admins (user_id) values (%s)", (admin,))
    try:
        with TestClient(make_api(app_url, fake, editor_url)) as api:
            changed = api.patch(
                "/api/v1/admin/pass-plans/velora_prime",
                json={"price_ugx": 25000},
                headers=as_user(admin),
            )
            assert changed.status_code == 200, changed.text
            assert changed.json()["price_ugx"] == 25000
            assert changed.json()["days"] == 30
            listed = api.get("/api/v1/admin/pass-plans", headers=as_user(admin))
            by_id = {p["id"]: p["price_ugx"] for p in listed.json()}
            assert by_id["velora_prime"] == 25000
            assert by_id["velora_start"] == 6000
            assert (
                api.patch(
                    "/api/v1/admin/pass-plans/velora_start",
                    json={"price_ugx": 100},
                    headers=as_user(admin),
                ).status_code
                == 422
            )
            assert (
                api.patch(
                    "/api/v1/admin/pass-plans/velora_start",
                    json={"price_ugx": None},
                    headers=as_user(uuid.uuid4()),
                ).status_code
                == 403
            )
    finally:
        clear_admins(prices)


# --- Buying ------------------------------------------------------------------


@needs_database
def test_checkout_sends_the_order_and_answers_pesapals_page(api, fake, prices):
    user = uuid.uuid4()

    started = buy(api, user, "velora_flex", email=None, phone="0772 123 456")

    assert started["redirect_url"].startswith("https://cybqa.pesapal.com/")
    sent = fake.orders[tracking_of(fake, started["payment_id"])]
    assert sent["amount"] == 10000
    assert sent["currency"] == "UGX"
    assert sent["callback_url"] == f"{PUBLIC_API}/api/v1/passes/return"
    assert sent["notification_id"] == "ipn-1234-5678"
    assert sent["billing_address"]["phone_number"] == "+256772123456"
    state, amount, days = prices.execute(
        "select state, amount_ugx, days from public.payments where id = %s",
        (started["payment_id"],),
    ).fetchone()
    assert (state, amount, days) == ("pending", 10000, 14)


@needs_database
def test_a_checkout_needs_an_email_or_phone_and_pesapal(api, fake):
    user = uuid.uuid4()
    response = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": "velora_start"},
        headers=as_user(user),
    )
    assert response.status_code == 422
    assert (
        api.post(
            "/api/v1/passes/checkout",
            json={"plan_id": "velora_start", "phone": "12"},
            headers=as_user(user),
        ).status_code
        == 422
    )

    fake.down = True
    response = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": "velora_start", "email": "a@b.c"},
        headers=as_user(user),
    )
    assert response.status_code == 503
    fake.down = False
    fake.refuse_orders = True
    response = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": "velora_start", "email": "a@b.c"},
        headers=as_user(user),
    )
    assert response.status_code == 502
    assert my_pass(api, user)["active"] is False


@needs_database
def test_without_pesapal_buying_answers_503(app_url, prices):
    app = create_app(
        token_verifier=FakeVerifier(),
        database=Database(app_url),
        settings=Settings(passes_required=True),
    )
    with TestClient(app) as api:
        response = api.post(
            "/api/v1/passes/checkout",
            json={"plan_id": "velora_start", "email": "a@b.c"},
            headers=as_user(uuid.uuid4()),
        )
    assert response.status_code == 503


# --- Pesapal's status --------------------------------------------------------


@needs_database
def test_a_completed_payment_makes_one_pass(api, fake, prices):
    user = uuid.uuid4()
    before = datetime.now(UTC)

    paid = pay(api, fake, user, "velora_flex")

    assert paid["state"] == "completed"
    ends = datetime.fromisoformat(paid["pass_ends_at"])
    assert timedelta(days=14) <= ends - before < timedelta(days=14, minutes=1)
    # Seen again, by the app and by a notification: still one pass.
    api.get(f"/api/v1/passes/payments/{paid['id']}", headers=as_user(user))
    api.get(
        "/api/v1/passes/ipn",
        params={"OrderTrackingId": tracking_of(fake, str(paid["id"]))},
    )
    assert prices.execute("select count(*) from public.passes").fetchone()[0] == 1
    found = my_pass(api, user)
    assert found["active"] is True
    assert found["ends_at"] == found["current_ends_at"]
    method, code = prices.execute(
        "select payment_method, confirmation_code from public.payments"
    ).fetchone()
    assert (method, code) == ("MTN", "ABC123")


@needs_database
def test_not_paid_yet_then_failed_then_paid(api, fake, prices):
    user = uuid.uuid4()
    payment = buy(api, user)
    tracking = tracking_of(fake, payment["payment_id"])
    path = f"/api/v1/passes/payments/{payment['payment_id']}"

    assert api.get(path, headers=as_user(user)).json()["state"] == "pending"
    assert my_pass(api, user)["checking"] is True
    fake.statuses[tracking] = FAILED
    assert api.get(path, headers=as_user(user)).json()["state"] == "failed"
    # On Pesapal's page the viewer can try another way to pay.
    fake.statuses[tracking] = COMPLETED
    assert api.get(path, headers=as_user(user)).json()["state"] == "completed"
    assert my_pass(api, user)["active"] is True


@pytest.mark.parametrize(
    ("amount", "currency"),
    [(5999.0, "UGX"), (6000.0, "KES"), (6000.5, "UGX"), (6000.5, "USD")],
)
@needs_database
def test_a_wrong_amount_or_currency_makes_no_pass(api, fake, prices, amount, currency):
    user = uuid.uuid4()
    payment = buy(api, user)
    tracking = tracking_of(fake, payment["payment_id"])
    fake.statuses[tracking] = COMPLETED
    fake.amounts[tracking] = amount
    fake.currency = currency

    response = api.get(
        f"/api/v1/passes/payments/{payment['payment_id']}", headers=as_user(user)
    )

    assert response.json()["state"] == "failed"
    assert my_pass(api, user)["active"] is False
    (reason,) = prices.execute("select reason from public.payments").fetchone()
    assert reason.startswith("Not accepted")


@needs_database
def test_another_payments_reference_makes_no_pass(api, fake, prices):
    user = uuid.uuid4()
    payment = buy(api, user)
    tracking = tracking_of(fake, payment["payment_id"])
    fake.orders[tracking]["id"] = str(uuid.uuid4())
    fake.statuses[tracking] = COMPLETED

    response = api.get(
        f"/api/v1/passes/payments/{payment['payment_id']}", headers=as_user(user)
    )

    assert response.json()["state"] == "failed"


@needs_database
def test_a_reversed_payment_ends_its_pass(api, fake, prices):
    user = uuid.uuid4()
    paid = pay(api, fake, user)
    fake.statuses[tracking_of(fake, str(paid["id"]))] = REVERSED

    response = api.get(
        "/api/v1/passes/ipn",
        params={
            "OrderTrackingId": tracking_of(fake, str(paid["id"])),
            "OrderNotificationType": "IPNCHANGE",
            "OrderMerchantReference": str(paid["id"]),
        },
    )

    assert response.json() == {
        "orderNotificationType": "IPNCHANGE",
        "orderTrackingId": tracking_of(fake, str(paid["id"])),
        "orderMerchantReference": str(paid["id"]),
        "status": 200,
    }
    assert my_pass(api, user)["active"] is False
    (state,) = prices.execute("select state from public.payments").fetchone()
    assert state == "reversed"


@pytest.fixture
def admin_api(app_url, editor_url, fake, prices):
    """The API with its editor role, and one admin. Answers (client, admin)."""
    admin = uuid.uuid4()
    clear_admins(prices)
    prices.execute("insert into public.admins (user_id) values (%s)", (admin,))
    try:
        with TestClient(make_api(app_url, fake, editor_url)) as client:
            yield client, admin
    finally:
        clear_admins(prices)


def refund(api, admin, payment_id):
    return api.post(
        f"/api/v1/admin/billing/payments/{payment_id}/refund", headers=as_user(admin)
    )


def notify(api, fake, payment_id):
    """Pesapal's notification for one payment, as it would send it."""
    return api.get(
        "/api/v1/passes/ipn",
        params={
            "OrderTrackingId": tracking_of(fake, payment_id),
            "OrderNotificationType": "IPNCHANGE",
            "OrderMerchantReference": payment_id,
        },
    )


@needs_database
def test_a_payment_marked_refunded_ends_its_pass_for_good(admin_api, fake, prices):
    api, admin = admin_api
    user = uuid.uuid4()
    paid = pay(api, fake, user)
    assert my_pass(api, user)["active"] is True

    response = refund(api, admin, paid["id"])

    assert response.status_code == 200, response.text
    assert response.json()["state"] == "refunded"
    assert response.json()["reason"] == "Refunded in full"
    assert my_pass(api, user)["active"] is False
    state, refunded_by, completed = prices.execute(
        "select state, refunded_by, completed_at is not null from public.payments"
    ).fetchone()
    assert (state, refunded_by, completed) == ("refunded", admin, True)
    # Pesapal still reports a refunded payment completed, and may notify:
    # neither the payment nor the pass comes back.
    fake.statuses[tracking_of(fake, paid["id"])] = COMPLETED
    assert notify(api, fake, paid["id"]).json()["status"] == 200
    fake.statuses[tracking_of(fake, paid["id"])] = REVERSED
    assert notify(api, fake, paid["id"]).json()["status"] == 200
    assert my_pass(api, user)["active"] is False
    assert prices.execute("select state from public.payments").fetchone() == (
        "refunded",
    )
    # A viewer's payment list says so too.
    mine = api.get("/api/v1/me/payments", headers=as_user(user)).json()
    assert [p["state"] for p in mine] == ["refunded"]


@needs_database
def test_refunding_a_running_pass_moves_the_next_one_up(admin_api, fake, prices):
    api, admin = admin_api
    user = uuid.uuid4()
    first = pay(api, fake, user, "velora_start")
    pay(api, fake, user, "velora_flex")
    assert my_pass(api, user)["queued"]

    assert refund(api, admin, first["id"]).status_code == 200

    found = my_pass(api, user)
    assert found["active"] is True
    assert found["current"]["plan_id"] == "velora_flex"
    assert found["queued"] == []
    starts = datetime.fromisoformat(found["current"]["starts_at"])
    assert abs(starts - datetime.now(UTC)) < timedelta(minutes=1)
    assert datetime.fromisoformat(found["current"]["ends_at"]) == starts + timedelta(
        days=14
    )


@needs_database
def test_only_an_admin_marks_only_a_completed_payment_refunded(admin_api, fake, prices):
    api, admin = admin_api
    user = uuid.uuid4()
    paid = pay(api, fake, user)
    failed = pay(api, fake, user, "velora_flex", code=FAILED)

    assert refund(api, user, paid["id"]).status_code == 403
    assert refund(api, admin, str(uuid.uuid4())).status_code == 404
    assert refund(api, admin, failed["id"]).status_code == 409
    assert refund(api, admin, paid["id"]).status_code == 200
    again = refund(api, admin, paid["id"])
    assert again.status_code == 409
    assert "refunded" in again.json()["detail"]
    listed = api.get(
        "/api/v1/admin/billing/payments",
        params={"state": "refunded"},
        headers=as_user(admin),
    ).json()
    assert [p["id"] for p in listed] == [paid["id"]]
    metrics = api.get("/api/v1/admin/billing/metrics", headers=as_user(admin)).json()
    assert metrics["refunded_30_days"] == 1
    assert metrics["revenue_30_days_ugx"] == 0


@needs_database
def test_the_database_keeps_refunds_narrow(app_url, editor_url, prices):
    """The admin role changes a payment only from completed to refunded, and
    no API role can take a refund back."""
    user, admin = uuid.uuid4(), uuid.uuid4()
    (payment,) = prices.execute(
        """
        insert into public.payments (user_id, plan_id, days, amount_ugx, email,
          plan_name, max_devices, max_streams, state, completed_at)
        values (%s, 'velora_start', 7, 6000, 'a@b.c', 'Velora Start', 1, 1,
          'completed', now())
        returning id
        """,
        (user,),
    ).fetchone()
    with psycopg.connect(editor_url) as conn:
        conn.execute("select set_config('app.user_id', %s, false)", (str(admin),))
        # Not to any other state, nor any other column.
        for change in (
            "state = 'failed'",
            "state = 'reversed'",
            "amount_ugx = 500",
            "email = 'x@y.z'",
        ):
            with pytest.raises(
                (psycopg.errors.InsufficientPrivilege, psycopg.errors.CheckViolation)
            ):
                conn.execute(
                    f"update public.payments set {change} where id = %s", (payment,)
                )
            conn.rollback()
            conn.execute("select set_config('app.user_id', %s, false)", (str(admin),))
        # Refunded needs when and by whom.
        with pytest.raises(psycopg.errors.CheckViolation):
            conn.execute(
                "update public.payments set state = 'refunded' where id = %s",
                (payment,),
            )
        conn.rollback()
        conn.execute("select set_config('app.user_id', %s, false)", (str(admin),))
        conn.execute(
            "update public.payments set state = 'refunded', refunded_at = now(), "
            "refunded_by = %s where id = %s",
            (admin, payment),
        )
        conn.commit()
        conn.execute("select set_config('app.user_id', %s, false)", (str(admin),))
        # Once refunded, its update policy no longer matches: nothing changes.
        changed = conn.execute(
            "update public.payments set state = 'refunded', reason = 'x' where id = %s",
            (payment,),
        ).rowcount
        assert changed == 0
        conn.rollback()
    with psycopg.connect(app_url) as conn:
        conn.execute("select set_config('app.user_id', %s, false)", (str(user),))
        with pytest.raises(psycopg.errors.CheckViolation):
            conn.execute(
                "update public.payments set state = 'completed' where id = %s",
                (payment,),
            )
        conn.rollback()


@needs_database
def test_a_payment_left_for_a_day_is_given_up(api, fake, prices):
    user = uuid.uuid4()
    payment = buy(api, user)
    prices.execute(
        "update public.payments set created_at = now() - interval '25 hours'"
    )

    response = api.get(
        f"/api/v1/passes/payments/{payment['payment_id']}", headers=as_user(user)
    )

    assert response.json()["state"] == "abandoned"
    assert my_pass(api, user)["checking"] is False


@needs_database
def test_the_account_tab_finds_a_payment_completed_while_away(api, fake, prices):
    user = uuid.uuid4()
    payment = buy(api, user)
    fake.statuses[tracking_of(fake, payment["payment_id"])] = COMPLETED

    found = my_pass(api, user)

    assert found["active"] is True
    assert found["checking"] is False


@needs_database
def test_a_pass_bought_early_starts_when_the_last_ends(api, fake, prices):
    user = uuid.uuid4()
    first = pay(api, fake, user, "velora_start")
    second = pay(api, fake, user, "velora_flex")

    first_end = datetime.fromisoformat(first["pass_ends_at"])
    assert datetime.fromisoformat(second["pass_ends_at"]) == first_end + timedelta(
        days=14
    )
    found = my_pass(api, user)
    assert datetime.fromisoformat(found["current_ends_at"]) == first_end
    assert datetime.fromisoformat(found["ends_at"]) == first_end + timedelta(days=14)


@needs_database
def test_viewers_see_only_their_own_payments(api, fake, prices):
    mine, theirs = uuid.uuid4(), uuid.uuid4()
    payment = buy(api, theirs)

    response = api.get(
        f"/api/v1/passes/payments/{payment['payment_id']}", headers=as_user(mine)
    )

    assert response.status_code == 404
    assert api.get("/api/v1/me/pass").status_code == 401


# --- Pesapal's return and notification ---------------------------------------


@needs_database
def test_the_return_page_checks_the_payment_and_never_echoes(api, fake, prices):
    user = uuid.uuid4()
    payment = buy(api, user)
    tracking = tracking_of(fake, payment["payment_id"])
    fake.statuses[tracking] = COMPLETED

    page = api.get(
        "/api/v1/passes/return",
        params={
            "OrderTrackingId": tracking,
            "OrderMerchantReference": "<script>alert(1)</script>",
            "OrderNotificationType": "CALLBACKURL",
        },
    )

    assert page.status_code == 200
    assert page.headers["content-type"].startswith("text/html")
    assert "Payment received" in page.text
    # Only the page's own script: nothing from the address is echoed.
    assert "alert(1)" not in page.text
    assert page.text.count("<script>") == 1
    assert 'postMessage("veloraug:pesapal-returned", "*")' in page.text
    assert my_pass(api, user)["active"] is True
    # Unknown or malformed: the same polite page, nothing checked.
    other = api.get("/api/v1/passes/return", params={"OrderTrackingId": "x<y"})
    assert other.status_code == 200 and "Thank you" in other.text


@needs_database
def test_a_notification_for_an_unknown_payment_isnt_acknowledged(api, fake, prices):
    response = api.get(
        "/api/v1/passes/ipn", params={"OrderTrackingId": "track-9999-0000-0000"}
    )
    assert response.json()["status"] == 500
    assert (
        api.get("/api/v1/passes/ipn", params={"OrderTrackingId": "a b"}).status_code
        == 400
    )


# --- Grants ------------------------------------------------------------------


def claims(response):
    token = response.json()["playlist_url"].removeprefix(f"{GATEWAY}/v1/").split("/")[0]
    payload = token.split(".")[0]
    return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))


@needs_database
def test_without_a_pass_playback_answers_402(api, catalogue):  # noqa: F811
    response = grant(api, catalogue["movie"].item_id, uuid.uuid4(), device=False)

    assert response.status_code == 402
    assert response.json()["detail"] == "You need a pass to watch."
    # A film that can't be watched anyway says so first.
    assert grant(api, uuid.uuid4(), uuid.uuid4(), device=False).status_code == 404


@needs_database
def test_a_grant_ends_no_later_than_the_pass(api, fake, prices, catalogue):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_start")
    prices.execute("update public.passes set ends_at = now() + interval '20 minutes'")
    prices.execute("update public.passes set starts_at = ends_at - interval '7 days'")

    response = grant(api, catalogue["movie"].item_id, user)

    assert response.status_code == 200
    (ends,) = prices.execute("select ends_at from public.passes").fetchone()
    assert abs(expiry(response) - ends) < timedelta(seconds=1)
    assert claims(response)["e"] == int(ends.timestamp())

    # Once it has ended, the renewal is refused.
    prices.execute(
        "update public.passes set ends_at = now() - interval '1 minute', "
        "starts_at = now() - interval '7 days 1 minute'"
    )
    assert grant(api, catalogue["movie"].item_id, user).status_code == 402


@needs_database
def test_a_long_pass_gets_one_hour_session_grants(api, fake, prices, catalogue):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_flex")

    response = grant(api, catalogue["movie"].item_id, user)

    left = expiry(response) - datetime.now(UTC)
    assert timedelta(minutes=59) < left <= timedelta(hours=1)
    assert claims(response)["s"] == response.json()["session_id"]


@needs_database
def test_admins_and_passes_off_need_no_pass(app_url, fake, prices, catalogue):  # noqa: F811
    admin = uuid.uuid4()
    clear_admins(prices)
    prices.execute("insert into public.admins (user_id) values (%s)", (admin,))
    try:
        with TestClient(make_api(app_url, fake)) as api:
            response = grant(api, catalogue["movie"].item_id, admin, device=False)
            assert response.status_code == 200
            assert "s" not in claims(response)
        with TestClient(make_api(app_url, fake, passes_required=False)) as api:
            response = grant(
                api, catalogue["movie"].item_id, uuid.uuid4(), device=False
            )
            assert response.status_code == 200
            assert "s" not in claims(response)
    finally:
        clear_admins(prices)


# --- The database's own rules ------------------------------------------------


@needs_database
def test_the_database_refuses_passes_that_dont_match_a_payment(app_url, prices):
    user = uuid.uuid4()
    with psycopg.connect(app_url) as conn:
        conn.execute("select set_config('app.user_id', %s, false)", (str(user),))
        (pending,) = conn.execute(
            """
            insert into public.payments (user_id, plan_id, days, amount_ugx, email,
              plan_name, max_devices, max_streams)
            values (%s, 'velora_start', 7, 6000, 'a@b.c', 'Velora Start', 1, 1)
            returning id
            """,
            (user,),
        ).fetchone()
        conn.commit()
        for payment, days in ((pending, 7),):
            with pytest.raises(psycopg.errors.CheckViolation):
                conn.execute(
                    """
                    insert into public.passes (user_id, payment_id, starts_at, ends_at,
                      plan_id, max_devices, max_streams)
                    values (%s, %s, now(), now() + make_interval(days => %s),
                      'velora_start', 1, 1)
                    """,
                    (user, payment, days),
                )
            conn.rollback()
        conn.execute("select set_config('app.user_id', %s, false)", (str(user),))
        conn.execute(
            "update public.payments set state = 'completed', completed_at = now()"
        )
        conn.commit()
        conn.execute("select set_config('app.user_id', %s, false)", (str(user),))
        # The wrong length.
        with pytest.raises(psycopg.errors.CheckViolation):
            conn.execute(
                """
                insert into public.passes (user_id, payment_id, starts_at, ends_at,
                  plan_id, max_devices, max_streams)
                values (%s, %s, now(), now() + interval '30 days',
                  'velora_start', 1, 1)
                """,
                (user, pending),
            )
        conn.rollback()
        # Another viewer's payment isn't even visible.
        conn.execute(
            "select set_config('app.user_id', %s, false)", (str(uuid.uuid4()),)
        )
        assert conn.execute("select count(*) from public.payments").fetchone() == (0,)
        assert conn.execute("select count(*) from public.admins").fetchone() == (0,)
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            conn.execute("select email from public.admins")
        conn.rollback()


# --- VUG-SEC-004: one checkout, one order ------------------------------------


@pytest.fixture
def app_db(app_url):
    db = Database(app_url)
    db.open()
    yield db
    db.close()


def submitted(fake) -> int:
    return sum(
        r.url.path.endswith("/Transactions/SubmitOrderRequest") for r in fake.requests
    )


@needs_database
def test_two_checkouts_at_once_reserve_one_payment(app_db, prices):
    """The second waits for the first's reservation, then sees it."""
    import threading

    from app import passes

    user = uuid.uuid4()
    db = app_db
    now = datetime.now(UTC)
    outcome: list[object] = []
    with db.as_user(user) as first:
        payment, new = passes.reserve_checkout(
            first, user, "velora_start", now, email="v@example.com", phone=None
        )
        assert new is True

        def second() -> None:
            with db.as_user(user) as conn:
                try:
                    outcome.append(
                        passes.reserve_checkout(
                            conn,
                            user,
                            "velora_start",
                            now,
                            email="v@example.com",
                            phone=None,
                        )
                    )
                except passes.CheckoutStarting as error:
                    outcome.append(error)

        thread = threading.Thread(target=second)
        thread.start()
        thread.join(1.0)
        # Held by the first reservation's lock until it commits.
        assert thread.is_alive() and outcome == []
    thread.join(10)

    assert len(outcome) == 1 and isinstance(outcome[0], passes.CheckoutStarting)
    rows = prices.execute(
        "select id from public.payments where user_id = %s", (user,)
    ).fetchall()
    assert [row[0] for row in rows] == [payment.id]


@needs_database
def test_a_checkout_still_starting_holds_off_another(api, app_db, fake, prices):
    user = uuid.uuid4()
    with app_db.as_user(user) as conn:
        from app import passes

        passes.reserve_checkout(
            conn,
            user,
            "velora_start",
            datetime.now(UTC),
            email="v@example.com",
            phone=None,
        )

    response = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": "velora_start", "email": "v@example.com"},
        headers=as_user(user),
    )

    assert response.status_code == 503
    assert response.headers["Retry-After"] == "5"
    assert submitted(fake) == 0
    # Another plan is another purchase.
    assert buy(api, user, "velora_flex")["redirect_url"]


@needs_database
def test_a_retried_attempt_answers_the_same_payment(api, fake, prices):
    user, attempt = uuid.uuid4(), str(uuid.uuid4())

    first = buy(api, user, attempt_id=attempt)
    again = api.post(
        "/api/v1/passes/checkout",
        json={
            "plan_id": "velora_start",
            "email": "v@example.com",
            "attempt_id": attempt,
        },
        headers=as_user(user),
    )

    assert again.status_code == 200
    assert again.json() == first
    assert submitted(fake) == 1
    # Another viewer's attempt with the same ID is their own.
    other = buy(api, uuid.uuid4(), attempt_id=attempt)
    assert other["payment_id"] != first["payment_id"]


@needs_database
def test_an_ended_attempt_starts_a_new_payment(api, fake, prices):
    user, attempt = uuid.uuid4(), str(uuid.uuid4())
    fake.refuse_orders = True
    refused = api.post(
        "/api/v1/passes/checkout",
        json={
            "plan_id": "velora_start",
            "email": "v@example.com",
            "attempt_id": attempt,
        },
        headers=as_user(user),
    )
    assert refused.status_code == 502
    fake.refuse_orders = False

    retried = buy(api, user, attempt_id=attempt)

    states = prices.execute(
        "select state from public.payments where user_id = %s order by created_at",
        (user,),
    ).fetchall()
    assert states == [("abandoned",), ("pending",)]
    assert retried["redirect_url"]


def lost_order(app_db, fake, prices, user):
    """A payment reserved and sent, whose order's answer never came back."""
    from app import passes

    with app_db.as_user(user) as conn:
        payment, _ = passes.reserve_checkout(
            conn,
            user,
            "velora_start",
            datetime.now(UTC) - timedelta(minutes=5),
            email="v@example.com",
            phone=None,
        )
    prices.execute(
        "update public.payments set created_at = now() - interval '5 minutes' "
        "where id = %s",
        (payment.id,),
    )
    tracking = "track-7777-0000-0000"
    fake.orders[tracking] = {"id": str(payment.id), "amount": payment.amount_ugx}
    return payment, tracking


@needs_database
def test_a_lost_orders_notification_finds_its_payment(api, app_db, fake, prices):
    user = uuid.uuid4()
    payment, tracking = lost_order(app_db, fake, prices, user)
    fake.statuses[tracking] = COMPLETED

    answer = api.get(
        "/api/v1/passes/ipn",
        params={
            "OrderTrackingId": tracking,
            "OrderNotificationType": "IPNCHANGE",
            "OrderMerchantReference": str(payment.id),
        },
    ).json()

    assert answer["status"] == 200
    assert prices.execute(
        "select state, tracking_id from public.payments where id = %s", (payment.id,)
    ).fetchone() == ("completed", tracking)
    assert my_pass(api, user)["active"] is True
    # A later checkout isn't held off by it.
    assert buy(api, user, "velora_flex")["redirect_url"]


@needs_database
def test_a_notification_naming_another_payment_matches_nothing(
    api, app_db, fake, prices
):
    user = uuid.uuid4()
    payment, tracking = lost_order(app_db, fake, prices, user)
    fake.statuses[tracking] = COMPLETED
    # Pesapal says this order is for some other reference.
    fake.orders[tracking]["id"] = str(uuid.uuid4())

    answer = api.get(
        "/api/v1/passes/ipn",
        params={"OrderTrackingId": tracking, "OrderMerchantReference": str(payment.id)},
    ).json()

    assert answer["status"] == 500
    assert prices.execute(
        "select state, tracking_id from public.payments where id = %s", (payment.id,)
    ).fetchone() == ("started", None)
    assert prices.execute("select count(*) from public.passes").fetchone()[0] == 0
    for reference in ("not-a-uuid", str(uuid.uuid4())):
        assert (
            api.get(
                "/api/v1/passes/ipn",
                params={
                    "OrderTrackingId": tracking,
                    "OrderMerchantReference": reference,
                },
            ).json()["status"]
            == 500
        )
