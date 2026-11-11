"""The catalogue routes and the TMDB refresher, on a real Postgres.

TMDB is replaced by a mock transport, and the refresher's clock by a fake.
Skipped without a local test Postgres: see tests/db_support.py.
"""

import logging
import uuid
from datetime import timedelta

import httpx2
import psycopg
import pytest
from fastapi.testclient import TestClient

from app.catalogue import RETRY_AFTER_FAILURE_SECONDS, Refresher
from app.db import Database
from app.main import create_app
from app.tmdb import TmdbClient
from scripts.catalogue import add_movie, set_published
from tests.db_support import needs_database
from tests.test_catalogue import details

pytestmark = needs_database

TOKEN = "eyJ-test-token-SECRET"


class FakeTmdb:
    """TMDB as a mock transport: answers per movie, and counts requests."""

    def __init__(self) -> None:
        self.titles: dict[int, str] = {}
        self.status: dict[int, int] = {}
        self.headers: dict[str, str] = {}
        self.requests: list[str] = []

    def handle(self, request: httpx2.Request) -> httpx2.Response:
        path = request.url.path.removeprefix("/3")
        self.requests.append(path)
        if path == "/configuration":
            return httpx2.Response(
                200,
                json={
                    "images": {
                        "secure_base_url": "https://image.tmdb.org/t/p/",
                        "poster_sizes": ["w92", "w342", "w500", "original"],
                        "backdrop_sizes": ["w300", "w780", "w1280", "original"],
                    }
                },
            )
        tmdb_id = int(path.rsplit("/", 1)[1])
        status = self.status.get(tmdb_id, 200)
        if status != 200:
            return httpx2.Response(status, headers=self.headers)
        return httpx2.Response(
            200,
            json={
                "id": tmdb_id,
                "title": self.titles.get(tmdb_id, f"Fresh {tmdb_id}"),
                "release_date": "2020-02-02",
                "runtime": 90,
                "genres": [{"name": "Drama"}],
                "poster_path": "/fresh.jpg",
                "backdrop_path": "/fresh-back.jpg",
            },
        )

    def movie_requests(self) -> list[str]:
        return [p for p in self.requests if p.startswith("/movie/")]


class Clock:
    def __init__(self) -> None:
        self.now = 1_000.0

    def __call__(self) -> float:
        return self.now


@pytest.fixture
def owner(owner_url, app_url):
    """The owner's connection, on an empty catalogue."""
    with psycopg.connect(owner_url, autocommit=True) as conn:
        conn.execute("delete from public.movies")
        yield conn
        conn.execute("delete from public.movies")


@pytest.fixture
def tmdb():
    return FakeTmdb()


@pytest.fixture
def clock():
    return Clock()


@pytest.fixture
def make_api(app_url, tmdb, clock):
    made = []

    def make(*, with_tmdb: bool = True) -> TestClient:
        database = Database(app_url)
        refresher = None
        if with_tmdb:
            client = TmdbClient(TOKEN, transport=httpx2.MockTransport(tmdb.handle))
            refresher = Refresher(database, client, clock=clock)
        app = create_app(database=database, refresher=refresher)
        test_client = TestClient(app)
        test_client.__enter__()
        made.append(test_client)
        return test_client

    yield make
    for test_client in made:
        test_client.__exit__(None, None, None)


@pytest.fixture
def api(make_api):
    return make_api()


def new_id() -> int:
    return 2_000_000 + uuid.uuid4().int % 1_000_000_000


def published(owner, title: str, *, age_days: float = 0, poster: bool = True):
    """A published movie whose copy is age_days old. Its VeloraUG ID."""
    tmdb_id = new_id()
    movie = details(tmdb_id, title)
    if not poster:
        from dataclasses import replace

        movie = replace(movie, poster_path=None, backdrop_path=None)
    movie_id = add_movie(owner, movie)
    set_published(owner, str(tmdb_id), True)
    age(owner, tmdb_id, age_days)
    return movie_id, tmdb_id


def age(owner, tmdb_id: int, days: float) -> None:
    owner.execute(
        "update public.tmdb_movie_details set fetched_at = now() - %s "
        "where tmdb_id = %s",
        (timedelta(days=days), tmdb_id),
    )


def title_of(owner, tmdb_id):
    row = owner.execute(
        "select title from public.tmdb_movie_details where tmdb_id = %s", (tmdb_id,)
    ).fetchone()
    return row[0] if row else None


# --- Lists -------------------------------------------------------------------


def test_the_list_shows_published_movies_newest_first(api, owner):
    first, _ = published(owner, "First")
    second, _ = published(owner, "Second")
    hidden_tmdb = new_id()
    add_movie(owner, details(hidden_tmdb, "Hidden"))

    response = api.get("/api/v1/movies")

    assert response.status_code == 200
    body = response.json()
    assert [m["title"] for m in body["movies"]] == ["Second", "First"]
    assert body["next_offset"] is None
    assert body["movies"][0] == {
        "id": str(second),
        "title": "Second",
        "year": 2024,
        "poster_url": "https://image.tmdb.org/t/p/w342/poster.jpg",
    }


def test_the_list_needs_no_token_and_ignores_one(api, owner):
    published(owner, "Open")

    plain = api.get("/api/v1/movies")
    with_token = api.get("/api/v1/movies", headers={"Authorization": "Bearer junk"})

    assert plain.status_code == with_token.status_code == 200
    assert plain.json()["movies"] == with_token.json()["movies"]


def test_pages_follow_next_offset(api, owner):
    for n in range(5):
        published(owner, f"Movie {n}")

    first = api.get("/api/v1/movies", params={"limit": 2}).json()
    second = api.get("/api/v1/movies", params={"limit": 2, "offset": 2}).json()
    last = api.get("/api/v1/movies", params={"limit": 2, "offset": 4}).json()

    assert [len(p["movies"]) for p in (first, second, last)] == [2, 2, 1]
    assert (first["next_offset"], second["next_offset"], last["next_offset"]) == (
        2,
        4,
        None,
    )
    titles = [m["title"] for p in (first, second, last) for m in p["movies"]]
    assert sorted(titles) == [f"Movie {n}" for n in range(5)]


@pytest.mark.parametrize(
    "params",
    [
        {"limit": 0},
        {"limit": 51},
        {"offset": -1},
        {"q": "a"},
        {"q": " a "},
        {"q": "x" * 81},
    ],
)
def test_bad_list_parameters_are_refused(api, params):
    assert api.get("/api/v1/movies", params=params).status_code == 422


def test_search_puts_title_starts_first_and_ignores_case(api, owner):
    published(owner, "The Matrix")
    published(owner, "Matrix Reloaded")
    published(owner, "Inception")

    body = api.get("/api/v1/movies", params={"q": "  MATRIX "}).json()

    assert [m["title"] for m in body["movies"]] == ["Matrix Reloaded", "The Matrix"]


def test_search_treats_wildcards_as_plain_text(api, owner):
    published(owner, "100% Wolf")
    published(owner, "1000 Ways")

    assert [
        m["title"]
        for m in api.get("/api/v1/movies", params={"q": "0%"}).json()["movies"]
    ] == ["100% Wolf"]
    assert api.get("/api/v1/movies", params={"q": "__"}).json()["movies"] == []


def test_a_movie_without_images_has_null_urls(api, owner):
    movie_id, _ = published(owner, "Plain", poster=False)

    assert api.get("/api/v1/movies").json()["movies"][0]["poster_url"] is None
    detail = api.get(f"/api/v1/movies/{movie_id}").json()
    assert detail["poster_url"] is None and detail["backdrop_url"] is None


# --- Detail ------------------------------------------------------------------


def test_the_detail_has_every_field(api, owner):
    movie_id, tmdb_id = published(owner, "Mine")

    response = api.get(f"/api/v1/movies/{movie_id}")

    assert response.status_code == 200
    assert response.json() == {
        "id": str(movie_id),
        "title": "Mine",
        "year": 2024,
        "overview": "An overview.",
        "runtime_minutes": 101,
        "genres": ["Drama", "Comedy"],
        "poster_url": "https://image.tmdb.org/t/p/w342/poster.jpg",
        "backdrop_url": "https://image.tmdb.org/t/p/w780/backdrop.jpg",
    }
    # VeloraUG's ID only: the TMDB ID never leaves the API.
    assert str(tmdb_id) not in response.text


def test_missing_and_hidden_movies_answer_the_same_404(api, owner):
    hidden_tmdb = new_id()
    hidden_id = add_movie(owner, details(hidden_tmdb, "Hidden"))

    missing = api.get(f"/api/v1/movies/{uuid.uuid4()}")
    hidden = api.get(f"/api/v1/movies/{hidden_id}")

    assert missing.status_code == hidden.status_code == 404
    assert missing.json() == hidden.json() == {"detail": "This movie isn't available."}


def test_an_unpublished_movie_disappears_at_once(api, owner):
    movie_id, tmdb_id = published(owner, "Gone soon")
    assert api.get(f"/api/v1/movies/{movie_id}").status_code == 200

    set_published(owner, str(tmdb_id), False)

    assert api.get(f"/api/v1/movies/{movie_id}").status_code == 404
    assert api.get("/api/v1/movies").json()["movies"] == []


def test_a_malformed_id_is_refused(api):
    assert api.get("/api/v1/movies/not-a-uuid").status_code == 422


# --- Ages and refreshing -----------------------------------------------------


def test_a_fresh_copy_is_served_without_calling_tmdb(api, owner, tmdb):
    movie_id, _ = published(owner, "Fresh", age_days=6)

    api.get("/api/v1/movies")
    api.get(f"/api/v1/movies/{movie_id}")

    assert tmdb.movie_requests() == []


def test_an_old_copy_is_served_then_refreshed_once(api, owner, tmdb):
    movie_id, tmdb_id = published(owner, "Old title", age_days=8)
    tmdb.titles[tmdb_id] = "New title"

    response = api.get(f"/api/v1/movies/{movie_id}")

    # Served as it was. The refresh ran after the response.
    assert response.json()["title"] == "Old title"
    assert title_of(owner, tmdb_id) == "New title"
    assert tmdb.movie_requests() == [f"/movie/{tmdb_id}"]

    # Now fresh, so no more requests.
    assert api.get(f"/api/v1/movies/{movie_id}").json()["title"] == "New title"
    api.get("/api/v1/movies")
    assert tmdb.movie_requests() == [f"/movie/{tmdb_id}"]


def test_a_list_refreshes_its_old_copies(api, owner, tmdb):
    _, old = published(owner, "Old", age_days=30)
    _, fresh = published(owner, "Fresh")

    api.get("/api/v1/movies")

    assert tmdb.movie_requests() == [f"/movie/{old}"]
    assert title_of(owner, old) == f"Fresh {old}"
    assert title_of(owner, fresh) == "Fresh"


@pytest.mark.parametrize("days", [150, 200])
def test_an_expired_copy_is_never_served(make_api, owner, days):
    movie_id, _ = published(owner, "Expired", age_days=days)
    api = make_api(with_tmdb=False)

    assert api.get("/api/v1/movies").json()["movies"] == []
    response = api.get(f"/api/v1/movies/{movie_id}")
    assert response.status_code == 503
    assert response.headers["Retry-After"] == "30"
    assert "Expired" not in response.text


def test_an_expired_copy_is_fetched_in_the_background(api, owner, tmdb):
    movie_id, tmdb_id = published(owner, "Expired", age_days=151)

    assert api.get(f"/api/v1/movies/{movie_id}").status_code == 503
    after = api.get(f"/api/v1/movies/{movie_id}")

    assert after.status_code == 200
    assert after.json()["title"] == f"Fresh {tmdb_id}"


def test_a_published_movie_with_no_copy_is_fetched(api, owner, tmdb):
    movie_id, tmdb_id = published(owner, "Will vanish")
    owner.execute(
        "delete from public.tmdb_movie_details where tmdb_id = %s", (tmdb_id,)
    )

    assert api.get("/api/v1/movies").json()["movies"] == []
    # The list's sweep found it and fetched it after answering.
    assert title_of(owner, tmdb_id) == f"Fresh {tmdb_id}"
    assert api.get(f"/api/v1/movies/{movie_id}").status_code == 200


def test_without_a_token_old_copies_are_served_and_not_refreshed(make_api, owner):
    movie_id, tmdb_id = published(owner, "Old", age_days=100)
    api = make_api(with_tmdb=False)

    assert api.get(f"/api/v1/movies/{movie_id}").json()["title"] == "Old"
    assert title_of(owner, tmdb_id) == "Old"


def test_a_failed_fetch_waits_before_trying_again(api, owner, tmdb, clock):
    movie_id, tmdb_id = published(owner, "Old", age_days=10)
    tmdb.status[tmdb_id] = 503

    api.get(f"/api/v1/movies/{movie_id}")
    api.get(f"/api/v1/movies/{movie_id}")
    assert tmdb.movie_requests() == [f"/movie/{tmdb_id}"]

    clock.now += RETRY_AFTER_FAILURE_SECONDS + 1
    tmdb.status.pop(tmdb_id)
    api.get(f"/api/v1/movies/{movie_id}")

    assert len(tmdb.movie_requests()) == 2
    assert title_of(owner, tmdb_id) == f"Fresh {tmdb_id}"


def test_tmdb_asking_to_wait_pauses_every_fetch(api, owner, tmdb, clock):
    first_id, first = published(owner, "One", age_days=10)
    second_id, second = published(owner, "Two", age_days=10)
    tmdb.status[first] = 429
    tmdb.headers = {"Retry-After": "60"}

    api.get(f"/api/v1/movies/{first_id}")
    api.get(f"/api/v1/movies/{second_id}")
    assert tmdb.movie_requests() == [f"/movie/{first}"]

    clock.now += 61
    api.get(f"/api/v1/movies/{second_id}")
    assert tmdb.movie_requests()[-1] == f"/movie/{second}"


def test_a_refused_token_stops_refreshing(api, owner, tmdb, clock, caplog):
    first_id, first = published(owner, "One", age_days=10)
    second_id, _ = published(owner, "Two", age_days=10)
    tmdb.status[first] = 401

    with caplog.at_level(logging.WARNING, logger="veloraug.catalogue"):
        api.get(f"/api/v1/movies/{first_id}")
        clock.now += 24 * 60 * 60
        api.get(f"/api/v1/movies/{second_id}")

    assert tmdb.movie_requests() == [f"/movie/{first}"]
    assert "refused the token" in caplog.text


def test_tmdb_deleting_a_movie_keeps_its_copy(api, owner, tmdb, caplog):
    movie_id, tmdb_id = published(owner, "Kept", age_days=10)
    tmdb.status[tmdb_id] = 404

    with caplog.at_level(logging.WARNING, logger="veloraug.catalogue"):
        response = api.get(f"/api/v1/movies/{movie_id}")

    assert response.json()["title"] == "Kept"
    assert title_of(owner, tmdb_id) == "Kept"
    assert f"TMDB has no movie {tmdb_id}" in caplog.text


def test_the_token_never_reaches_a_response_or_a_log(api, owner, tmdb, caplog):
    movie_id, tmdb_id = published(owner, "Old", age_days=10)
    tmdb.status[tmdb_id] = 500

    with caplog.at_level(logging.DEBUG):
        responses = [
            api.get("/api/v1/movies"),
            api.get(f"/api/v1/movies/{movie_id}"),
        ]

    assert TOKEN not in caplog.text
    for response in responses:
        assert TOKEN not in response.text


def test_image_settings_come_from_tmdb_once_a_day(api, owner, tmdb, clock):
    published(owner, "Old", age_days=10)

    api.get("/api/v1/movies")
    api.get("/api/v1/movies")

    assert tmdb.requests.count("/configuration") == 1
    clock.now += 24 * 60 * 60 + 1
    published(owner, "Another old", age_days=10)
    api.get("/api/v1/movies")
    assert tmdb.requests.count("/configuration") == 2


def test_cors_lets_the_web_app_read_the_list(api, owner):
    published(owner, "Seen from the web")

    response = api.get("/api/v1/movies", headers={"Origin": "http://localhost:8765"})

    assert response.headers["access-control-allow-origin"] == "http://localhost:8765"
