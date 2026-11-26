"""Payments for admins, Step 13H Phase 4: stale payments settled, the
overview's figures, transactions searched and exported, one payment's
timeline and re-check, and free days.

The database tests need a local test Postgres: see tests/db_support.py.
"""

# The owner fixture and others come from other test files; ruff reads each
# use of them as a parameter as redefining the import.
# ruff: noqa: F811

import csv
import io
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.pesapal import COMPLETED, FAILED
from tests.db_support import clear_admins, needs_database
from tests.test_database import as_user
from tests.test_passes import (  # noqa: F401
    buy,
    fake,
    make_api,
    my_pass,
    notify,
    pay,
    prices,
    refund,
    tracking_of,
)
from tests.test_viewer import owner  # noqa: F401

BILLING = "/api/v1/admin/billing"


@pytest.fixture
def admin_api(app_url, editor_url, fake, prices):
    """The API with its editor role and one admin, with the payment timeout
    at its default of 60 minutes. Answers (client, admin)."""
    admin = uuid.uuid4()
    clear_admins(prices)
    prices.execute(
        "insert into public.admins (user_id, email) values (%s, 'boss@example.com')",
        (admin,),
    )
    prices.execute("delete from public.pass_grants")
    try:
        with TestClient(make_api(app_url, fake, editor_url)) as client:
            yield client, admin
    finally:
        prices.execute("delete from public.passes where grant_id is not null")
        prices.execute("delete from public.pass_grants")
        clear_admins(prices)


def age(owner, payment_id, minutes: float) -> None:
    """Moves a payment's start back, as if it began that long ago."""
    owner.execute(
        "update public.payments set created_at = now() - make_interval(mins => %s) "
        "where id = %s",
        (minutes, payment_id),
    )


def state_of(owner, payment_id) -> tuple[str, str | None]:
    return owner.execute(
        "select state, reason from public.payments where id = %s", (payment_id,)
    ).fetchone()


def transactions(api, admin, **params):
    response = api.get(f"{BILLING}/transactions", params=params, headers=as_user(admin))
    assert response.status_code == 200, response.text
    return response.json()


def metrics(api, admin):
    response = api.get(f"{BILLING}/metrics", headers=as_user(admin))
    assert response.status_code == 200, response.text
    return response.json()


def never_sent(owner, user) -> uuid.UUID:
    """A payment that never reached Pesapal, left 'started'."""
    return owner.execute(
        """
        insert into public.payments (user_id, plan_id, days, amount_ugx, plan_name,
          max_devices, max_streams, email)
        select %s, id, days, price_ugx, display_name, max_devices, max_streams,
          'viewer@example.com'
        from public.pass_plans where id = 'velora_start'
        returning id
        """,
        (user,),
    ).fetchone()[0]


# --- Stale payments: the bug ------------------------------------------------------


@needs_database
def test_an_unpaid_payment_stops_showing_pending_once_it_has_expired(
    admin_api, fake, prices
):
    """The bug: a payment nobody paid stayed "pending" for ever, because it
    was only given up on when the viewer's app or Pesapal asked about it."""
    api, admin = admin_api
    user = uuid.uuid4()
    payment = buy(api, user)["payment_id"]
    age(prices, payment, 61)

    found = transactions(api, admin)

    assert [p["state"] for p in found["payments"]] == ["abandoned"]
    assert found["payments"][0]["reason"] == "Not paid within 1 hour"
    assert metrics(api, admin)["pending_now"] == 0
    # Pesapal was asked first, in case it was paid after all.
    asked = [r.url.path for r in fake.requests]
    assert any(p.endswith("/Transactions/GetTransactionStatus") for p in asked)


@needs_database
def test_a_recent_unpaid_payment_stays_pending(admin_api, fake, prices):
    api, admin = admin_api
    payment = buy(api, uuid.uuid4())["payment_id"]
    age(prices, payment, 30)

    assert [p["state"] for p in transactions(api, admin)["payments"]] == ["pending"]
    assert metrics(api, admin)["pending_now"] == 1


@needs_database
def test_a_stale_payment_paid_after_all_is_completed_with_its_pass(
    admin_api, fake, prices
):
    api, admin = admin_api
    user = uuid.uuid4()
    payment = buy(api, user)["payment_id"]
    age(prices, payment, 90)
    fake.statuses[tracking_of(fake, payment)] = COMPLETED

    metrics(api, admin)

    assert state_of(prices, payment)[0] == "completed"
    assert my_pass(api, user)["active"] is True


@needs_database
def test_a_payment_that_never_reached_pesapal_expires(admin_api, fake, prices):
    api, admin = admin_api
    payment = never_sent(prices, uuid.uuid4())
    age(prices, payment, 61)
    before = len(fake.requests)

    metrics(api, admin)

    assert state_of(prices, payment)[0] == "abandoned"
    # Nothing to ask Pesapal about.
    assert len(fake.requests) == before


@needs_database
def test_when_pesapal_is_down_stale_payments_wait_rather_than_guess(
    admin_api, fake, prices
):
    api, admin = admin_api
    payment = buy(api, uuid.uuid4())["payment_id"]
    age(prices, payment, 120)
    fake.down = True

    metrics(api, admin)
    assert state_of(prices, payment)[0] == "pending"

    fake.down = False
    metrics(api, admin)
    assert state_of(prices, payment)[0] == "abandoned"


@needs_database
def test_a_payment_paid_after_it_expired_is_honoured_by_pesapals_notice(
    admin_api, fake, prices
):
    api, admin = admin_api
    user = uuid.uuid4()
    payment = buy(api, user)["payment_id"]
    age(prices, payment, 61)
    metrics(api, admin)
    assert state_of(prices, payment)[0] == "abandoned"

    fake.statuses[tracking_of(fake, payment)] = COMPLETED
    assert notify(api, fake, payment).status_code == 200

    assert state_of(prices, payment)[0] == "completed"
    assert my_pass(api, user)["active"] is True


@needs_database
def test_the_timeout_is_a_setting(app_url, editor_url, fake, prices):
    admin = uuid.uuid4()
    clear_admins(prices)
    prices.execute("insert into public.admins (user_id) values (%s)", (admin,))
    try:
        with TestClient(
            make_api(app_url, fake, editor_url, payment_timeout_minutes=30)
        ) as api:
            payment = buy(api, uuid.uuid4())["payment_id"]
            age(prices, payment, 31)

            found = metrics(api, admin)

            assert found["payment_timeout_minutes"] == 30
            assert state_of(prices, payment) == (
                "abandoned",
                "Not paid within 30 minutes",
            )
    finally:
        clear_admins(prices)


# --- The overview -------------------------------------------------------------------


@needs_database
def test_the_overview_counts_money_success_and_passes_ending(admin_api, fake, prices):
    api, admin = admin_api
    paid = uuid.uuid4()
    pay(api, fake, paid)  # Velora Start: UGX 6,000, today.
    old = pay(api, fake, uuid.uuid4())
    prices.execute(
        "update public.payments set completed_at = now() - interval '10 days' "
        "where id = %s",
        (old["id"],),
    )
    pay(api, fake, uuid.uuid4(), code=FAILED)
    # Paid, then its pass is about to end.
    ending = uuid.uuid4()
    pay(api, fake, ending)
    prices.execute(
        "update public.passes set starts_at = now() - interval '6 days', "
        "ends_at = now() + interval '1 day' where user_id = %s",
        (ending,),
    )

    found = metrics(api, admin)

    assert found["revenue_today_ugx"] == 12_000
    assert found["revenue_7_days_ugx"] == 12_000
    assert found["revenue_30_days_ugx"] == 18_000
    # 3 paid of 4 settled.
    assert found["success_rate_30_days"] == 0.75
    assert found["ending_soon"] == 1
    assert len(found["daily"]) == 30
    assert found["daily"][-1]["revenue_ugx"] == 12_000
    assert found["daily"][-1]["completed"] == 2
    assert sum(d["revenue_ugx"] for d in found["daily"]) == 18_000


# --- Transactions -------------------------------------------------------------------


@needs_database
def test_transactions_are_filtered_searched_and_paged(admin_api, fake, prices):
    api, admin = admin_api
    first = pay(api, fake, uuid.uuid4())
    pay(api, fake, uuid.uuid4(), plan="velora_flex")
    failed = pay(api, fake, uuid.uuid4(), code=FAILED)
    prices.execute(
        "update public.payments set phone = '+256772123456' where id = %s",
        (failed["id"],),
    )

    assert transactions(api, admin)["total"] == 3
    assert [
        p["state"] for p in transactions(api, admin, state="failed")["payments"]
    ] == ["failed"]
    assert [
        p["plan_id"] for p in transactions(api, admin, plan="velora_flex")["payments"]
    ] == ["velora_flex"]
    tracking = tracking_of(fake, first["id"])
    assert [p["id"] for p in transactions(api, admin, q=tracking)["payments"]] == [
        first["id"]
    ]
    by_phone = transactions(api, admin, q="0772 123")["payments"]
    assert [p["id"] for p in by_phone] == [failed["id"]]
    # Contacts stay masked, even when searched for.
    assert by_phone[0]["contact"] == "v***@example.com"
    assert "772123" not in str(by_phone)
    today = datetime.now(UTC).date()
    assert transactions(api, admin, since=str(today + timedelta(days=1)))["total"] == 0
    assert transactions(api, admin, until=str(today + timedelta(days=1)))["total"] == 3
    page = transactions(api, admin, limit=2, offset=2)
    assert (len(page["payments"]), page["total"]) == (1, 3)


@needs_database
def test_transactions_export_as_a_safe_spreadsheet(admin_api, fake, prices):
    api, admin = admin_api
    expired = buy(api, uuid.uuid4())["payment_id"]
    age(prices, expired, 61)
    pay(api, fake, uuid.uuid4())
    prices.execute(
        "update public.payments set reason = '=HYPERLINK(\"x\")' where id = %s",
        (expired,),
    )

    # Opening Payments settles the stale one first.
    transactions(api, admin)
    response = api.get(f"{BILLING}/transactions.csv", headers=as_user(admin))

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/csv")
    assert "attachment" in response.headers["content-disposition"]
    rows = list(csv.DictReader(io.StringIO(response.text)))
    assert len(rows) == 2
    assert {r["state"] for r in rows} == {"completed", "expired"}
    assert all(r["contact"] == "v***@example.com" for r in rows)
    assert not any(r["reason"].startswith("=") for r in rows)
    assert (
        api.get(
            f"{BILLING}/transactions.csv", headers=as_user(uuid.uuid4())
        ).status_code
        == 403
    )


# --- One payment ----------------------------------------------------------------------


@needs_database
def test_a_payment_shows_its_steps_and_its_pass(admin_api, fake, prices):
    api, admin = admin_api
    paid = pay(api, fake, uuid.uuid4())
    assert refund(api, admin, paid["id"]).status_code == 200

    response = api.get(f"{BILLING}/payments/{paid['id']}", headers=as_user(admin))

    assert response.status_code == 200, response.text
    body = response.json()
    assert [s["step"] for s in body["timeline"]] == [
        "started",
        "sent",
        "completed",
        "refunded",
    ]
    assert body["timeline"][1]["at"] is None
    assert body["pass"]["payment_id"] == paid["id"]
    assert body["pass"]["revoked_at"] is not None
    assert body["refunded_by"] == str(admin)
    missing = api.get(f"{BILLING}/payments/{uuid.uuid4()}", headers=as_user(admin))
    assert missing.status_code == 404


@needs_database
def test_a_payment_is_rechecked_with_pesapal(admin_api, fake, prices):
    api, admin = admin_api
    user = uuid.uuid4()
    payment = buy(api, user)["payment_id"]
    age(prices, payment, 61)
    transactions(api, admin)
    assert state_of(prices, payment)[0] == "abandoned"
    fake.statuses[tracking_of(fake, payment)] = COMPLETED

    response = api.post(f"{BILLING}/payments/{payment}/recheck", headers=as_user(admin))

    assert response.status_code == 200, response.text
    assert response.json()["payment"]["state"] == "completed"
    assert my_pass(api, user)["active"] is True

    fake.down = True
    down = api.post(f"{BILLING}/payments/{payment}/recheck", headers=as_user(admin))
    assert down.status_code == 503
    fake.down = False
    unsent = never_sent(prices, uuid.uuid4())
    refused = api.post(f"{BILLING}/payments/{unsent}/recheck", headers=as_user(admin))
    assert refused.status_code == 409
    stranger = api.post(
        f"{BILLING}/payments/{payment}/recheck", headers=as_user(uuid.uuid4())
    )
    assert stranger.status_code == 403


# --- Free days ---------------------------------------------------------------


@needs_database
def test_free_days_start_a_pass_or_extend_one_and_never_count_as_money(
    admin_api, fake, prices
):
    api, admin = admin_api
    without, with_pass = uuid.uuid4(), uuid.uuid4()
    pay(api, fake, with_pass)
    revenue = metrics(api, admin)["revenue_30_days_ugx"]

    started = api.post(
        f"{BILLING}/users/{without}/grants",
        json={
            "plan_id": "velora_start",
            "days": 3,
            "reason": "  Sorry for the outage ",
        },
        headers=as_user(admin),
    )
    extended = api.post(
        f"{BILLING}/users/{with_pass}/grants",
        json={"plan_id": "velora_start", "days": 2, "reason": "Loyal viewer"},
        headers=as_user(admin),
    )

    assert started.status_code == 201, started.text
    granted = started.json()
    assert granted["payment_id"] is None and granted["grant_id"] is not None
    starts = datetime.fromisoformat(granted["starts_at"])
    assert abs(starts - datetime.now(UTC)) < timedelta(minutes=1)
    assert datetime.fromisoformat(granted["ends_at"]) - starts == timedelta(days=3)
    assert my_pass(api, without)["active"] is True
    # After the paid pass: an extension.
    paid_end = prices.execute(
        "select ends_at from public.passes "
        "where user_id = %s and payment_id is not null",
        (with_pass,),
    ).fetchone()[0]
    assert datetime.fromisoformat(extended.json()["starts_at"]) == paid_end
    found = metrics(api, admin)
    assert found["revenue_30_days_ugx"] == revenue
    assert found["granted_30_days"] == 2

    detail = api.get(f"{BILLING}/users/{without}", headers=as_user(admin)).json()
    assert [
        (g["days"], g["reason"], g["granted_by_email"]) for g in detail["grants"]
    ] == [(3, "Sorry for the outage", "boss@example.com")]
    assert detail["passes"][0]["plan_name"] == "Velora Start"
    assert detail["payments"] == []


@needs_database
def test_free_days_are_checked(admin_api, fake, prices):
    api, admin = admin_api
    target = uuid.uuid4()
    for body, status in [
        ({"plan_id": "no_such", "days": 3, "reason": "Because"}, 404),
        ({"plan_id": "velora_start", "days": 0, "reason": "Because"}, 422),
        ({"plan_id": "velora_start", "days": 91, "reason": "Because"}, 422),
        ({"plan_id": "velora_start", "days": 3, "reason": "  "}, 422),
        ({"plan_id": "velora_start", "days": 3}, 422),
    ]:
        response = api.post(
            f"{BILLING}/users/{target}/grants", json=body, headers=as_user(admin)
        )
        assert response.status_code == status, (body, response.text)
    stranger = api.post(
        f"{BILLING}/users/{target}/grants",
        json={"plan_id": "velora_start", "days": 3, "reason": "Because"},
        headers=as_user(uuid.uuid4()),
    )
    assert stranger.status_code == 403
    assert my_pass(api, target)["active"] is False


@needs_database
def test_subscribers_are_searched_and_those_ending_soon_found(admin_api, fake, prices):
    api, admin = admin_api
    ending, later = uuid.uuid4(), uuid.uuid4()
    pay(api, fake, ending)
    pay(api, fake, later, plan="velora_prime")
    prices.execute(
        "update public.passes set starts_at = now() - interval '6 days', "
        "ends_at = now() + interval '1 day' where user_id = %s",
        (ending,),
    )

    def found(**params):
        response = api.get(
            f"{BILLING}/subscribers", params=params, headers=as_user(admin)
        )
        assert response.status_code == 200, response.text
        return [s["user_id"] for s in response.json()]

    assert found() == [str(ending), str(later)]
    assert found(ending_within_days=3) == [str(ending)]
    assert found(q=str(later)) == [str(later)]
    assert found(q="viewer@example") == [str(ending), str(later)]
