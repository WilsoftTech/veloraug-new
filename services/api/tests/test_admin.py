"""The admin routes, Step 9C, on a real Postgres, with TMDB faked.

Skipped without a local test Postgres: see tests/db_support.py.
"""

import json
import logging
import os
import uuid

import httpx2
import psycopg
import pytest
from fastapi.testclient import TestClient

from app.db import Database
from app.main import create_app
from app.playback import Granter
from app.tmdb import TmdbClient
from tests.db_support import clear_admins, delete_editions, needs_database
from tests.test_database import FakeVerifier, as_user

KEY = "a-test-signing-key-that-is-long-enough-000"
GATEWAY = "http://127.0.0.1:8787"


class FakeTmdb:
    """Search, details, posters and videos, by path. Unknown IDs are 404."""

    def __init__(self) -> None:
        self.search: dict[str, list[dict]] = {}
        self.movies: dict[int, dict] = {}
        self.posters: dict[int, list[str]] = {}
        self.down = False
        self.requests: list[str] = []

    def handle(self, request: httpx2.Request) -> httpx2.Response:
        path = request.url.path.removeprefix("/3")
        self.requests.append(path)
        if self.down:
            return httpx2.Response(500)
        if path.startswith("/search/"):
            query = request.url.params["query"]
            return httpx2.Response(200, json={"results": self.search.get(query, [])})
        parts = path.strip("/").split("/")
        tmdb_id = int(parts[1])
        if tmdb_id not in self.movies:
            return httpx2.Response(404)
        if len(parts) == 2:
            return httpx2.Response(200, json=self.movies[tmdb_id])
        if parts[2] == "images":
            return httpx2.Response(
                200,
                json={
                    "posters": [
                        {"file_path": p, "iso_639_1": "en"}
                        for p in self.posters.get(tmdb_id, [])
                    ]
                },
            )
        return httpx2.Response(
            200,
            json={
                "results": [
                    {
                        "site": "YouTube",
                        "type": "Trailer",
                        "official": True,
                        "key": f"trailer{tmdb_id}",
                        "published_at": "2023-01-01",
                    }
                ]
            },
        )

    def add_movie(self, tmdb_id, title, year, posters=("/one.jpg",)):
        self.movies[tmdb_id] = {
            "id": tmdb_id,
            "title": title,
            "original_title": title,
            "overview": f"About {title}.",
            "release_date": f"{year}-05-01",
            "runtime": 120,
            "genres": [{"name": "Action"}],
            "poster_path": posters[0] if posters else None,
            "backdrop_path": "/back.jpg",
        }
        self.posters[tmdb_id] = list(posters)
        return {"id": tmdb_id, "title": title, "release_date": f"{year}-05-01"}


def new_tmdb_id() -> int:
    return 5_000_000 + uuid.uuid4().int % 1_000_000_000


@pytest.fixture
def tmdb():
    return FakeTmdb()


@pytest.fixture
def owner(owner_url, app_url):
    with psycopg.connect(owner_url, autocommit=True) as conn:
        delete_editions(conn)
        conn.execute("delete from public.vjs")
        yield conn
        delete_editions(conn)
        conn.execute("delete from public.vjs")


@pytest.fixture
def admin(owner):
    """A signed-in admin's user ID."""
    user = uuid.uuid4()
    clear_admins(owner)
    owner.execute("insert into public.admins (user_id) values (%s)", (user,))
    yield user
    clear_admins(owner)


@pytest.fixture
def api(app_url, editor_url, tmdb):
    app = create_app(
        token_verifier=FakeVerifier(),
        database=Database(app_url),
        editor_database=Database(editor_url),
        tmdb=TmdbClient("token", transport=httpx2.MockTransport(tmdb.handle)),
        granter=Granter(key=KEY.encode(), gateway_url=GATEWAY),
    )
    with TestClient(app) as client:
        yield client


def ready(owner, item_id, filename="Fast.X.2023.VJ.Junior.Luganda.mp4", hints=None):
    """An original taken to 'ready', as the worker would."""
    (key_id,) = owner.execute(
        """
        insert into public.upload_keys (item_id, key_hash, label, expires_at, used_at)
        values (%s, %s, 'Test', now() + interval '1 day', now()) returning id
        """,
        (item_id, os.urandom(32)),
    ).fetchone()
    original = uuid.uuid4()
    owner.execute(
        """
        insert into public.media_originals (id, item_id, upload_key_id, size_bytes,
          filename, credit_hints, state, ready_at)
        values (%s, %s, %s, 1000, %s, %s, 'ready', now())
        """,
        (original, item_id, key_id, filename, hints),
    )
    return original


def draft(api, admin, **body):
    response = api.post(
        "/api/v1/admin/drafts",
        json={"kind": "movie", "title": "Fast X", **body},
        headers=as_user(admin),
    )
    assert response.status_code == 201, response.text
    return response.json()


def edition(api, admin, edition_id):
    response = api.get(f"/api/v1/admin/editions/{edition_id}", headers=as_user(admin))
    assert response.status_code == 200, response.text
    return response.json()


# --- Who may use them --------------------------------------------------------


@needs_database
def test_only_admins_get_in(api, admin):
    assert api.get("/api/v1/admin/me").status_code == 401
    refused = api.get("/api/v1/admin/me", headers=as_user(uuid.uuid4()))
    assert refused.status_code == 403
    assert refused.json() == {"detail": "This account isn't an admin."}
    assert (
        api.post(
            "/api/v1/admin/drafts",
            json={"kind": "movie", "title": "x"},
            headers=as_user(uuid.uuid4()),
        ).status_code
        == 403
    )

    me = api.get("/api/v1/admin/me", headers=as_user(admin))
    assert me.json() == {"user_id": str(admin), "admin": True}


@needs_database
def test_without_the_editor_settings_admin_answers_503(app_url):
    app = create_app(token_verifier=FakeVerifier(), database=Database(app_url))
    with TestClient(app) as client:
        response = client.get("/api/v1/admin/me", headers=as_user(uuid.uuid4()))
    assert response.status_code == 503


# --- A movie, from draft to published ----------------------------------------


@needs_database
def test_a_clear_match_prefills_and_the_movie_publishes(
    api, admin, owner, tmdb, caplog
):
    tmdb_id = new_tmdb_id()
    tmdb.search["Fast X"] = [
        tmdb.add_movie(tmdb_id, "Fast X", 2023),
        tmdb.add_movie(new_tmdb_id(), "Fast Five", 2011),
    ]
    with caplog.at_level(logging.INFO, logger="veloraug.admin"):
        made = draft(api, admin, title="Fast X VJ Junior", year=2023)
    assert made["upload_key"].startswith("vu_")
    assert made["upload_key"] not in caplog.text
    ready(owner, made["item_id"])

    # The list answers first, then looks the ready draft up on TMDB.
    listed = api.get("/api/v1/admin/drafts", headers=as_user(admin)).json()
    assert made["edition_id"] in [e["id"] for e in listed["editions"]]
    state = edition(api, admin, made["edition_id"])
    assert state["tmdb_lookup"] == "clear"
    assert state["source_tmdb_id"] == tmdb_id
    assert state["poster_path"] == "/one.jpg"
    assert state["display_title"] == "Fast X VJ Junior"
    assert state["missing"] == ["a confirmed VJ credit"]

    credit = api.get(
        f"/api/v1/admin/editions/{made['edition_id']}/credit", headers=as_user(admin)
    ).json()
    assert credit["suggestions"] == [
        {"vj_id": None, "name": "VJ Junior", "found_in": "file name"}
    ]
    credited = api.put(
        f"/api/v1/admin/editions/{made['edition_id']}/credit",
        json={"new_vj": "VJ Junior"},
        headers=as_user(admin),
    )
    assert credited.json()["vj_name"] == "VJ Junior"
    api.patch(
        f"/api/v1/admin/editions/{made['edition_id']}",
        json={"display_title": "Fast X"},
        headers=as_user(admin),
    )

    published = api.post(
        f"/api/v1/admin/editions/{made['edition_id']}/publish", headers=as_user(admin)
    )
    assert published.status_code == 200, published.text
    assert published.json()["status"] == "published"
    # Viewers see it, with its trailer saved on the source.
    titles = [m["title"] for m in api.get("/api/v1/movies").json()["movies"]]
    assert "Fast X" in titles
    assert owner.execute(
        "select trailer_key from public.sources where tmdb_id = %s", (tmdb_id,)
    ).fetchone() == (f"trailer{tmdb_id}",)


@needs_database
def test_an_unclear_match_waits_for_the_admin(api, admin, owner, tmdb):
    first, second = new_tmdb_id(), new_tmdb_id()
    tmdb.search["The Lion King"] = [
        tmdb.add_movie(first, "The Lion King", 1994, posters=("/a.jpg", "/b.jpg")),
        tmdb.add_movie(second, "The Lion King", 2019),
    ]
    made = draft(api, admin, title="The Lion King")
    ready(owner, made["item_id"])

    found = api.post(
        f"/api/v1/admin/editions/{made['edition_id']}/tmdb/search",
        json={},
        headers=as_user(admin),
    ).json()
    assert found["outcome"] == "choose"
    assert [m["tmdb_id"] for m in found["edition"]["matches"]] == [first, second]

    chosen = api.put(
        f"/api/v1/admin/editions/{made['edition_id']}/source",
        json={"tmdb_id": first},
        headers=as_user(admin),
    ).json()
    assert chosen["source_tmdb_id"] == first
    assert chosen["matches"] == []
    # Two posters: the admin must choose.
    assert chosen["poster_path"] is None
    posters = api.get(
        f"/api/v1/admin/editions/{made['edition_id']}/posters", headers=as_user(admin)
    ).json()
    assert [p["path"] for p in posters["options"]] == ["/a.jpg", "/b.jpg"]
    refused = api.post(
        f"/api/v1/admin/editions/{made['edition_id']}/publish", headers=as_user(admin)
    )
    assert refused.status_code == 409
    assert refused.json()["detail"]["missing"] == [
        "a chosen poster",
        "a confirmed VJ credit",
    ]
    chose = api.put(
        f"/api/v1/admin/editions/{made['edition_id']}/poster",
        json={"path": "/b.jpg"},
        headers=as_user(admin),
    )
    assert chose.json()["poster_path"] == "/b.jpg"
    bad = api.put(
        f"/api/v1/admin/editions/{made['edition_id']}/poster",
        json={"path": "https://evil.example/x.jpg"},
        headers=as_user(admin),
    )
    assert bad.status_code == 400


@needs_database
def test_nothing_found_or_tmdb_down_keeps_the_draft(api, admin, owner, tmdb):
    made = draft(api, admin, title="Kampala Nights")
    ready(owner, made["item_id"])
    url = f"/api/v1/admin/editions/{made['edition_id']}"

    none = api.post(f"{url}/tmdb/search", json={}, headers=as_user(admin)).json()
    assert none["outcome"] == "none"
    tmdb.down = True
    failed = api.post(f"{url}/tmdb/search", json={}, headers=as_user(admin)).json()
    assert failed["outcome"] == "failed"
    assert failed["edition"]["status"] == "draft"
    missing = api.put(
        f"{url}/source", json={"tmdb_id": 999_999_999}, headers=as_user(admin)
    )
    assert missing.status_code == 503
    tmdb.down = False
    assert (
        api.put(
            f"{url}/source", json={"tmdb_id": 999_999_999}, headers=as_user(admin)
        ).status_code
        == 404
    )

    typed = api.put(
        f"{url}/source",
        json={
            "manual": {
                "title": "Kampala Nights",
                "overview": "A local film.",
                "year": 2024,
                "genres": ["Drama"],
            }
        },
        headers=as_user(admin),
    ).json()
    assert typed["details_from"] == "manual"
    assert typed["tmdb_lookup"] == "manual"
    assert typed["missing"] == ["a chosen poster", "a confirmed VJ credit"]


@needs_database
def test_a_preview_works_before_publishing(api, admin, owner):
    made = draft(api, admin)
    url = f"/api/v1/admin/items/{made['item_id']}/preview"

    assert api.post(url, headers=as_user(admin)).status_code == 409
    original = ready(owner, made["item_id"])
    response = api.post(url, headers=as_user(admin))

    assert response.status_code == 200
    token = response.json()["playlist_url"].removeprefix(f"{GATEWAY}/v1/").split("/")[0]
    payload = token.split(".")[0]
    decoded = json.loads(
        __import__("base64").urlsafe_b64decode(payload + "=" * (-len(payload) % 4))
    )
    assert (decoded["m"], decoded["o"]) == (made["item_id"], str(original))


@needs_database
def test_the_same_vj_cant_have_two_editions_of_one_title(api, admin, owner, tmdb):
    tmdb_id = new_tmdb_id()
    tmdb.add_movie(tmdb_id, "Fast X", 2023)
    first, second = draft(api, admin), draft(api, admin)
    for made in (first, second):
        api.put(
            f"/api/v1/admin/editions/{made['edition_id']}/source",
            json={"tmdb_id": tmdb_id},
            headers=as_user(admin),
        )
    vj = api.post(
        "/api/v1/admin/vjs", json={"name": "VJ Emmy"}, headers=as_user(admin)
    ).json()
    api.put(
        f"/api/v1/admin/editions/{first['edition_id']}/credit",
        json={"vj_id": vj["id"]},
        headers=as_user(admin),
    )

    again = api.put(
        f"/api/v1/admin/editions/{second['edition_id']}/credit",
        json={"vj_id": vj["id"]},
        headers=as_user(admin),
    )

    assert again.status_code == 400
    assert "already has an edition" in again.json()["detail"]


# --- Series ------------------------------------------------------------------


@needs_database
def test_a_new_episode_of_a_published_series_waits_for_approval(api, admin, owner):
    first = draft(api, admin, kind="series", title="Kabaka", season=1, episode=1)
    second = draft(
        api,
        admin,
        kind="series",
        series_edition_id=first["edition_id"],
        season=1,
        episode=2,
        key_label="VJ Emmy",
    )
    assert second["edition_id"] == first["edition_id"]
    ready(owner, first["item_id"])
    url = f"/api/v1/admin/editions/{first['edition_id']}"
    api.put(
        f"{url}/source",
        json={"manual": {"title": "Kabaka"}},
        headers=as_user(admin),
    )
    api.put(f"{url}/poster", json={"path": "/k.jpg"}, headers=as_user(admin))
    api.put(f"{url}/credit", json={"new_vj": "VJ Emmy"}, headers=as_user(admin))
    assert api.post(f"{url}/publish", headers=as_user(admin)).status_code == 200

    ready(owner, second["item_id"])
    waiting = [
        e
        for e in api.get("/api/v1/admin/drafts", headers=as_user(admin)).json()[
            "editions"
        ]
        if e["id"] == first["edition_id"]
    ]
    assert [i["approved"] for i in waiting[0]["items"]] == [True, False]
    approved = api.post(
        f"/api/v1/admin/items/{second['item_id']}/approve", headers=as_user(admin)
    )
    assert approved.status_code == 200
    assert all(i["approved"] for i in edition(api, admin, first["edition_id"])["items"])


@needs_database
def test_an_episode_number_cant_repeat(api, admin):
    first = draft(api, admin, kind="series", title="Kabaka", season=1, episode=1)
    response = api.post(
        "/api/v1/admin/drafts",
        json={
            "kind": "series",
            "series_edition_id": first["edition_id"],
            "season": 1,
            "episode": 1,
        },
        headers=as_user(admin),
    )
    assert response.status_code == 400
    assert "already exists" in response.json()["detail"]


# --- Keys, VJs and languages -------------------------------------------------


@needs_database
def test_another_key_can_be_made_and_revoked(api, admin, owner):
    made = draft(api, admin)
    key = api.post(
        f"/api/v1/admin/items/{made['item_id']}/keys",
        json={"label": "Kampala Films", "days": 2},
        headers=as_user(admin),
    )
    assert key.status_code == 201
    revoked = api.post(
        f"/api/v1/admin/keys/{key.json()['key_id']}/revoke", headers=as_user(admin)
    )
    assert revoked.status_code == 200
    keys = edition(api, admin, made["edition_id"])["items"][0]["keys"]
    assert [(k["label"], k["revoked"]) for k in keys] == [
        ("Kampala Films", True),
        ("Owner", False),
    ]
    assert all("upload_key" not in k and "key_hash" not in k for k in keys)


@needs_database
def test_vjs_and_languages_are_managed(api, admin, owner):
    added = api.post(
        "/api/v1/admin/vjs",
        json={"name": "VJ Ice P", "match_names": ["IceP", "icep"], "bio": "Kampala."},
        headers=as_user(admin),
    ).json()
    assert (added["slug"], added["match_names"]) == ("vj-ice-p", ["IceP"])
    same = api.post(
        "/api/v1/admin/vjs", json={"name": "vj ice p"}, headers=as_user(admin)
    )
    assert same.status_code == 400
    changed = api.patch(
        f"/api/v1/admin/vjs/{added['id']}",
        json={"bio": "From Kampala."},
        headers=as_user(admin),
    ).json()
    assert changed["bio"] == "From Kampala."

    assert (
        api.post(
            "/api/v1/admin/languages",
            json={"code": "nyn", "name": "Runyankole"},
            headers=as_user(admin),
        ).status_code
        == 201
    )
    try:
        codes = [
            lang["code"]
            for lang in api.get(
                "/api/v1/admin/languages", headers=as_user(admin)
            ).json()
        ]
        assert codes[0] == "lg" and "nyn" in codes
        assert api.post(
            "/api/v1/admin/languages",
            json={"code": "x1", "name": "Bad"},
            headers=as_user(admin),
        ).status_code in (400, 422)
    finally:
        owner.execute("delete from public.languages where code = 'nyn'")


def neon_auth():
    """The test server's superuser, in the test database: Neon Auth's tables
    are Neon's, so the owner only reads them."""
    from tests.db_support import DATABASE, admin_credentials, url_for

    return psycopg.connect(url_for(*admin_credentials(), DATABASE), autocommit=True)


# --- Admins ------------------------------------------------------------------


@needs_database
def test_an_admin_adds_and_removes_admins_by_verified_email(api, admin, owner):
    verified, unverified = uuid.uuid4(), uuid.uuid4()
    with neon_auth() as conn:
        conn.execute(
            'insert into neon_auth."user" (id, email, "emailVerified") values '
            "(%s, 'new.admin@example.test', true), (%s, 'not.yet@example.test', false)",
            (verified, unverified),
        )
    try:
        added = api.post(
            "/api/v1/admin/admins",
            json={"email": "New.Admin@example.test"},
            headers=as_user(admin),
        )
        assert added.status_code == 201
        assert added.json() == {"user_id": str(verified)}
        nope = api.post(
            "/api/v1/admin/admins",
            json={"email": "not.yet@example.test"},
            headers=as_user(admin),
        )
        assert nope.status_code == 404
        assert "confirm" in nope.json()["detail"]

        listed = api.get("/api/v1/admin/admins", headers=as_user(admin)).json()
        new = next(a for a in listed if a["user_id"] == str(verified))
        assert new["email"] == "new.admin@example.test"

        # The new admin can use the admin routes, and remove the first.
        assert api.get("/api/v1/admin/me", headers=as_user(verified)).status_code == 200
        assert (
            api.delete(
                f"/api/v1/admin/admins/{admin}", headers=as_user(verified)
            ).status_code
            == 200
        )
        last = api.delete(f"/api/v1/admin/admins/{verified}", headers=as_user(verified))
        assert last.status_code == 400
        assert "last admin" in last.json()["detail"]
    finally:
        owner.execute(
            "insert into public.admins (user_id) values (%s) on conflict do nothing",
            (admin,),
        )
        owner.execute("delete from public.admins where user_id = %s", (verified,))
        with neon_auth() as conn:
            conn.execute(
                'delete from neon_auth."user" where id in (%s, %s)',
                (verified, unverified),
            )


# --- Uploaded posters and VJ photos ------------------------------------------


def decode(token):
    import base64

    payload, signature = token.split(".")
    claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    return payload, signature, claims


@needs_database
def test_an_upload_address_is_signed_for_one_image(api, admin):
    import base64
    import hashlib
    import hmac

    made = draft(api, admin)
    response = api.post(
        "/api/v1/admin/images",
        json={
            "folder": "posters",
            "owner_id": made["edition_id"],
            "content_type": "image/png",
        },
        headers=as_user(admin),
    )

    assert response.status_code == 201
    body = response.json()
    assert body["path"].startswith(f"posters/{made['edition_id']}/")
    assert body["path"].endswith(".png")
    token = body["upload_url"].removeprefix(f"{GATEWAY}/i/")
    payload, signature, claims = decode(token)
    assert (claims["p"], claims["t"]) == (body["path"], "image/png")
    expected = hmac.new(
        KEY.encode(), b"veloraug-image-v1." + payload.encode(), hashlib.sha256
    ).digest()
    assert base64.urlsafe_b64encode(expected).rstrip(b"=").decode() == signature

    assert (
        api.post(
            "/api/v1/admin/images",
            json={
                "folder": "vjs",
                "owner_id": str(uuid.uuid4()),
                "content_type": "image/jpeg",
            },
            headers=as_user(admin),
        ).status_code
        == 404
    )
    assert (
        api.post(
            "/api/v1/admin/images",
            json={
                "folder": "posters",
                "owner_id": made["edition_id"],
                "content_type": "image/gif",
            },
            headers=as_user(admin),
        ).status_code
        == 422
    )


@needs_database
def test_an_uploaded_poster_and_photo_belong_to_their_own_edition_and_vj(api, admin):
    first, second = draft(api, admin), draft(api, admin)
    poster = f"posters/{first['edition_id']}/abcdefghijklmnopqrstuv.jpg"

    chosen = api.put(
        f"/api/v1/admin/editions/{first['edition_id']}/poster",
        json={"path": poster},
        headers=as_user(admin),
    )
    assert chosen.json()["poster_url"] == f"{GATEWAY}/i/{poster}"
    other = api.put(
        f"/api/v1/admin/editions/{second['edition_id']}/poster",
        json={"path": poster},
        headers=as_user(admin),
    )
    assert other.status_code == 400

    vj = api.post(
        "/api/v1/admin/vjs", json={"name": "VJ Junior"}, headers=as_user(admin)
    ).json()
    photo = f"vjs/{vj['id']}/abcdefghijklmnopqrstuv.webp"
    changed = api.patch(
        f"/api/v1/admin/vjs/{vj['id']}",
        json={"photo_path": photo},
        headers=as_user(admin),
    ).json()
    assert changed["photo_url"] == f"{GATEWAY}/i/{photo}"
    wrong = api.patch(
        f"/api/v1/admin/vjs/{vj['id']}",
        json={"photo_path": f"vjs/{uuid.uuid4()}/abcdefghijklmnopqrstuv.webp"},
        headers=as_user(admin),
    )
    assert wrong.status_code == 400
    removed = api.patch(
        f"/api/v1/admin/vjs/{vj['id']}", json={"photo_path": ""}, headers=as_user(admin)
    ).json()
    assert removed["photo_url"] is None
