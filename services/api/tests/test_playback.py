"""Playback grants: signing, settings, migration 0004 and the grant route.

The route tests need a local test Postgres: see tests/db_support.py.
"""

import base64
import hashlib
import hmac
import json
import logging
import uuid
from datetime import UTC, datetime
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.config import Settings
from app.db import Database
from app.main import create_app
from app.playback import GRANT_SECONDS, Granter, sign_grant
from tests.db_support import add_movie, migrate, needs_database, set_published
from tests.test_catalogue import details
from tests.test_database import FakeVerifier, as_user
from tests.test_uploads import ready_original

VECTOR = json.loads(
    (
        Path(__file__).resolve().parents[2]
        / "media_gateway"
        / "test"
        / "grant-vector.json"
    ).read_text()
)
KEY = "a-test-signing-key-that-is-long-enough-000"
GATEWAY = "http://127.0.0.1:8787"
NOW = 1_800_000_000


def unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


# --- The grant ---------------------------------------------------------------


def test_the_shared_vector_matches():
    """The Worker's tests check the same grant, so the two can't drift."""
    grant = sign_grant(
        VECTOR["key"].encode(),
        item_id=uuid.UUID(VECTOR["movie_id"]),
        original_id=uuid.UUID(VECTOR["original_id"]),
        expires=VECTOR["expires"],
    )
    assert grant == VECTOR["grant"]
    download = sign_grant(
        VECTOR["key"].encode(),
        item_id=uuid.UUID(VECTOR["movie_id"]),
        original_id=uuid.UUID(VECTOR["original_id"]),
        expires=VECTOR["expires"],
        purpose="download",
    )
    assert download == VECTOR["download_grant"]


def test_a_grant_is_a_signed_payload_naming_the_movie_and_original():
    movie, original = uuid.uuid4(), uuid.uuid4()
    grant = sign_grant(KEY.encode(), item_id=movie, original_id=original, expires=7)

    payload, signature = grant.split(".")
    assert json.loads(unb64(payload)) == {
        "m": str(movie),
        "o": str(original),
        "e": 7,
        "p": "playback",
    }
    expected = hmac.new(
        KEY.encode(), b"veloraug-playback-v1." + payload.encode(), hashlib.sha256
    ).digest()
    assert unb64(signature) == expected
    # Safe in a path: no padding, slashes or plus signs.
    assert all(c.isalnum() or c in "-_." for c in grant)


def test_a_different_key_makes_a_different_signature():
    ids = {"item_id": uuid.uuid4(), "original_id": uuid.uuid4(), "expires": 7}
    assert sign_grant(b"x" * 32, **ids) != sign_grant(b"y" * 32, **ids)


def test_the_granter_builds_the_address_and_expiry():
    movie, original = uuid.uuid4(), uuid.uuid4()
    granter = Granter(key=KEY.encode(), gateway_url=GATEWAY + "/", clock=lambda: NOW)

    playback = granter.grant(movie, original)

    prefix = f"{GATEWAY}/v1/"
    assert playback.playlist_url.startswith(prefix)
    assert playback.playlist_url.endswith("/master.m3u8")
    token = playback.playlist_url.removeprefix(prefix).removesuffix("/master.m3u8")
    assert token == sign_grant(
        KEY.encode(), item_id=movie, original_id=original, expires=NOW + GRANT_SECONDS
    )
    assert playback.expires_at == datetime.fromtimestamp(NOW + 6 * 3600, UTC)


# --- Settings ----------------------------------------------------------------


def test_playback_settings_go_together():
    with pytest.raises(ValidationError, match="together"):
        Settings(playback_signing_key=KEY)
    with pytest.raises(ValidationError, match="together"):
        Settings(media_gateway_url=GATEWAY)
    assert not Settings().playback_configured


def test_a_short_key_is_refused_without_quoting_it():
    with pytest.raises(ValidationError) as error:
        Settings(playback_signing_key="short-secret", media_gateway_url=GATEWAY)
    assert "32 characters" in str(error.value)
    assert "short-secret" not in str(error.value)


def test_the_key_is_kept_secret():
    settings = Settings(playback_signing_key=KEY, media_gateway_url=GATEWAY)
    assert KEY not in repr(settings)
    assert KEY not in str(settings.model_dump())


@pytest.mark.parametrize(
    "url",
    [
        "http://media.example",
        "https://media.example/v1",
        "https://media.example?x=1",
        "ftp://media.example",
        "media.example",
    ],
)
def test_the_gateway_must_be_https_or_loopback_with_no_path(url):
    with pytest.raises(ValidationError, match="media_gateway_url"):
        Settings(playback_signing_key=KEY, media_gateway_url=url)


@pytest.mark.parametrize(
    "url", ["http://127.0.0.1:8787", "http://localhost:8787", "https://m.example/"]
)
def test_good_gateway_addresses(url):
    settings = Settings(playback_signing_key=KEY, media_gateway_url=url)
    assert settings.media_gateway_url == url.rstrip("/")


def test_production_needs_playback():
    with pytest.raises(ValidationError, match="VELORAUG_PLAYBACK_SIGNING_KEY"):
        Settings(
            environment="production",
            neon_auth_url="https://auth.example.test/neondb/auth",
            api_resource="https://api.example.invalid",
            neon_auth_client_ids=["web"],
            database_url="postgresql://veloraug_app:x@ep-x-pooler.neon.tech/neondb",
        )


def test_cors_allows_post_from_the_app():
    client = TestClient(create_app())
    response = client.options(
        "/api/v1/movies/x/playback",
        headers={
            "Origin": "http://localhost:8765",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "Authorization",
        },
    )
    assert response.status_code == 200
    assert "POST" in response.headers["access-control-allow-methods"]


def test_without_settings_granting_answers_503():
    app = create_app(token_verifier=FakeVerifier())
    with TestClient(app) as client:
        response = client.post(
            f"/api/v1/items/{uuid.uuid4()}/playback", headers=as_user(uuid.uuid4())
        )
    assert response.status_code == 503


# --- On a real Postgres ------------------------------------------------------


@pytest.fixture
def api(app_url):
    app = create_app(
        token_verifier=FakeVerifier(),
        database=Database(app_url),
        granter=Granter(key=KEY.encode(), gateway_url=GATEWAY, clock=lambda: NOW),
    )
    with TestClient(app) as client:
        yield client


@pytest.fixture
def owner(owner_url, app_url):
    with psycopg.connect(owner_url, autocommit=True) as conn:
        yield conn


def new_movie(owner, *, publish=True):
    tmdb_id = 3_000_000 + uuid.uuid4().int % 1_000_000_000
    movie_id = add_movie(owner, details(tmdb_id, "Watchable"))
    if publish:
        set_published(owner, str(tmdb_id), True)
    return movie_id, tmdb_id


def grant_for(api, movie_id, user=None):
    return api.post(
        f"/api/v1/items/{movie_id}/playback", headers=as_user(user or uuid.uuid4())
    )


@needs_database
def test_a_ready_published_movie_is_granted(api, owner, owner_url, media_url, caplog):
    movie_id, _ = new_movie(owner)
    original = ready_original(owner_url, media_url, movie_id)
    user = uuid.uuid4()

    with caplog.at_level(logging.INFO, logger="veloraug.playback"):
        response = grant_for(api, movie_id, user)

    assert response.status_code == 200
    body = response.json()
    token = body["playlist_url"].removeprefix(f"{GATEWAY}/v1/").split("/")[0]
    payload = json.loads(unb64(token.split(".")[0]))
    assert payload == {
        "m": str(movie_id),
        "o": str(original),
        "e": NOW + 21600,
        "p": "playback",
    }
    assert body["expires_at"] == "2027-01-15T14:00:00Z"
    # The log names the item, never the user or the grant. A film from
    # before Milestone 9 keeps its ID as its item's.
    assert str(movie_id) in caplog.text
    assert str(user) not in caplog.text and token not in caplog.text


@needs_database
def test_the_details_say_whether_a_movie_is_playable(api, owner, owner_url, media_url):
    waiting, _ = new_movie(owner)
    ready, _ = new_movie(owner)
    ready_original(owner_url, media_url, ready)

    assert api.get(f"/api/v1/editions/{waiting}").json()["playable"] is False
    assert api.get(f"/api/v1/editions/{ready}").json()["playable"] is True


@needs_database
def test_signing_in_is_needed(api, owner, owner_url, media_url):
    movie_id, _ = new_movie(owner)
    ready_original(owner_url, media_url, movie_id)

    assert api.post(f"/api/v1/items/{movie_id}/playback").status_code == 401
    response = api.post(
        f"/api/v1/items/{movie_id}/playback",
        headers={"Authorization": "Bearer not-a-user"},
    )
    assert response.status_code == 401


@needs_database
def test_hidden_and_unknown_movies_are_404_alike(api, owner, owner_url, media_url):
    hidden, _ = new_movie(owner, publish=False)
    ready_original(owner_url, media_url, hidden)

    for movie_id in (hidden, uuid.uuid4()):
        response = grant_for(api, movie_id)
        assert response.status_code == 404
        assert response.json() == {"detail": "This isn't available."}


@needs_database
def test_a_movie_with_nothing_ready_is_409(api, owner, owner_url, media_url):
    movie_id, _ = new_movie(owner)

    response = grant_for(api, movie_id)

    assert response.status_code == 409
    assert response.json() == {"detail": "This can't be watched yet."}


@needs_database
def test_an_unpublished_movie_hides_its_original_from_the_api(
    app_url, owner, owner_url, media_url
):
    movie_id, tmdb_id = new_movie(owner)
    original = ready_original(owner_url, media_url, movie_id)

    def seen():
        with psycopg.connect(app_url) as conn:
            return conn.execute(
                "select id from public.media_originals where id = %s", (original,)
            ).fetchall()

    assert seen() == [(original,)]
    set_published(owner, str(tmdb_id), False)
    assert seen() == []


@needs_database
def test_the_api_sees_no_original_that_isnt_ready(app_url, owner, owner_url, media_url):
    movie_id, _ = new_movie(owner)
    original = ready_original(owner_url, media_url, movie_id)
    with psycopg.connect(media_url) as conn:
        conn.execute(
            "update public.media_originals set state = 'removing' where id = %s",
            (original,),
        )

    with psycopg.connect(app_url) as conn:
        assert (
            conn.execute(
                "select count(*) from public.media_originals where id = %s",
                (original,),
            ).fetchone()[0]
            == 0
        )


@needs_database
def test_0004_downgrades_and_upgrades(owner_url, app_url):
    try:
        migrate(owner_url, "0003", down=True)
        with (
            psycopg.connect(app_url) as conn,
            pytest.raises(psycopg.errors.InsufficientPrivilege),
        ):
            conn.execute("select id from public.media_originals")
    finally:
        migrate(owner_url)
    with psycopg.connect(app_url) as conn:
        conn.execute("select id from public.media_originals")
