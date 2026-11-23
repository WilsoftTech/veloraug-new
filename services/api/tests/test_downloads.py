# Fixtures imported from test_passes and test_viewer are used as arguments.
# ruff: noqa: F811
"""Downloads on Android: the download grant and offline licences.

A download's grant has no playback session, so it takes no stream; the
offline licence lasts OFFLINE_DAYS, never past the viewer's passes, and is
refused for a removed device, an ended pass or a title taken down.

On a real Postgres with Pesapal faked. Skipped without a local test
Postgres: see tests/db_support.py.
"""

import base64
import json
import uuid
from datetime import UTC, datetime, timedelta

import pytest

from app import editions, playback
from tests.db_support import needs_database
from tests.test_database import as_user
from tests.test_passes import (  # noqa: F401
    api,
    buy,
    catalogue,
    fake,
    owner,
    pay,
    prices,
    tracking_of,
)
from tests.test_subscriptions import (  # noqa: F401
    admin,
    device_id,
    end_passes_now,
    live,
    new_device,
    watch,
)
from tests.test_viewer import GATEWAY
from tests.test_viewer import api as viewer_api  # noqa: F401

LICENCES = "/api/v1/me/offline-licences"


def download(api, item_id, user, credential=None):
    headers = as_user(user)
    if credential:
        headers["X-Velora-Device"] = credential
    return api.post(f"/api/v1/items/{item_id}/download", headers=headers)


def renew(api, items, user, credential=None):
    headers = as_user(user)
    if credential:
        headers["X-Velora-Device"] = credential
    return api.post(LICENCES, json={"items": [str(i) for i in items]}, headers=headers)


def claims_of(response) -> dict:
    token = response.json()["playlist_url"].removeprefix(f"{GATEWAY}/v1/")
    payload = token.split("/")[0].split(".")[0]
    return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))


def offline_until(response) -> datetime:
    return datetime.fromisoformat(response.json()["offline_until"])


def near(when: datetime, expected: datetime) -> bool:
    return abs((when - expected).total_seconds()) < 60


@pytest.fixture
def items(catalogue):
    return catalogue["movie"].item_id, catalogue["third"].item_id


# --- Passes off: any signed-in viewer -----------------------------------------


@needs_database
def test_with_passes_off_a_download_lasts_an_hour_and_plays_offline_a_week(
    viewer_api, catalogue
):
    now = datetime.now(UTC)
    response = download(viewer_api, catalogue["movie"].item_id, uuid.uuid4())

    assert response.status_code == 200, response.text
    assert "s" not in claims_of(response)
    expires = datetime.fromisoformat(response.json()["expires_at"])
    assert near(expires, now + timedelta(seconds=playback.DOWNLOAD_GRANT_SECONDS))
    assert near(offline_until(response), now + timedelta(days=playback.OFFLINE_DAYS))


@needs_database
def test_downloads_are_refused_as_playback_is(viewer_api, owner, catalogue):
    movie = catalogue["movie"].item_id
    assert viewer_api.post(f"/api/v1/items/{movie}/download").status_code == 401
    for item_id in (catalogue["second"].item_id, catalogue["draft"].item_id):
        assert download(viewer_api, item_id, uuid.uuid4()).status_code == 404

    owner.execute(
        "update public.media_originals set state = 'removing' where item_id = %s",
        (movie,),
    )
    assert download(viewer_api, movie, uuid.uuid4()).status_code == 409


@needs_database
def test_licences_are_renewed_and_taken_down_titles_get_none(
    viewer_api, owner, catalogue
):
    movie, episode = catalogue["movie"].item_id, catalogue["third"].item_id
    gone = catalogue["draft"].item_id
    user = uuid.uuid4()

    response = renew(viewer_api, [movie, episode, gone, movie], user)

    assert response.status_code == 200, response.text
    licences = {
        row["item_id"]: row["offline_until"] for row in response.json()["licences"]
    }
    assert set(licences) == {str(movie), str(episode), str(gone)}
    assert licences[str(gone)] is None
    assert licences[str(movie)] is not None

    editions.hide(owner, catalogue["movie"].edition_id)
    after = renew(viewer_api, [movie], user).json()["licences"]
    assert after == [{"item_id": str(movie), "offline_until": None}]


@needs_database
def test_licences_are_asked_for_at_most_two_hundred_at_once(viewer_api, catalogue):
    many = [uuid.uuid4() for _ in range(201)]
    assert renew(viewer_api, many, uuid.uuid4()).status_code == 422


# --- Passes required ------------------------------------------------------------


@needs_database
def test_a_download_needs_a_pass_and_a_registered_device(api, fake, prices, items):
    movie, _ = items
    user = uuid.uuid4()
    assert download(api, movie, user).status_code == 402
    assert renew(api, [movie], user).status_code == 402

    pay(api, fake, user, "velora_flex")
    refused = download(api, movie, user)
    assert refused.status_code == 403
    assert refused.json()["detail"]["code"] == "device_required"

    phone = new_device(api, user)
    response = download(api, movie, user, phone)
    assert response.status_code == 200, response.text
    assert "s" not in claims_of(response)


@needs_database
def test_offline_play_ends_with_the_passes(api, fake, prices, items):
    movie, _ = items
    user = uuid.uuid4()
    pay(api, fake, user, "velora_flex")
    phone = new_device(api, user)
    ends = datetime.now(UTC) + timedelta(days=2)
    prices.execute(
        "update public.passes set ends_at = %s where user_id = %s", (ends, user)
    )

    response = download(api, movie, user, phone)

    assert near(offline_until(response), ends)
    assert datetime.fromisoformat(response.json()["expires_at"]) <= ends
    licence = renew(api, [movie], user, phone).json()["licences"][0]
    assert near(datetime.fromisoformat(licence["offline_until"]), ends)

    end_passes_now(prices, user)
    assert download(api, movie, user, phone).status_code == 402
    assert renew(api, [movie], user, phone).status_code == 402


@needs_database
def test_a_download_takes_no_stream_and_never_stops_the_player(
    api, fake, prices, items
):
    movie, episode = items
    user = uuid.uuid4()
    pay(api, fake, user, "velora_start")  # One stream.
    phone = new_device(api, user)
    watching = watch(api, movie, user, phone)
    assert watching.status_code == 200, watching.text
    session = watching.json()["session_id"]

    assert download(api, episode, user, phone).status_code == 200

    assert live(api, session)
    (count,) = prices.execute(
        "select count(*) from public.playback_sessions where user_id = %s", (user,)
    ).fetchone()
    assert count == 1


@needs_database
def test_a_removed_device_can_neither_download_nor_renew(api, fake, prices, items):
    movie, _ = items
    user = uuid.uuid4()
    pay(api, fake, user, "velora_flex")
    phone = new_device(api, user)
    assert renew(api, [movie], user, phone).status_code == 200

    removed = api.delete(
        f"/api/v1/me/devices/{device_id(phone)}", headers=as_user(user)
    )
    assert removed.status_code == 204, removed.text

    for response in (
        download(api, movie, user, phone),
        renew(api, [movie], user, phone),
    ):
        assert response.status_code == 403
        assert response.json()["detail"]["code"] == "device_required"


@needs_database
def test_admins_download_without_a_pass_or_device(api, admin, items):
    response = download(api, items[0], admin)

    assert response.status_code == 200, response.text
    expected = datetime.now(UTC) + timedelta(days=playback.OFFLINE_DAYS)
    assert near(offline_until(response), expected)
