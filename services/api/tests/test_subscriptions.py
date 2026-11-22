# Fixtures imported from test_passes are used as test arguments.
# ruff: noqa: F811
"""Milestone 10: six tiers, queued passes, devices, playback sessions, the
media gateway's session check, admin billing and the database's own rules.

On a real Postgres with Pesapal faked. Skipped without a local test
Postgres: see tests/db_support.py.
"""

import json
import logging
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from importlib import import_module

import psycopg
import pytest
from fastapi.testclient import TestClient

from app import audit, ratelimit
from app.pesapal import COMPLETED, FAILED, REVERSED
from app.playback import sign_gateway_check
from app.ratelimit import Limit
from tests.db_support import clear_admins, needs_database
from tests.test_database import as_user
from tests.test_passes import (  # noqa: F401
    api,
    buy,
    catalogue,
    claims,
    fake,
    make_api,
    my_pass,
    owner,
    pay,
    prices,
    tracking_of,
)
from tests.test_viewer import KEY

PLANS = "/api/v1/passes/plans"
MIGRATION = import_module("migrations.versions.0007_subscriptions")


# --- Helpers -----------------------------------------------------------------


def register(api, user, credential=None, label="Phone", platform="android"):
    headers = as_user(user)
    if credential:
        headers["X-Velora-Device"] = credential
    return api.post(
        "/api/v1/me/devices",
        json={"label": label, "platform": platform},
        headers=headers,
    )


def new_device(api, user, label="Phone") -> str:
    response = register(api, user, label=label)
    assert response.status_code == 201, response.text
    return response.json()["credential"]


def device_id(credential: str) -> str:
    return credential.split(".")[0]


def watch(api, item_id, user, credential=None):
    headers = as_user(user)
    if credential:
        headers["X-Velora-Device"] = credential
    return api.post(f"/api/v1/items/{item_id}/playback", headers=headers)


def gateway(api, session_id, *, signature=None):
    if signature is None:
        now = int(datetime.now(UTC).timestamp())
        signature = sign_gateway_check(KEY.encode(), uuid.UUID(session_id), now + 60)
    return api.get(
        f"/api/v1/gateway/sessions/{session_id}",
        headers={"X-Velora-Gateway": signature},
    )


def live(api, session_id) -> bool:
    response = gateway(api, session_id)
    assert response.status_code == 200, response.text
    return response.json()["live"]


def heartbeat(api, user, session_id, credential):
    return api.post(
        f"/api/v1/me/playback-sessions/{session_id}/heartbeat",
        headers=as_user(user) | {"X-Velora-Device": credential},
    )


def code(response) -> str | None:
    detail = response.json().get("detail")
    return detail.get("code") if isinstance(detail, dict) else None


def end_passes_now(conn, user) -> None:
    """As the owner, by hand, as the 10E run sheet does."""
    conn.execute(
        "update public.passes set starts_at = now() - (ends_at - starts_at) "
        "- interval '1 minute', ends_at = now() - interval '1 minute' "
        "where user_id = %s and starts_at <= now()",
        (user,),
    )


@pytest.fixture
def item(catalogue):  # noqa: F811
    return catalogue["movie"].item_id


@pytest.fixture
def admin(prices):  # noqa: F811
    user = uuid.uuid4()
    clear_admins(prices)
    prices.execute("insert into public.admins (user_id) values (%s)", (user,))
    yield user
    clear_admins(prices)


# --- The catalogue -----------------------------------------------------------


@needs_database
def test_the_six_tiers_are_for_sale_with_their_prices(api):
    plans = api.get(PLANS).json()
    assert [
        (p["id"], p["display_name"], p["price_ugx"], p["days"], p["max_devices"])
        for p in plans
    ] == [
        ("velora_start", "Velora Start", 6000, 7, 1),
        ("velora_flex", "Velora Flex", 10000, 14, 1),
        ("velora_prime", "Velora Prime", 18000, 30, 1),
        ("velora_duo", "Velora Duo", 50000, 90, 2),
        ("velora_pro", "Velora Pro", 90000, 180, 2),
        ("velora_max", "Velora Max", 150000, 365, 3),
    ]
    assert [p["id"] for p in plans if p["featured"]] == ["velora_prime"]
    assert all(p["max_streams"] == p["max_devices"] <= 3 for p in plans)


@needs_database
def test_legacy_passes_stay_but_cant_be_bought(app_url, editor_url, fake, admin):  # noqa: F811
    with TestClient(make_api(app_url, fake, editor_url)) as api:  # noqa: F811
        listed = api.get("/api/v1/admin/pass-plans", headers=as_user(admin)).json()
        legacy = [(p["id"], p["days"], p["for_sale"]) for p in listed if p["legacy"]]
        assert legacy == [("day", 1, False), ("week", 7, False), ("month", 30, False)]
        checkout = api.post(
            "/api/v1/passes/checkout",
            json={"plan_id": "day", "email": "a@b.c"},
            headers=as_user(uuid.uuid4()),
        )
        assert checkout.status_code == 409
        back = api.patch(
            "/api/v1/admin/pass-plans/day",
            json={"price_ugx": 1000, "for_sale": True},
            headers=as_user(admin),
        )
        assert back.status_code == 409


@needs_database
def test_the_seed_is_idempotent_and_keeps_admins_prices(prices):  # noqa: F811
    prices.execute(
        "update public.pass_plans set price_ugx = 20000 where id = 'velora_prime'"
    )
    prices.execute(MIGRATION._seed())
    prices.execute(MIGRATION._seed())
    rows = prices.execute(
        "select id, price_ugx from public.pass_plans where not legacy order by id"
    ).fetchall()
    assert len(rows) == 6
    assert dict(rows)["velora_prime"] == 20000


@needs_database
def test_admin_plan_changes_are_recorded_and_one_is_featured(
    app_url,
    editor_url,
    fake,  # noqa: F811
    admin,
    prices,  # noqa: F811
):
    with TestClient(make_api(app_url, fake, editor_url)) as api:  # noqa: F811
        headers = as_user(admin)
        featured = api.patch(
            "/api/v1/admin/pass-plans/velora_max",
            json={"featured": True},
            headers=headers,
        )
        assert featured.status_code == 200, featured.text
        plans = api.get(PLANS).json()
        assert [p["id"] for p in plans if p["featured"]] == ["velora_max"]
        off = api.patch(
            "/api/v1/admin/pass-plans/velora_flex",
            json={"for_sale": False},
            headers=headers,
        )
        assert off.json()["for_sale"] is False
        assert "velora_flex" not in [p["id"] for p in api.get(PLANS).json()]
        history = api.get("/api/v1/admin/billing/plan-changes", headers=headers).json()
        changed = {
            (h["plan_id"], h["new_featured"], h["new_for_sale"]) for h in history
        }
        assert ("velora_max", True, True) in changed
        assert ("velora_prime", False, True) in changed
        assert ("velora_flex", False, False) in changed
        assert all(h["changed_by"] == str(admin) for h in history)


# --- What was bought ---------------------------------------------------------


@needs_database
def test_a_payment_keeps_what_was_bought_after_a_price_change(api, fake, prices):  # noqa: F811
    user = uuid.uuid4()
    started = buy(api, user, "velora_duo")
    prices.execute(
        "update public.pass_plans set price_ugx = 55000 where id = 'velora_duo'"
    )
    fake.statuses[tracking_of(fake, started["payment_id"])] = COMPLETED
    fake.amounts[tracking_of(fake, started["payment_id"])] = 50000
    paid = api.get(
        f"/api/v1/passes/payments/{started['payment_id']}", headers=as_user(user)
    ).json()

    assert paid["state"] == "completed"
    assert paid["plan_name"] == "Velora Duo"
    row = prices.execute(
        "select p.amount_ugx, p.max_devices, s.max_devices, s.max_streams, s.plan_id "
        "from public.payments p join public.passes s on s.payment_id = p.id"
    ).fetchone()
    assert row == (50000, 2, 2, 2, "velora_duo")


@needs_database
def test_the_api_roles_cant_rewrite_a_payment(app_url, editor_url, api, fake, prices):  # noqa: F811
    user = uuid.uuid4()
    paid = pay(api, fake, user, "velora_prime")
    with psycopg.connect(app_url) as conn:
        conn.execute("select set_config('app.user_id', %s, false)", (str(user),))
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            conn.execute("update public.payments set amount_ugx = 500")
        conn.rollback()
        conn.execute("select set_config('app.user_id', %s, false)", (str(user),))
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            conn.execute("delete from public.payments")
        conn.rollback()
        # Moving a pass that has started, even through allowed columns.
        conn.execute("select set_config('app.user_id', %s, false)", (str(user),))
        with pytest.raises(psycopg.errors.CheckViolation):
            conn.execute(
                "update public.passes set ends_at = ends_at + interval '9 days'"
            )
        conn.rollback()
    with psycopg.connect(editor_url) as conn:
        for statement in (
            "update public.payments set state = 'completed'",
            "update public.passes set ends_at = now()",
            "delete from public.payments",
            "delete from public.plan_changes",
        ):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                conn.execute(statement)
            conn.rollback()
    assert paid["state"] == "completed"


@needs_database
def test_the_database_refuses_a_payment_that_doesnt_match_its_plan(app_url, prices):  # noqa: F811
    user = uuid.uuid4()
    with psycopg.connect(app_url) as conn:
        for price, devices in ((6000, 3), (100, 1), (6000, 1)):
            conn.execute("select set_config('app.user_id', %s, false)", (str(user),))
            statement = """
                insert into public.payments (user_id, plan_id, days, amount_ugx,
                  email, plan_name, max_devices, max_streams)
                values (%s, 'velora_start', 7, %s, 'a@b.c', 'Velora Start', %s, 1)
            """
            if (price, devices) == (6000, 1):
                conn.execute(statement, (user, price, devices))
                conn.rollback()
                continue
            with pytest.raises(psycopg.errors.CheckViolation):
                conn.execute(statement, (user, price, devices))
            conn.rollback()


# --- Payment lifecycle ---------------------------------------------------------


@needs_database
def test_duplicate_notifications_and_polls_at_once_make_one_pass(api, fake, prices):  # noqa: F811
    user = uuid.uuid4()
    started = buy(api, user, "velora_prime")
    tracking = tracking_of(fake, started["payment_id"])
    fake.statuses[tracking] = COMPLETED

    def notify(_):
        return api.get("/api/v1/passes/ipn", params={"OrderTrackingId": tracking})

    def poll(_):
        return api.get(
            f"/api/v1/passes/payments/{started['payment_id']}", headers=as_user(user)
        )

    with ThreadPoolExecutor(max_workers=8) as pool:
        answers = list(pool.map(lambda i: (notify if i % 2 else poll)(i), range(16)))

    assert all(a.status_code == 200 for a in answers)
    assert prices.execute("select count(*) from public.passes").fetchone() == (1,)
    assert my_pass(api, user)["current"]["plan_id"] == "velora_prime"


@needs_database
def test_a_retried_checkout_reuses_the_same_payment(api, fake, prices):  # noqa: F811
    user = uuid.uuid4()
    first = buy(api, user, "velora_flex")
    again = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": "velora_flex", "email": "viewer@example.com"},
        headers=as_user(user),
    )
    assert again.status_code == 200
    assert again.json() == first
    assert len(fake.orders) == 1
    # Another plan is another payment.
    buy(api, user, "velora_prime")
    assert len(fake.orders) == 2


@needs_database
def test_checkouts_and_payment_checks_are_rate_limited(
    api,
    fake,
    prices,
    monkeypatch,  # noqa: F811
):
    monkeypatch.setattr(ratelimit, "PAYMENT_STATUS", Limit(3, 60))
    user = uuid.uuid4()
    fake.refuse_orders = True
    codes = [
        api.post(
            "/api/v1/passes/checkout",
            json={"plan_id": "velora_start", "email": "a@b.c"},
            headers=as_user(user),
        ).status_code
        for _ in range(ratelimit.CHECKOUT.count + 1)
    ]
    assert codes[:-1] == [502] * ratelimit.CHECKOUT.count
    assert codes[-1] == 429
    # Another viewer isn't held back.
    fake.refuse_orders = False
    other = uuid.uuid4()
    payment = buy(api, other)
    path = f"/api/v1/passes/payments/{payment['payment_id']}"
    checks = [api.get(path, headers=as_user(other)) for _ in range(4)]
    assert [c.status_code for c in checks] == [200, 200, 200, 429]
    assert int(checks[-1].headers["Retry-After"]) >= 1


@needs_database
def test_failed_then_given_up_payments_make_no_pass(api, fake, prices):  # noqa: F811
    user = uuid.uuid4()
    failed = pay(api, fake, user, "velora_start", code=FAILED)
    assert failed["state"] == "failed"
    assert my_pass(api, user)["active"] is False
    history = api.get("/api/v1/me/payments", headers=as_user(user)).json()
    assert [(p["state"], p["provider_reference"]) for p in history] == [
        ("failed", None)
    ]


@needs_database
def test_a_reversal_moves_the_queued_pass_up(api, fake, prices):  # noqa: F811
    user = uuid.uuid4()
    first = pay(api, fake, user, "velora_prime")
    pay(api, fake, user, "velora_duo")
    queued = my_pass(api, user)["queued"]
    assert [q["plan_id"] for q in queued] == ["velora_duo"]

    fake.statuses[tracking_of(fake, str(first["id"]))] = REVERSED
    api.get(
        "/api/v1/passes/ipn",
        params={"OrderTrackingId": tracking_of(fake, str(first["id"]))},
    )

    found = my_pass(api, user)
    assert found["current"]["plan_id"] == "velora_duo"
    assert found["queued"] == []
    starts = datetime.fromisoformat(found["current"]["starts_at"])
    assert datetime.now(UTC) - starts < timedelta(minutes=1)
    ends = datetime.fromisoformat(found["current"]["ends_at"])
    assert ends - starts == timedelta(days=90)
    states = dict(
        prices.execute("select plan_id, state from public.payments").fetchall()
    )
    assert states == {"velora_prime": "reversed", "velora_duo": "completed"}


# --- Queued tiers --------------------------------------------------------------


@needs_database
def test_a_different_tier_is_queued_with_its_own_allowances(api, fake, prices, item):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_prime")
    pay(api, fake, user, "velora_max")

    found = my_pass(api, user)
    current, queued = found["current"], found["queued"]
    assert (current["plan_id"], current["max_devices"]) == ("velora_prime", 1)
    assert [(q["plan_id"], q["max_devices"], q["max_streams"]) for q in queued] == [
        ("velora_max", 3, 3)
    ]
    assert queued[0]["starts_at"] == current["ends_at"]
    # The running pass decides: one device, not four.
    new_device(api, user)
    refused = register(api, user, label="Laptop")
    assert refused.status_code == 409
    assert code(refused) == "device_limit"
    assert refused.json()["detail"]["limit"] == 1

    # Once Prime ends, Max's three devices apply.
    end_passes_now(prices, user)
    prices.execute(
        "update public.passes set starts_at = now() - interval '1 second', "
        "ends_at = now() - interval '1 second' + interval '365 days' "
        "where user_id = %s and plan_id = 'velora_max'",
        (user,),
    )
    assert my_pass(api, user)["current"]["plan_id"] == "velora_max"
    assert register(api, user, label="Laptop").status_code == 201


@needs_database
def test_an_expired_pass_stops_playback_and_renewal_restores_it(
    api,
    fake,
    prices,
    item,  # noqa: F811
):
    user = uuid.uuid4()
    pay(api, fake, user, "velora_start")
    phone = new_device(api, user)
    first = watch(api, item, user, phone)
    assert first.status_code == 200, first.text
    session = first.json()["session_id"]
    assert live(api, session)

    end_passes_now(prices, user)

    assert not live(api, session)
    assert heartbeat(api, user, session, phone).status_code == 402
    assert watch(api, item, user, phone).status_code == 402

    pay(api, fake, user, "velora_flex")
    renewed = watch(api, item, user, phone)
    assert renewed.status_code == 200
    assert live(api, renewed.json()["session_id"])


# --- Devices -------------------------------------------------------------------


@needs_database
def test_without_a_pass_one_device_can_register(api, prices):  # noqa: F811
    user = uuid.uuid4()
    first = register(api, user)
    assert first.status_code == 201
    body = first.json()
    assert body["device"]["current"] is True
    assert body["credential"].startswith(body["device"]["id"] + ".")
    assert code(register(api, user, label="Laptop")) == "device_limit"
    listed = api.get(
        "/api/v1/me/devices",
        headers=as_user(user) | {"X-Velora-Device": body["credential"]},
    ).json()
    assert listed["allowed"] == 1
    assert [d["current"] for d in listed["devices"]] == [True]


@needs_database
def test_registering_again_from_the_same_device_is_one_device(api, fake, prices):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_max")
    credential = new_device(api, user)
    again = register(api, user, credential=credential)
    assert again.status_code == 200
    assert again.json()["credential"] is None
    assert again.json()["device"]["id"] == device_id(credential)
    assert prices.execute("select count(*) from public.devices").fetchone() == (1,)


@needs_database
def test_max_allows_three_devices_and_never_a_fourth(api, fake, prices, app_url):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_max")
    for label in ("Phone", "Laptop", "TV"):
        new_device(api, user, label)
    fourth = register(api, user, label="Tablet")
    assert fourth.status_code == 409
    assert code(fourth) == "device_limit"
    # The database refuses a fourth too, whatever the API does.
    with psycopg.connect(app_url) as conn:
        conn.execute("select set_config('app.user_id', %s, false)", (str(user),))
        with pytest.raises(psycopg.errors.CheckViolation):
            conn.execute(
                "insert into public.devices (user_id, secret_hash, label, platform) "
                "values (%s, sha256('x'::bytea), 'Sneaky', 'web')",
                (user,),
            )


@needs_database
def test_registrations_at_the_same_moment_cant_pass_the_limit(api, fake, prices):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_max")

    with ThreadPoolExecutor(max_workers=8) as pool:
        answers = list(
            pool.map(lambda i: register(api, user, label=f"Device {i}"), range(8))
        )

    assert sorted(a.status_code for a in answers).count(201) == 3
    assert {a.status_code for a in answers} == {201, 409}
    (count,) = prices.execute(
        "select count(*) from public.devices where revoked_at is null"
    ).fetchone()
    assert count == 3


@needs_database
def test_device_switching_is_limited(api, fake, prices):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_prime")
    # The plan's one device, then three replacements for lost or broken ones.
    for _ in range(4):
        credential = new_device(api, user)
        removed = api.delete(
            f"/api/v1/me/devices/{device_id(credential)}", headers=as_user(user)
        )
        assert removed.status_code == 204
    fifth = register(api, user)
    assert fifth.status_code == 429
    assert code(fifth) == "device_switch_limit"


@needs_database
def test_devices_can_be_renamed_and_listed_most_recent_first(api, fake, prices):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_duo")
    phone = new_device(api, user, "Phone")
    renamed = api.patch(
        f"/api/v1/me/devices/{device_id(phone)}",
        json={"label": "  Sarah's phone "},
        headers=as_user(user) | {"X-Velora-Device": phone},
    )
    assert renamed.json()["label"] == "Sarah's phone"
    assert renamed.json()["current"] is True
    assert (
        api.patch(
            f"/api/v1/me/devices/{device_id(phone)}",
            json={"label": ""},
            headers=as_user(user),
        ).status_code
        == 422
    )


# --- Forged and foreign devices ----------------------------------------------


@needs_database
def test_forged_device_credentials_are_refused(api, fake, prices, item):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_prime")
    real = new_device(api, user)
    real_id, real_secret = real.split(".")
    for forged in (
        None,
        "nonsense",
        f"{uuid.uuid4()}.{real_secret}",
        f"{real_id}.{'A' * 43}",
        f"{real_id}.{real_secret}x",
    ):
        response = watch(api, item, user, forged)
        assert response.status_code in (403, 422), forged
        if response.status_code == 403:
            assert code(response) == "device_required"
    assert watch(api, item, user, real).status_code == 200


@needs_database
def test_another_accounts_device_and_sessions_are_out_of_reach(
    api,
    fake,
    prices,
    item,  # noqa: F811
):
    mine, theirs = uuid.uuid4(), uuid.uuid4()
    pay(api, fake, mine, "velora_prime")
    pay(api, fake, theirs, "velora_prime")
    their_device = new_device(api, theirs)
    their_session = watch(api, item, theirs, their_device).json()["session_id"]

    # Their credential doesn't make it my device.
    stolen = watch(api, item, mine, their_device)
    assert stolen.status_code == 403
    assert code(stolen) == "device_required"
    assert (
        api.delete(
            f"/api/v1/me/devices/{device_id(their_device)}", headers=as_user(mine)
        ).status_code
        == 404
    )
    assert (
        api.delete(
            f"/api/v1/me/playback-sessions/{their_session}", headers=as_user(mine)
        ).status_code
        == 404
    )
    assert api.get("/api/v1/me/devices", headers=as_user(mine)).json()["devices"] == []
    assert api.get("/api/v1/me/playback-sessions", headers=as_user(mine)).json() == []
    assert live(api, their_session)


# --- Sessions ------------------------------------------------------------------


@needs_database
def test_a_grant_is_bound_to_a_live_session(api, fake, prices, item):  # noqa: F811
    user = uuid.uuid4()
    pass_ = pay(api, fake, user, "velora_prime")
    phone = new_device(api, user)
    response = watch(api, item, user, phone)
    body = response.json()

    assert body["heartbeat_seconds"] == 60
    assert claims(response)["s"] == body["session_id"]
    assert claims(response)["e"] <= int(datetime.now(UTC).timestamp()) + 3600
    answer = gateway(api, body["session_id"]).json()
    assert answer["live"] is True
    assert answer["until"] == int(
        datetime.fromisoformat(pass_["pass_ends_at"]).timestamp()
    )
    assert heartbeat(api, user, body["session_id"], phone).json() == {"live": True}
    sessions = api.get(
        "/api/v1/me/playback-sessions",
        headers=as_user(user) | {"X-Velora-Device": phone},
    ).json()
    assert [(s["id"], s["current_device"]) for s in sessions] == [
        (body["session_id"], True)
    ]


@needs_database
def test_a_new_grant_on_the_same_device_replaces_its_session(api, fake, prices, item):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_prime")
    phone = new_device(api, user)
    first = watch(api, item, user, phone).json()["session_id"]
    second = watch(api, item, user, phone).json()["session_id"]

    assert first != second
    # The old grant is useless now: replaying it gets nothing.
    assert not live(api, first)
    assert live(api, second)
    assert heartbeat(api, user, first, phone).status_code == 410


@needs_database
def test_the_stream_limit_and_stopping_another_device(api, fake, prices, item):  # noqa: F811
    # A plan with two devices but one stream, to reach the stream limit.
    prices.execute(
        "update public.pass_plans set max_streams = 1 where id = 'velora_duo'"
    )
    user = uuid.uuid4()
    pay(api, fake, user, "velora_duo")
    phone, laptop = new_device(api, user, "Phone"), new_device(api, user, "Laptop")
    playing = watch(api, item, user, phone).json()["session_id"]

    refused = watch(api, item, user, laptop)
    assert refused.status_code == 409
    assert code(refused) == "stream_limit"
    detail = refused.json()["detail"]
    assert detail["limit"] == 1
    assert [s["device_label"] for s in detail["sessions"]] == ["Phone"]

    stopped = api.delete(
        f"/api/v1/me/playback-sessions/{playing}", headers=as_user(user)
    )
    assert stopped.status_code == 204
    assert not live(api, playing)
    assert watch(api, item, user, laptop).status_code == 200
    prices.execute(
        "update public.pass_plans set max_streams = 2 where id = 'velora_duo'"
    )


@needs_database
def test_concurrent_grants_never_exceed_the_streams(api, fake, prices, item):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_duo")
    phone, laptop = new_device(api, user, "Phone"), new_device(api, user, "Laptop")

    with ThreadPoolExecutor(max_workers=6) as pool:
        answers = list(
            pool.map(lambda i: watch(api, item, user, (phone, laptop)[i % 2]), range(6))
        )

    assert all(a.status_code == 200 for a in answers)
    (count,) = prices.execute(
        "select count(*) from public.playback_sessions where ended_at is null"
    ).fetchone()
    assert count == 2


@needs_database
def test_an_idle_session_lapses_and_frees_its_stream(api, fake, prices, item):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_prime")
    phone = new_device(api, user)
    session = watch(api, item, user, phone).json()["session_id"]
    prices.execute(
        "update public.playback_sessions "
        "set last_seen_at = now() - interval '4 minutes'"
    )
    assert not live(api, session)
    assert heartbeat(api, user, session, phone).status_code == 410
    assert api.get("/api/v1/me/playback-sessions", headers=as_user(user)).json() == []


@needs_database
def test_removing_a_device_ends_its_playback_at_once(api, fake, prices, item):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_duo")
    phone, laptop = new_device(api, user, "Phone"), new_device(api, user, "Laptop")
    session = watch(api, item, user, phone).json()["session_id"]

    removed = api.delete(
        f"/api/v1/me/devices/{device_id(phone)}",
        headers=as_user(user) | {"X-Velora-Device": laptop},
    )

    assert removed.status_code == 204
    assert not live(api, session)
    assert heartbeat(api, user, session, phone).status_code == 403
    again = watch(api, item, user, phone)
    assert again.status_code == 403 and code(again) == "device_required"
    (reason,) = prices.execute(
        "select end_reason from public.playback_sessions where id = %s", (session,)
    ).fetchone()
    assert reason == "device_removed"


@needs_database
def test_a_smaller_plan_asks_which_devices_to_keep(api, fake, prices, item):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_max")
    devices = [new_device(api, user, label) for label in ("Phone", "Laptop", "TV")]
    pay(api, fake, user, "velora_start")
    # Max ends; Start, one device, takes over.
    end_passes_now(prices, user)
    prices.execute(
        "update public.passes set starts_at = now() - interval '1 second', "
        "ends_at = now() - interval '1 second' + interval '7 days' "
        "where user_id = %s and plan_id = 'velora_start'",
        (user,),
    )
    listed = api.get("/api/v1/me/devices", headers=as_user(user)).json()
    assert (listed["allowed"], listed["over_limit"]) == (1, True)
    refused = watch(api, item, user, devices[0])
    assert refused.status_code == 409 and code(refused) == "device_limit"

    for credential in devices[1:]:
        api.delete(f"/api/v1/me/devices/{device_id(credential)}", headers=as_user(user))

    assert watch(api, item, user, devices[0]).status_code == 200


# --- The media gateway's question ----------------------------------------------


@needs_database
def test_only_the_gateway_can_ask_about_a_session(api, fake, prices, item):  # noqa: F811
    user = uuid.uuid4()
    pay(api, fake, user, "velora_prime")
    session = watch(api, item, user, new_device(api, user)).json()["session_id"]
    now = int(datetime.now(UTC).timestamp())
    other = str(uuid.uuid4())
    for signature in (
        "",
        "nonsense",
        sign_gateway_check(
            b"another-key-entirely-but-long-enough", uuid.UUID(session), now + 60
        ),
        sign_gateway_check(KEY.encode(), uuid.UUID(other), now + 60),
        sign_gateway_check(KEY.encode(), uuid.UUID(session), now - 1),
        sign_gateway_check(KEY.encode(), uuid.UUID(session), now + 3600),
    ):
        assert gateway(api, session, signature=signature).status_code == 401
    assert live(api, session)
    assert live(api, other) is False


# --- Admins ----------------------------------------------------------------------


@needs_database
def test_admin_billing_views(app_url, editor_url, fake, admin, prices, item):  # noqa: F811
    with TestClient(make_api(app_url, fake, editor_url)) as api:  # noqa: F811
        viewer = uuid.uuid4()
        pay(api, fake, viewer, "velora_duo")
        pay(api, fake, uuid.uuid4(), "velora_start", code=FAILED)
        phone = new_device(api, viewer)
        session = watch(api, item, viewer, phone).json()["session_id"]
        headers = as_user(admin)

        metrics = api.get("/api/v1/admin/billing/metrics", headers=headers).json()
        assert metrics["active_subscribers"] == 1
        assert metrics["by_plan"] == [
            {"plan_id": "velora_duo", "plan_name": "Velora Duo", "subscribers": 1}
        ]
        assert metrics["revenue_30_days_ugx"] == 50000
        assert metrics["failed_30_days"] == 1
        assert metrics["live_sessions"] == 1

        failed = api.get(
            "/api/v1/admin/billing/payments",
            params={"state": "failed"},
            headers=headers,
        ).json()
        assert [p["plan_id"] for p in failed] == ["velora_start"]
        assert failed[0]["contact"] == "v***@example.com"

        subs = api.get("/api/v1/admin/billing/subscribers", headers=headers).json()
        assert [(s["user_id"], s["active_devices"]) for s in subs] == [(str(viewer), 1)]

        detail = api.get(
            f"/api/v1/admin/billing/users/{viewer}", headers=headers
        ).json()
        assert [p["plan_id"] for p in detail["passes"]] == ["velora_duo"]
        assert [d["id"] for d in detail["devices"]] == [device_id(phone)]

        removed = api.delete(
            f"/api/v1/admin/billing/users/{viewer}/devices/{device_id(phone)}",
            headers=headers,
        )
        assert removed.status_code == 204
        assert not live(api, session)

        for path in ("metrics", "payments", "subscribers", "plan-changes"):
            refused = api.get(f"/api/v1/admin/billing/{path}", headers=as_user(viewer))
            assert refused.status_code == 403, path


# --- Audit -----------------------------------------------------------------------


def test_audit_events_drop_anything_not_allowed(caplog):
    with caplog.at_level(logging.INFO, logger="veloraug.audit"):
        record = audit.event(
            "payment.started",
            payment_id=uuid.UUID(int=1),
            email="someone@example.com",
            phone="+256772000000",
            secret="x",
            amount_ugx=6000,
        )
    assert record == {
        "event": "payment.started",
        "payment_id": str(uuid.UUID(int=1)),
        "amount_ugx": 6000,
    }
    logged = json.loads(caplog.records[-1].getMessage())
    assert logged == record
    assert "example.com" not in caplog.text


@needs_database
def test_payment_audit_never_names_the_customer(api, fake, prices, caplog):  # noqa: F811
    with caplog.at_level(logging.INFO, logger="veloraug.audit"):
        pay(api, fake, uuid.uuid4(), "velora_prime")
    events = [json.loads(r.getMessage())["event"] for r in caplog.records]
    assert "payment.started" in events and "payment.completed" in events
    assert "viewer@example.com" not in caplog.text


# --- The preflight before 0007 -----------------------------------------------


@needs_database
def test_the_preflight_passes_at_0006_and_refuses_at_0007(owner_url, app_url):
    from scripts.preflight_0007 import checks
    from tests.db_support import migrate

    migrate(owner_url, "0006", down=True)
    try:
        with psycopg.connect(owner_url) as conn:
            results = checks(conn)
            conn.rollback()
        assert all(passed for _, passed, _ in results), results
    finally:
        migrate(owner_url)
    with psycopg.connect(owner_url) as conn:
        failed = [name for name, passed, _ in checks(conn) if not passed]
    assert "the database is at 0006" in failed
