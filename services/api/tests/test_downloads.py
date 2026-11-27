# Fixtures imported from test_passes and test_viewer are used as arguments.
# ruff: noqa: F811
"""Downloads: the grant for a viewer's browser or phone to download an
item's video as one .mp4 file, and the file's name.

A download's grant has no playback session, so it takes no stream and never
stops the player. It lasts a day, never past the pass, because the
browser's or Android's own downloader can't ask for a new one.

On a real Postgres with Pesapal faked. Skipped without a local test
Postgres: see tests/db_support.py.
"""

import base64
import json
import uuid
from datetime import UTC, datetime, timedelta

import pytest

from app import editions, playback
from app.viewer import safe_file_name
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


def download(api, item_id, user, credential=None):
    headers = as_user(user)
    if credential:
        headers["X-Velora-Device"] = credential
    return api.post(f"/api/v1/items/{item_id}/download", headers=headers)


def claims_of(response) -> dict:
    token = response.json()["playlist_url"].removeprefix(f"{GATEWAY}/v1/")
    payload = token.split("/")[0].split(".")[0]
    return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))


def expires(response) -> datetime:
    return datetime.fromisoformat(response.json()["expires_at"])


def near(when: datetime, expected: datetime) -> bool:
    return abs((when - expected).total_seconds()) < 60


@pytest.fixture
def items(catalogue):
    return catalogue["movie"].item_id, catalogue["third"].item_id


def test_file_names_are_plain_and_safe():
    assert safe_file_name("Fast X - VJ Junior") == "Fast X - VJ Junior"
    assert safe_file_name("Amélie: ça va?") == "Amelie ca va"
    assert safe_file_name("../../etc/passwd") == "etc passwd"
    assert safe_file_name('a<b>c"d|e*') == "a b c d e"
    assert safe_file_name("???") == "VeloraUG"
    assert len(safe_file_name("x" * 300)) == 100


# --- Passes off: any signed-in viewer -----------------------------------------


@needs_database
def test_a_download_lasts_a_day_and_names_its_file(viewer_api, catalogue):
    now = datetime.now(UTC)
    response = download(viewer_api, catalogue["movie"].item_id, uuid.uuid4())

    assert response.status_code == 200, response.text
    assert "s" not in claims_of(response)
    # VUG-SEC-001: good for the download files only, never for streaming.
    assert claims_of(response)["p"] == "download"
    assert response.json()["playlist_url"].endswith("/master.m3u8")
    assert near(
        expires(response), now + timedelta(seconds=playback.DOWNLOAD_GRANT_SECONDS)
    )
    assert response.json()["file_name"] == "Fast X - VJ Junior"


@needs_database
def test_a_download_lists_its_qualities_without_the_playlist(
    viewer_api, owner, catalogue
):
    """The gateway won't open the master playlist for a download grant, so
    the API says which qualities there are, best first."""
    from tests.test_uploads import add_quality

    movie = catalogue["movie"].item_id
    assert download(viewer_api, movie, uuid.uuid4()).json()["heights"] == []
    (original,) = owner.execute(
        "select id from public.media_originals where item_id = %s and state = 'ready'",
        (movie,),
    ).fetchone()
    for height in (480, 1080, 720):
        add_quality(owner, original, height)

    response = download(viewer_api, movie, uuid.uuid4())

    assert response.json()["heights"] == [1080, 720, 480]


@needs_database
def test_an_episodes_file_names_its_season_and_episode(viewer_api, catalogue):
    response = download(viewer_api, catalogue["third"].item_id, uuid.uuid4())

    assert response.status_code == 200, response.text
    assert response.json()["file_name"] == "Kabaka - S02E01 - VJ Emmy"


@needs_database
def test_downloads_are_refused_as_playback_is(viewer_api, owner, catalogue):
    movie = catalogue["movie"].item_id
    assert viewer_api.post(f"/api/v1/items/{movie}/download").status_code == 401
    for item_id in (catalogue["second"].item_id, catalogue["draft"].item_id):
        assert download(viewer_api, item_id, uuid.uuid4()).status_code == 404

    editions.hide(owner, catalogue["movie"].edition_id)
    assert download(viewer_api, movie, uuid.uuid4()).status_code == 404


@needs_database
def test_nothing_ready_is_409(viewer_api, owner, catalogue):
    movie = catalogue["movie"].item_id
    owner.execute(
        "update public.media_originals set state = 'removing' where item_id = %s",
        (movie,),
    )
    assert download(viewer_api, movie, uuid.uuid4()).status_code == 409


# --- Passes required ------------------------------------------------------------


@needs_database
def test_a_download_needs_a_pass_and_a_registered_device(api, fake, prices, items):
    movie, _ = items
    user = uuid.uuid4()
    assert download(api, movie, user).status_code == 402

    pay(api, fake, user, "velora_flex")
    refused = download(api, movie, user)
    assert refused.status_code == 403
    assert refused.json()["detail"]["code"] == "device_required"

    phone = new_device(api, user)
    response = download(api, movie, user, phone)
    assert response.status_code == 200, response.text
    assert "s" not in claims_of(response)


@needs_database
def test_a_download_grant_ends_with_the_pass(api, fake, prices, items):
    movie, _ = items
    user = uuid.uuid4()
    pay(api, fake, user, "velora_flex")
    phone = new_device(api, user)
    ends = datetime.now(UTC) + timedelta(hours=2)
    prices.execute(
        "update public.passes set ends_at = %s where user_id = %s", (ends, user)
    )

    assert near(expires(download(api, movie, user, phone)), ends)

    end_passes_now(prices, user)
    assert download(api, movie, user, phone).status_code == 402


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
def test_a_removed_device_cant_download(api, fake, prices, items):
    movie, _ = items
    user = uuid.uuid4()
    pay(api, fake, user, "velora_flex")
    phone = new_device(api, user)
    assert download(api, movie, user, phone).status_code == 200

    removed = api.delete(
        f"/api/v1/me/devices/{device_id(phone)}", headers=as_user(user)
    )
    assert removed.status_code == 204, removed.text

    refused = download(api, movie, user, phone)
    assert refused.status_code == 403
    assert refused.json()["detail"]["code"] == "device_required"


@needs_database
def test_admins_download_without_a_pass_or_device(api, admin, items):
    now = datetime.now(UTC)
    response = download(api, items[0], admin)

    assert response.status_code == 200, response.text
    assert near(
        expires(response), now + timedelta(seconds=playback.DOWNLOAD_GRANT_SECONDS)
    )
