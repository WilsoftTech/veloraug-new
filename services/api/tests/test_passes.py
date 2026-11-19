"""Passes and payments, Step 10B, on a real Postgres with Pesapal faked.

Skipped without a local test Postgres: see tests/db_support.py.
"""

import base64
import json
import uuid
from datetime import UTC, datetime, timedelta

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


@pytest.fixture
def prices(owner):  # noqa: F811
    owner.execute("delete from public.passes")
    owner.execute("delete from public.payments")
    owner.execute("update public.pass_plans set price_ugx = null")
    owner.execute("update public.pass_plans set price_ugx = 2000 where id = 'day'")
    owner.execute("update public.pass_plans set price_ugx = 8000 where id = 'week'")
    yield owner
    owner.execute("delete from public.passes")
    owner.execute("delete from public.payments")
    owner.execute("update public.pass_plans set price_ugx = null")


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


def buy(api, user, plan="day", **body):
    response = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": plan, "email": "viewer@example.com", **body},
        headers=as_user(user),
    )
    assert response.status_code == 201, response.text
    return response.json()


def tracking_of(fake, payment_id):
    return next(t for t, o in fake.orders.items() if o["id"] == payment_id)


def pay(api, fake, user, plan="day", code=COMPLETED):
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


def grant(api, item_id, user):
    return api.post(f"/api/v1/items/{item_id}/playback", headers=as_user(user))


def expiry(response) -> datetime:
    return datetime.fromisoformat(response.json()["expires_at"])


# --- Prices ------------------------------------------------------------------


@needs_database
def test_only_passes_with_a_price_are_for_sale(api):
    assert api.get("/api/v1/passes/plans").json() == [
        {"id": "day", "days": 1, "price_ugx": 2000},
        {"id": "week", "days": 7, "price_ugx": 8000},
    ]
    response = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": "month", "email": "a@b.c"},
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
                "/api/v1/admin/pass-plans/month",
                json={"price_ugx": 25000},
                headers=as_user(admin),
            )
            assert changed.json() == {"id": "month", "days": 30, "price_ugx": 25000}
            listed = api.get("/api/v1/admin/pass-plans", headers=as_user(admin))
            assert [p["price_ugx"] for p in listed.json()] == [2000, 8000, 25000]
            assert (
                api.patch(
                    "/api/v1/admin/pass-plans/day",
                    json={"price_ugx": 100},
                    headers=as_user(admin),
                ).status_code
                == 422
            )
            assert (
                api.patch(
                    "/api/v1/admin/pass-plans/day",
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

    started = buy(api, user, "week", email=None, phone="0772 123 456")

    assert started["redirect_url"].startswith("https://cybqa.pesapal.com/")
    sent = fake.orders[tracking_of(fake, started["payment_id"])]
    assert sent["amount"] == 8000
    assert sent["currency"] == "UGX"
    assert sent["callback_url"] == f"{PUBLIC_API}/api/v1/passes/return"
    assert sent["notification_id"] == "ipn-1234-5678"
    assert sent["billing_address"]["phone_number"] == "+256772123456"
    state, amount, days = prices.execute(
        "select state, amount_ugx, days from public.payments where id = %s",
        (started["payment_id"],),
    ).fetchone()
    assert (state, amount, days) == ("pending", 8000, 7)


@needs_database
def test_a_checkout_needs_an_email_or_phone_and_pesapal(api, fake):
    user = uuid.uuid4()
    response = api.post(
        "/api/v1/passes/checkout", json={"plan_id": "day"}, headers=as_user(user)
    )
    assert response.status_code == 422
    assert (
        api.post(
            "/api/v1/passes/checkout",
            json={"plan_id": "day", "phone": "12"},
            headers=as_user(user),
        ).status_code
        == 422
    )

    fake.down = True
    response = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": "day", "email": "a@b.c"},
        headers=as_user(user),
    )
    assert response.status_code == 503
    fake.down = False
    fake.refuse_orders = True
    response = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": "day", "email": "a@b.c"},
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
            json={"plan_id": "day", "email": "a@b.c"},
            headers=as_user(uuid.uuid4()),
        )
    assert response.status_code == 503


# --- Pesapal's status --------------------------------------------------------


@needs_database
def test_a_completed_payment_makes_one_pass(api, fake, prices):
    user = uuid.uuid4()
    before = datetime.now(UTC)

    paid = pay(api, fake, user, "week")

    assert paid["state"] == "completed"
    ends = datetime.fromisoformat(paid["pass_ends_at"])
    assert timedelta(days=7) <= ends - before < timedelta(days=7, minutes=1)
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
    ("amount", "currency"), [(1999.0, "UGX"), (2000.0, "KES"), (2000.5, "USD")]
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
    first = pay(api, fake, user, "day")
    second = pay(api, fake, user, "week")

    first_end = datetime.fromisoformat(first["pass_ends_at"])
    assert datetime.fromisoformat(second["pass_ends_at"]) == first_end + timedelta(
        days=7
    )
    found = my_pass(api, user)
    assert datetime.fromisoformat(found["current_ends_at"]) == first_end
    assert datetime.fromisoformat(found["ends_at"]) == first_end + timedelta(days=7)


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
    assert "<script>" not in page.text
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
    response = grant(api, catalogue["movie"].item_id, uuid.uuid4())

    assert response.status_code == 402
    assert response.json()["detail"] == "You need a pass to watch."
    # A film that can't be watched anyway says so first.
    assert grant(api, uuid.uuid4(), uuid.uuid4()).status_code == 404


@needs_database
def test_a_grant_ends_no_later_than_the_pass(api, fake, prices, catalogue):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "day")
    prices.execute("update public.passes set ends_at = now() + interval '2 hours'")
    prices.execute("update public.passes set starts_at = ends_at - interval '1 day'")

    response = grant(api, catalogue["movie"].item_id, user)

    assert response.status_code == 200
    (ends,) = prices.execute("select ends_at from public.passes").fetchone()
    assert abs(expiry(response) - ends) < timedelta(seconds=1)
    assert claims(response)["e"] == int(ends.timestamp())

    # Once it has ended, the renewal is refused.
    prices.execute(
        "update public.passes set ends_at = now() - interval '1 minute', "
        "starts_at = now() - interval '1 day 1 minute'"
    )
    assert grant(api, catalogue["movie"].item_id, user).status_code == 402


@needs_database
def test_a_long_pass_still_gets_six_hour_grants(api, fake, prices, catalogue):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "week")

    response = grant(api, catalogue["movie"].item_id, user)

    left = expiry(response) - datetime.now(UTC)
    assert timedelta(hours=5, minutes=59) < left <= timedelta(hours=6)


@needs_database
def test_admins_and_passes_off_need_no_pass(app_url, fake, prices, catalogue):  # noqa: F811
    admin = uuid.uuid4()
    clear_admins(prices)
    prices.execute("insert into public.admins (user_id) values (%s)", (admin,))
    try:
        with TestClient(make_api(app_url, fake)) as api:
            assert grant(api, catalogue["movie"].item_id, admin).status_code == 200
        with TestClient(make_api(app_url, fake, passes_required=False)) as api:
            response = grant(api, catalogue["movie"].item_id, uuid.uuid4())
            assert response.status_code == 200
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
            insert into public.payments (user_id, plan_id, days, amount_ugx, email)
            values (%s, 'day', 1, 2000, 'a@b.c') returning id
            """,
            (user,),
        ).fetchone()
        conn.commit()
        for payment, days in ((pending, 1),):
            with pytest.raises(psycopg.errors.CheckViolation):
                conn.execute(
                    """
                    insert into public.passes (user_id, payment_id, starts_at, ends_at)
                    values (%s, %s, now(), now() + make_interval(days => %s))
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
                insert into public.passes (user_id, payment_id, starts_at, ends_at)
                values (%s, %s, now(), now() + interval '30 days')
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
