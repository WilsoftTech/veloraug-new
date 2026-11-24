# ruff: noqa: F811  (pytest fixtures are imported, then named as arguments)
"""The account hub: watch history, notifications and account deletion, on a
real Postgres, with Pesapal and the identity provider faked.

Skipped without a local test Postgres: see tests/db_support.py.
"""

import uuid
from datetime import UTC, datetime, timedelta

import psycopg
import pytest
from fastapi.testclient import TestClient

from app import account
from app.auth import InvalidToken, VerifiedUser
from app.config import Settings
from app.db import Database
from app.main import create_app
from app.playback import Granter
from tests.db_support import needs_database
from tests.test_database import as_user
from tests.test_passes import (  # noqa: F401
    admin_api,
    clear_billing,
    device_of,
    fake,
    grant,
    pay,
    prices,
    refund,
)
from tests.test_viewer import GATEWAY, KEY, catalogue, owner  # noqa: F401


class Verifier:
    """The token is the user ID, then `@recent` or `@stale` for when the
    person last signed in. Without either, the token doesn't say."""

    def verify(self, token: str) -> VerifiedUser:
        user, _, when = token.partition("@")
        try:
            user_id = uuid.UUID(user)
        except ValueError:
            raise InvalidToken("test") from None
        now = datetime.now(UTC)
        auth_time = {
            "recent": now - timedelta(minutes=1),
            "stale": now - timedelta(hours=2),
        }.get(when)
        return VerifiedUser(
            user_id=user_id, client_id="web-client", auth_time=auth_time
        )


class FakeIdentity:
    """The identity provider: fails the first `failures` times."""

    def __init__(self, failures: int = 0) -> None:
        self.failures = failures
        self.deleted: list[uuid.UUID] = []

    def delete(self, user_id: uuid.UUID) -> None:
        if self.failures:
            self.failures -= 1
            raise account.IdentityDeletionFailed()
        if user_id not in self.deleted:
            self.deleted.append(user_id)


def make(app_url, *, deletion: bool = False, identity=None, **changes):
    return create_app(
        settings=Settings(account_deletion_enabled=deletion, **changes),
        token_verifier=Verifier(),
        database=Database(app_url),
        granter=Granter(key=KEY.encode(), gateway_url=GATEWAY),
        identity_deleter=identity,
    )


@pytest.fixture
def api(app_url, prices):  # noqa: F811
    with TestClient(make(app_url)) as client:
        yield client


@pytest.fixture
def clean(owner_url):
    def wipe():
        with psycopg.connect(owner_url, autocommit=True) as conn:
            for table in ("watch_history", "notification_reads", "account_deletions"):
                conn.execute(f"delete from public.{table}")

    wipe()
    yield
    wipe()


def watch(api, item_id, user):
    response = api.post(f"/api/v1/items/{item_id}/playback", headers=as_user(user))
    assert response.status_code == 200, response.text
    assert position(api, item_id, user, 2).status_code == 204


def history(api, user):
    response = api.get("/api/v1/me/history", headers=as_user(user))
    assert response.status_code == 200, response.text
    return response.json()


def position(api, item_id, user, seconds, finished=False):
    return api.put(
        f"/api/v1/me/history/{item_id}/position",
        json={"position_seconds": seconds, "finished": finished},
        headers=as_user(user),
    )


# --- Watch history -----------------------------------------------------------


@needs_database
def test_unused_grant_is_not_watch_history(api, catalogue, clean):
    user = uuid.uuid4()
    item = catalogue["movie"].item_id
    response = api.post(f"/api/v1/items/{item}/playback", headers=as_user(user))
    assert response.status_code == 200
    assert history(api, user) == []


@needs_database
def test_watching_is_recorded_once_per_item_latest_first(api, catalogue, clean):
    user = uuid.uuid4()
    movie = catalogue["movie"].item_id
    episode = catalogue["series"].item_id

    watch(api, movie, user)
    watch(api, episode, user)
    watch(api, movie, user)  # A replay: the same row, now the latest.

    rows = history(api, user)
    assert [row["item_id"] for row in rows] == [str(movie), str(episode)]
    assert rows[0]["edition"]["title"] == "Fast X"
    assert rows[1]["season"] == 1 and rows[1]["episode"] == 1
    assert rows[0]["resume_seconds"] is None


@needs_database
def test_resume_is_offered_only_for_a_saved_position(api, catalogue, clean):
    user = uuid.uuid4()
    movie = catalogue["movie"].item_id
    watch(api, movie, user)

    assert position(api, movie, user, 12).status_code == 204
    assert history(api, user)[0]["resume_seconds"] is None  # Too early.

    assert position(api, movie, user, 1500).status_code == 204
    assert history(api, user)[0]["resume_seconds"] == 1500

    assert position(api, movie, user, 7000, finished=True).status_code == 204
    assert history(api, user)[0]["resume_seconds"] is None


@needs_database
def test_a_position_for_something_not_watched_is_refused(api, catalogue, clean):
    user = uuid.uuid4()
    assert position(api, catalogue["movie"].item_id, user, 100).status_code == 404
    assert history(api, user) == []


@needs_database
def test_history_is_private_to_each_account(api, catalogue, clean):
    mine, theirs = uuid.uuid4(), uuid.uuid4()
    movie = catalogue["movie"].item_id
    watch(api, movie, mine)

    assert history(api, theirs) == []
    # Saving a position on someone else's row finds nothing to update.
    assert position(api, movie, theirs, 900).status_code == 404
    assert history(api, mine)[0]["resume_seconds"] is None


@needs_database
def test_an_unpublished_title_leaves_history(api, owner, catalogue, clean):  # noqa: F811
    user = uuid.uuid4()
    watch(api, catalogue["movie"].item_id, user)
    owner.execute(
        "update public.editions set status = 'hidden' where id = %s",
        (catalogue["movie"].edition_id,),
    )
    assert history(api, user) == []


# --- Notifications -----------------------------------------------------------


@pytest.fixture
def billing_api(app_url, fake, prices):  # noqa: F811
    from tests.test_passes import make_api

    with TestClient(make_api(app_url, fake)) as client:
        yield client


def notifications(api, user):
    response = api.get("/api/v1/me/notifications", headers=as_user(user))
    assert response.status_code == 200, response.text
    return response.json()


@needs_database
def test_a_confirmed_payment_is_a_notification_until_read(
    billing_api,
    fake,
    prices,
    clean,  # noqa: F811
):
    user, other = uuid.uuid4(), uuid.uuid4()
    paid = pay(billing_api, fake, user)
    assert paid["state"] == "completed"

    found = notifications(billing_api, user)
    assert found["unread"] == 1
    (note,) = found["notifications"]
    assert note["kind"] == "payment_completed"
    assert note["plan_name"] == "Velora Start"
    assert note["read"] is False
    # Never an amount, a phone number or an email.
    assert set(note) == {"id", "kind", "at", "read", "plan_name", "device_label"}

    # Someone else sees nothing, and can't mark it read for them.
    assert notifications(billing_api, other) == {"notifications": [], "unread": 0}
    billing_api.post(
        "/api/v1/me/notifications/read",
        json={"ids": [note["id"]]},
        headers=as_user(other),
    )
    assert notifications(billing_api, user)["unread"] == 1

    response = billing_api.post(
        "/api/v1/me/notifications/read", json={"all": True}, headers=as_user(user)
    )
    assert response.status_code == 204
    after = notifications(billing_api, user)
    assert after["unread"] == 0 and after["notifications"][0]["read"] is True


@needs_database
def test_a_refund_and_a_device_removed_by_an_admin_are_notifications(
    admin_api,
    fake,
    prices,
    clean,  # noqa: F811
):
    api, admin = admin_api
    user = uuid.uuid4()
    paid = pay(api, fake, user)
    assert refund(api, admin, paid["id"]).status_code == 200

    device_of(api, user)
    (device,) = api.get("/api/v1/me/devices", headers=as_user(user)).json()["devices"]
    response = api.delete(
        f"/api/v1/admin/billing/users/{user}/devices/{device['id']}",
        headers=as_user(admin),
    )
    assert response.status_code == 204

    kinds = [n["kind"] for n in notifications(api, user)["notifications"]]
    assert "payment_refunded" in kinds
    assert "device_removed" in kinds
    assert "payment_completed" in kinds


@needs_database
def test_read_marks_take_only_notification_ids(api, clean):
    user = uuid.uuid4()
    response = api.post(
        "/api/v1/me/notifications/read",
        json={"ids": ["'; drop table x; --"]},
        headers=as_user(user),
    )
    assert response.status_code == 422


# --- Account deletion --------------------------------------------------------


def deletion(api, user, token_suffix="@recent"):
    return api.post(
        "/api/v1/me/deletion",
        json={"user_id": str(uuid.uuid4())},  # Ignored: the token decides.
        headers=as_user(f"{user}{token_suffix}"),
    )


def count(owner_url, table, user_id, where="true"):
    with psycopg.connect(owner_url) as conn:
        return conn.execute(
            f"select count(*) from public.{table} where user_id = %s and {where}",
            (user_id,),
        ).fetchone()[0]


@pytest.fixture
def viewer_with_data(api, catalogue, owner_url, clean):
    """A viewer with a profile, history and a registered device."""
    user = uuid.uuid4()
    assert api.get("/api/v1/me", headers=as_user(user)).status_code == 200
    watch(api, catalogue["movie"].item_id, user)
    register = api.post(
        "/api/v1/me/devices",
        json={"label": "Test phone", "platform": "android"},
        headers=as_user(user),
    )
    assert register.status_code == 201, register.text
    return user


@needs_database
def test_deletion_is_off_until_set_up_and_removes_nothing(
    api, viewer_with_data, owner_url
):
    user = viewer_with_data
    status = api.get("/api/v1/me/deletion", headers=as_user(user)).json()
    assert status == {"available": False, "state": "none", "requested_at": None}

    response = deletion(api, user)
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "deletion_unavailable"
    assert count(owner_url, "profiles", user) == 1
    assert count(owner_url, "watch_history", user) == 1
    assert count(owner_url, "account_deletions", user) == 0


@needs_database
def test_deletion_needs_a_recent_sign_in(app_url, viewer_with_data, owner_url):
    user = viewer_with_data
    identity = FakeIdentity()
    with TestClient(make(app_url, deletion=True, identity=identity)) as api:
        for suffix in ("@stale", ""):
            response = deletion(api, user, suffix)
            assert response.status_code == 401
            assert response.json()["detail"]["code"] == "reauth_required"
    assert identity.deleted == []
    assert count(owner_url, "profiles", user) == 1


@needs_database
def test_deletion_removes_only_this_accounts_data_and_keeps_payments(
    app_url,
    viewer_with_data,
    catalogue,
    owner_url,
    fake,
    prices,  # noqa: F811
):
    user, bystander = viewer_with_data, uuid.uuid4()
    identity = FakeIdentity()
    with TestClient(make(app_url, deletion=True, identity=identity)) as api:
        assert api.get("/api/v1/me", headers=as_user(bystander)).status_code == 200
        watch(api, catalogue["movie"].item_id, bystander)
        prices.execute(
            "insert into public.payments (user_id, plan_id, plan_name, days, "
            "amount_ugx, email, max_devices, max_streams) values (%s, "
            "'velora_start', 'Velora Start', 7, 6000, 'viewer@example.com', 1, 1)",
            (user,),
        )

        response = deletion(api, user)
        assert response.status_code == 200, response.text
        assert response.json()["state"] == "completed"

        # Asking again is safe, and says it's done.
        again = deletion(api, user)
        assert again.status_code == 200 and again.json()["state"] == "completed"

    assert identity.deleted == [user]
    assert count(owner_url, "profiles", user) == 0
    assert count(owner_url, "watch_history", user) == 0
    assert count(owner_url, "devices", user, "revoked_at is null") == 0
    assert count(owner_url, "payments", user) == 1
    # Someone else's account is untouched.
    assert count(owner_url, "profiles", bystander) == 1
    assert count(owner_url, "watch_history", bystander) == 1


@needs_database
def test_a_deletion_that_fails_part_way_can_be_retried(
    app_url, viewer_with_data, owner_url
):
    user = viewer_with_data
    identity = FakeIdentity(failures=1)
    with TestClient(make(app_url, deletion=True, identity=identity)) as api:
        first = deletion(api, user)
        assert first.status_code == 502
        assert first.json()["detail"]["code"] == "deletion_incomplete"
        status = api.get("/api/v1/me/deletion", headers=as_user(user)).json()
        assert status["state"] == "pending"
        # VeloraUG's own data is already gone; the sign-in account isn't.
        assert count(owner_url, "watch_history", user) == 0
        assert identity.deleted == []

        second = deletion(api, user)
        assert second.status_code == 200
        assert second.json()["state"] == "completed"
    assert identity.deleted == [user]
    assert count(owner_url, "account_deletions", user, "attempts = 2") == 1
