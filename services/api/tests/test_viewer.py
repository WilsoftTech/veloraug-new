"""Viewers' catalogue routes, Step 9D, on a real Postgres.

Skipped without a local test Postgres: see tests/db_support.py.
"""

import base64
import json
import uuid
from datetime import timedelta

import psycopg
import pytest
from fastapi.testclient import TestClient

from app import editions
from app.db import Database
from app.main import create_app
from app.playback import Granter
from tests.db_support import add_movie, delete_editions, needs_database, set_published
from tests.test_admin import ready
from tests.test_catalogue import details
from tests.test_database import FakeVerifier, as_user

KEY = "a-test-signing-key-that-is-long-enough-000"
GATEWAY = "http://127.0.0.1:8787"


@pytest.fixture
def owner(owner_url, app_url):
    with psycopg.connect(owner_url, autocommit=True) as conn:
        delete_editions(conn)
        conn.execute("delete from public.vjs")
        yield conn
        delete_editions(conn)
        conn.execute("delete from public.vjs")
        conn.execute("delete from public.languages where code <> 'lg'")


@pytest.fixture
def api(app_url):
    app = create_app(
        token_verifier=FakeVerifier(),
        database=Database(app_url),
        granter=Granter(key=KEY.encode(), gateway_url=GATEWAY),
    )
    with TestClient(app) as client:
        yield client


def vj(owner, name):
    slug = name.lower().replace(" ", "-")
    return owner.execute(
        "insert into public.vjs (name, slug, bio, photo_path) values (%s, %s, %s, %s) "
        "returning id",
        (name, slug, f"About {name}.", None),
    ).fetchone()[0]


def describe(owner, edition_id, *, vj_id, title, tmdb_id=None, genres=("Action",)):
    kind = owner.execute(
        "select kind from public.editions where id = %s", (edition_id,)
    ).fetchone()[0]
    (source,) = owner.execute(
        """
        insert into public.sources (kind, tmdb_id, title, overview, release_date,
          genres, backdrop_path, trailer_key, details_from, fetched_at)
        values (%s, %s, %s, 'An overview.', '2023-05-01', %s, '/back.jpg', 'abc123',
                case when %s::int is null then 'manual' else 'tmdb' end, now())
        returning id
        """,
        (kind, tmdb_id, title, list(genres), tmdb_id),
    ).fetchone()
    owner.execute(
        "update public.editions set source_id = %s, vj_id = %s, poster_path = '/p.jpg' "
        "where id = %s",
        (source, vj_id, edition_id),
    )


@pytest.fixture
def catalogue(owner):
    """A published movie and series by two VJs, a draft, and a test film."""
    junior, emmy = vj(owner, "VJ Junior"), vj(owner, "VJ Emmy")
    vj(owner, "VJ Nobody")
    movie = editions.create_draft(owner, kind="movie", title="Fast X")
    describe(owner, movie.edition_id, vj_id=junior, title="Fast X", tmdb_id=385687)
    ready(owner, movie.item_id)
    editions.publish(owner, movie.edition_id)

    first = editions.create_draft(
        owner, kind="series", title="Kabaka", season=1, episode=1
    )
    second = editions.create_draft(
        owner, kind="series", series_edition=first.edition_id, season=1, episode=2
    )
    third = editions.create_draft(
        owner, kind="series", series_edition=first.edition_id, season=2, episode=1
    )
    describe(owner, first.edition_id, vj_id=emmy, title="Kabaka", genres=("Drama",))
    ready(owner, first.item_id)
    ready(owner, third.item_id)
    editions.publish(owner, first.edition_id)
    ready(owner, second.item_id)  # Ready after publishing: waits for approval.

    draft = editions.create_draft(owner, kind="movie", title="Secret Draft")
    film = add_movie(owner, details(42, "The Matrix"))
    set_published(owner, str(film), True)
    return {
        "junior": junior,
        "emmy": emmy,
        "movie": movie,
        "series": first,
        "second": second,
        "third": third,
        "draft": draft,
        "film": film,
    }


def cards(api, **params):
    response = api.get("/api/v1/editions", params=params)
    assert response.status_code == 200, response.text
    return response.json()["editions"]


@needs_database
def test_only_published_editions_are_listed_with_their_vj(api, catalogue):
    listed = {card["title"]: card for card in cards(api)}

    assert set(listed) == {"Fast X", "Kabaka", "The Matrix"}
    assert listed["Fast X"]["vj_name"] == "VJ Junior"
    assert listed["Fast X"]["label"] == "Luganda · VJ Junior"
    assert listed["Fast X"]["poster_url"] == "https://image.tmdb.org/t/p/w342/p.jpg"
    assert listed["Kabaka"]["kind"] == "series"
    assert listed["The Matrix"]["label"] == "Test"
    assert listed["The Matrix"]["vj_name"] is None


@needs_database
@pytest.mark.parametrize(
    ("params", "titles"),
    [
        ({"kind": "movie"}, {"Fast X", "The Matrix"}),
        ({"kind": "series"}, {"Kabaka"}),
        ({"vj": "vj-emmy"}, {"Kabaka"}),
        ({"genre": "Drama"}, {"Kabaka", "The Matrix"}),
        ({"language": "lg"}, {"Fast X", "Kabaka", "The Matrix"}),
        ({"q": "emmy"}, {"Kabaka"}),
        ({"q": "fast"}, {"Fast X"}),
        ({"q": "secret"}, set()),
    ],
)
def test_editions_can_be_filtered_and_searched(api, catalogue, params, titles):
    assert {card["title"] for card in cards(api, **params)} == titles


@needs_database
def test_pages_follow_on(api, catalogue):
    first = api.get("/api/v1/editions", params={"limit": 2}).json()
    second = api.get(
        "/api/v1/editions", params={"limit": 2, "offset": first["next_offset"]}
    ).json()

    assert first["next_offset"] == 2
    assert len(first["editions"]) == 2 and len(second["editions"]) == 1
    assert second["next_offset"] is None


@needs_database
def test_a_movie_edition_names_its_item_and_trailer(api, catalogue):
    movie = catalogue["movie"]
    detail = api.get(f"/api/v1/editions/{movie.edition_id}").json()

    assert detail["label"] == "Luganda · VJ Junior"
    assert detail["item_id"] == str(movie.item_id)
    assert detail["playable"] is True
    assert detail["trailer_url"] == "https://www.youtube.com/watch?v=abc123"
    assert detail["backdrop_url"] == "https://image.tmdb.org/t/p/w780/back.jpg"
    assert detail["seasons"] == []


@needs_database
def test_a_series_shows_its_approved_episodes_by_season(api, catalogue):
    series = catalogue["series"]
    detail = api.get(f"/api/v1/editions/{series.edition_id}").json()

    assert detail["item_id"] is None
    assert [
        (s["season"], [e["episode"] for e in s["episodes"]]) for s in detail["seasons"]
    ] == [(1, [1]), (2, [1])]
    assert detail["seasons"][0]["episodes"][0]["item_id"] == str(series.item_id)


@needs_database
def test_drafts_and_unknown_editions_are_404_alike(api, catalogue):
    for edition_id in (catalogue["draft"].edition_id, uuid.uuid4()):
        response = api.get(f"/api/v1/editions/{edition_id}")
        assert response.status_code == 404
        assert response.json() == {"detail": "This isn't available."}


@needs_database
def test_an_expired_tmdb_copy_isnt_shown(api, owner, catalogue):
    owner.execute(
        "update public.sources set fetched_at = now() - %s where tmdb_id = 385687",
        (timedelta(days=151),),
    )

    response = api.get(f"/api/v1/editions/{catalogue['movie'].edition_id}")

    assert response.status_code == 503
    assert "Fast X" not in {card["title"] for card in cards(api)}


# --- VJs and languages -------------------------------------------------------


@needs_database
def test_only_vjs_with_something_published_are_listed(api, catalogue):
    listed = api.get("/api/v1/vjs").json()

    assert [(v["name"], v["slug"], v["editions"]) for v in listed] == [
        ("VJ Emmy", "vj-emmy", 1),
        ("VJ Junior", "vj-junior", 1),
    ]


@needs_database
def test_a_vjs_page_has_their_bio_movies_and_series(api, catalogue):
    page = api.get("/api/v1/vjs/vj-emmy").json()

    assert page["bio"] == "About VJ Emmy."
    assert page["movies"] == []
    assert [card["title"] for card in page["series"]] == ["Kabaka"]
    assert api.get("/api/v1/vjs/vj-nobody").status_code == 404
    assert api.get("/api/v1/vjs/nobody-at-all").status_code == 404


@needs_database
def test_languages_with_published_editions_are_listed(api, owner, catalogue):
    owner.execute(
        "insert into public.languages (code, name) values ('nyn', 'Runyankole')"
    )

    assert api.get("/api/v1/languages").json() == [
        {"code": "lg", "name": "Luganda", "editions": 2}
    ]


@needs_database
def test_genres_are_the_exact_values_the_genre_filter_matches(api, catalogue):
    genres = api.get("/api/v1/genres").json()

    # The test film isn't counted, as on Home.
    assert genres == [
        {"name": "Action", "editions": 1},
        {"name": "Drama", "editions": 1},
    ]
    for genre in genres:
        assert len(cards(api, genre=genre["name"])) >= genre["editions"]


@needs_database
@pytest.mark.parametrize(
    ("params", "titles"),
    [
        ({"kind": "movie", "genre": "Action", "vj": "vj-junior"}, {"Fast X"}),
        ({"kind": "series", "genre": "Action"}, set()),
        ({"genre": "Drama", "vj": "vj-junior"}, set()),
        ({"genre": "Drama", "language": "lg", "kind": "series"}, {"Kabaka"}),
        # Exact values only: no partial or different-case matches.
        ({"genre": "drama"}, set()),
        ({"genre": "Dram"}, set()),
    ],
)
def test_filters_combine(api, catalogue, params, titles):
    assert {card["title"] for card in cards(api, **params)} == titles


# --- Playback by item --------------------------------------------------------


def grant_for(api, item_id, user=None):
    return api.post(
        f"/api/v1/items/{item_id}/playback", headers=as_user(user or uuid.uuid4())
    )


@needs_database
def test_an_episode_is_granted_by_its_item(api, catalogue):
    response = grant_for(api, catalogue["third"].item_id)

    assert response.status_code == 200
    token = response.json()["playlist_url"].removeprefix(f"{GATEWAY}/v1/").split("/")[0]
    payload = token.split(".")[0]
    claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    assert claims["m"] == str(catalogue["third"].item_id)


@needs_database
def test_unapproved_episodes_drafts_and_strangers_are_refused(api, owner, catalogue):
    assert (
        api.post(f"/api/v1/items/{catalogue['movie'].item_id}/playback").status_code
        == 401
    )
    for item_id in (
        catalogue["second"].item_id,
        catalogue["draft"].item_id,
        uuid.uuid4(),
    ):
        assert grant_for(api, item_id).status_code == 404

    owner.execute(
        "update public.media_originals set state = 'removing' where item_id = %s",
        (catalogue["movie"].item_id,),
    )
    assert grant_for(api, catalogue["movie"].item_id).status_code == 409
    detail = api.get(f"/api/v1/editions/{catalogue['movie'].edition_id}").json()
    assert detail["playable"] is False


@needs_database
def test_films_from_before_keep_their_ids_on_the_new_routes(api, catalogue):
    """The Milestone 6 routes are gone since Step 9E. A film from before
    Milestone 9 keeps its ID as its edition's and its item's."""
    film = catalogue["film"]

    assert api.get(f"/api/v1/movies/{film}").status_code == 404
    assert api.get("/api/v1/movies").status_code == 404
    detail = api.get(f"/api/v1/editions/{film}").json()
    assert detail["title"] == "The Matrix"
    assert detail["item_id"] == str(film)
