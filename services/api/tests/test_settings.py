"""Settings, Step 13H Phase 5: checked, saved, reset, and obeyed: support
contacts and maintenance in the app, the payment timeout, pass reminders,
and the language of new drafts.

The database tests need a local test Postgres: see tests/db_support.py.
"""

# Fixtures come from other test files; ruff reads each use of them as a
# parameter as redefining the import.
# ruff: noqa: F811

import logging
import uuid

import pytest
from fastapi.testclient import TestClient

from app.app_settings import SETTINGS, SettingError
from tests.db_support import clear_admins, delete_editions, needs_database
from tests.test_admin_payments import age, state_of
from tests.test_database import as_user
from tests.test_passes import buy, fake, make_api, pay, prices  # noqa: F401
from tests.test_viewer import owner  # noqa: F401

SETTINGS_URL = "/api/v1/admin/settings"


# --- Without a database ---------------------------------------------------------


@pytest.mark.parametrize(
    ("key", "given", "saved"),
    [
        ("support_email", "  help@veloraug.ug ", "help@veloraug.ug"),
        ("support_email", "", ""),
        ("support_phone", "+256 772-123 456", "+256772123456"),
        ("support_whatsapp", "+256772123456", "+256772123456"),
        ("maintenance", True, True),
        ("maintenance_message", "  Back at 6pm. ", "Back at 6pm."),
        ("payment_timeout_minutes", 30, 30),
        ("pass_reminder_days", 14, 14),
        ("default_language", "nyn", "nyn"),
    ],
)
def test_good_values_are_tidied(key, given, saved):
    assert SETTINGS[key].check(given) == saved


@pytest.mark.parametrize(
    ("key", "given"),
    [
        ("support_email", "not an email"),
        ("support_phone", "0772123456"),
        ("support_whatsapp", "+12"),
        ("maintenance", "yes"),
        ("maintenance_message", "x" * 301),
        ("payment_timeout_minutes", 4),
        ("payment_timeout_minutes", 1441),
        ("payment_timeout_minutes", True),
        ("pass_reminder_days", 0),
        ("default_language", "Luganda"),
    ],
)
def test_bad_values_are_refused(key, given):
    with pytest.raises(SettingError):
        SETTINGS[key].check(given)


# --- With a database ---------------------------------------------------------------


@pytest.fixture
def admin_api(app_url, editor_url, fake, prices):
    """The API with its editor role and one admin, and no settings stored.
    Answers (client, admin)."""
    admin = uuid.uuid4()
    clear_admins(prices)
    prices.execute("insert into public.admins (user_id) values (%s)", (admin,))
    prices.execute("delete from public.app_settings")
    try:
        with TestClient(make_api(app_url, fake, editor_url)) as client:
            yield client, admin
    finally:
        prices.execute("delete from public.app_settings")
        prices.execute("delete from public.languages where code <> 'lg'")
        clear_admins(prices)


def change(api, admin, **changes):
    return api.patch(SETTINGS_URL, json=changes, headers=as_user(admin))


@needs_database
def test_defaults_and_the_servers_setup_are_shown(admin_api, prices):
    api, admin = admin_api

    response = api.get(SETTINGS_URL, headers=as_user(admin))

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["values"]["maintenance"] is False
    assert body["values"]["payment_timeout_minutes"] is None
    assert body["values"]["pass_reminder_days"] == 3
    assert body["defaults"]["payment_timeout_minutes"] == 60
    server = body["server"]
    assert server["schema_version"] == "0020"
    assert server["pesapal_configured"] is True
    assert server["payment_timeout_minutes_server"] == 60
    assert server["qualities"] == ["360p", "480p", "720p", "1080p"]
    assert api.get(SETTINGS_URL, headers=as_user(uuid.uuid4())).status_code == 403


@needs_database
def test_settings_are_saved_reset_and_never_half_saved(admin_api, prices, caplog):
    api, admin = admin_api

    with caplog.at_level(logging.INFO, logger="veloraug.audit"):
        response = change(
            api,
            admin,
            support_email="help@veloraug.ug",
            pass_reminder_days=5,
        )

    assert response.status_code == 200, response.text
    values = response.json()["values"]
    assert (values["support_email"], values["pass_reminder_days"]) == (
        "help@veloraug.ug",
        5,
    )
    assert '"event":"admin.settings_changed"' in caplog.text
    who = prices.execute(
        "select updated_by from public.app_settings where key = 'support_email'"
    ).fetchone()[0]
    assert who == admin

    # One wrong value: nothing is saved, and each wrong one is named.
    bad = change(
        api,
        admin,
        support_email="other@veloraug.ug",
        support_phone="0772",
        nonsense=1,
    )
    assert bad.status_code == 400
    errors = bad.json()["detail"]["errors"]
    assert set(errors) == {"support_phone", "nonsense"}
    shown = api.get(SETTINGS_URL, headers=as_user(admin)).json()["values"]
    assert shown["support_email"] == "help@veloraug.ug"

    # null: back to the default.
    reset = change(api, admin, pass_reminder_days=None)
    assert reset.json()["values"]["pass_reminder_days"] == 3
    unknown = change(api, admin, default_language="xyz")
    assert unknown.status_code == 400
    assert "Add it first" in unknown.json()["detail"]["errors"]["default_language"]
    assert change(api, uuid.uuid4(), maintenance=True).status_code == 403


@needs_database
def test_the_app_reads_maintenance_and_support_contacts(admin_api, prices):
    api, admin = admin_api
    assert api.get("/api/v1/status").json() == {
        "maintenance": False,
        "maintenance_message": "",
        "support_email": "",
        "support_phone": "",
        "support_whatsapp": "",
    }

    change(
        api,
        admin,
        maintenance=True,
        maintenance_message="Back at 6pm.",
        support_whatsapp="+256772123456",
    )

    status = api.get("/api/v1/status").json()
    assert status["maintenance"] is True
    assert status["maintenance_message"] == "Back at 6pm."
    assert status["support_whatsapp"] == "+256772123456"


@needs_database
def test_no_pass_is_sold_during_maintenance(admin_api, fake, prices):
    api, admin = admin_api
    change(api, admin, maintenance=True, maintenance_message="Back at 6pm.")
    user = uuid.uuid4()

    refused = api.post(
        "/api/v1/passes/checkout",
        json={"plan_id": "velora_start", "email": "viewer@example.com"},
        headers=as_user(user),
    )

    assert refused.status_code == 503
    assert refused.json()["detail"] == "Back at 6pm."
    assert fake.orders == {}
    change(api, admin, maintenance=False)
    assert buy(api, user)["payment_id"]


@needs_database
def test_the_payment_timeout_set_here_wins_over_the_servers(admin_api, prices):
    api, admin = admin_api
    change(api, admin, payment_timeout_minutes=30)
    payment = buy(api, uuid.uuid4())["payment_id"]
    age(prices, payment, 31)

    metrics = api.get("/api/v1/admin/billing/metrics", headers=as_user(admin)).json()

    assert metrics["payment_timeout_minutes"] == 30
    assert state_of(prices, payment) == ("abandoned", "Not paid within 30 minutes")


@needs_database
def test_viewers_are_reminded_as_many_days_ahead_as_set(admin_api, fake, prices):
    api, admin = admin_api
    user = uuid.uuid4()
    pay(api, fake, user)  # Velora Start: 7 days.
    prices.execute(
        "update public.passes set starts_at = now() - interval '2 days', "
        "ends_at = now() + interval '5 days' where user_id = %s",
        (user,),
    )

    def kinds():
        response = api.get("/api/v1/me/notifications", headers=as_user(user))
        assert response.status_code == 200, response.text
        return {n["kind"] for n in response.json()["notifications"]}

    assert "pass_ending" not in kinds()
    change(api, admin, pass_reminder_days=6)
    assert "pass_ending" in kinds()


@needs_database
def test_new_drafts_take_the_default_language(admin_api, prices):
    api, admin = admin_api
    prices.execute(
        "insert into public.languages (code, name) values ('nyn', 'Runyankole') "
        "on conflict do nothing"
    )
    try:
        assert change(api, admin, default_language="nyn").status_code == 200

        made = api.post(
            "/api/v1/admin/drafts",
            json={"kind": "movie", "title": "Omukwano"},
            headers=as_user(admin),
        ).json()
        chosen = api.post(
            "/api/v1/admin/drafts",
            json={"kind": "movie", "title": "Fast X", "language": "lg"},
            headers=as_user(admin),
        ).json()

        def language(edition_id):
            return prices.execute(
                "select language from public.editions where id = %s",
                (edition_id,),
            ).fetchone()[0]

        assert language(made["edition_id"]) == "nyn"
        assert language(chosen["edition_id"]) == "lg"
    finally:
        delete_editions(prices, "display_title in ('Omukwano', 'Fast X')")
