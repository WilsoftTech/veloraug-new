"""Discovery rails on an edition's page, and Because you watched, on a real
Postgres. Skipped without a local test Postgres: see tests/db_support.py."""

# The owner and api fixtures come from test_viewer; ruff reads each use of
# them as a parameter as redefining the import.
# ruff: noqa: F811

import uuid
from datetime import timedelta

import psycopg
import pytest

from app import editions
from tests.db_support import add_movie, needs_database, set_published
from tests.test_admin import ready
from tests.test_catalogue import details
from tests.test_database import as_user
from tests.test_viewer import api, describe, owner, vj  # noqa: F401

pytestmark = needs_database


def title(
    owner,
    name,
    *,
    vj_id,
    kind="movie",
    genres=("Action",),
    days_ago=60,
    rating=None,
    votes=None,
    popularity=None,
):
    """A published edition, published `days_ago`. Its edition ID."""
    draft = editions.create_draft(
        owner,
        kind=kind,
        title=name,
        **({"season": 1, "episode": 1} if kind == "series" else {}),
    )
    describe(owner, draft.edition_id, vj_id=vj_id, title=name, genres=genres)
    ready(owner, draft.item_id)
    editions.publish(owner, draft.edition_id)
    when = timedelta(days=days_ago)
    owner.execute(
        "update public.editions set published_at = now() - %s where id = %s",
        (when, draft.edition_id),
    )
    owner.execute(
        "update public.items set approved_at = now() - %s where edition_id = %s",
        (when, draft.edition_id),
    )
    owner.execute(
        """
        update public.sources set tmdb_rating = %s, tmdb_vote_count = %s,
          tmdb_popularity = %s
        where id = (select source_id from public.editions where id = %s)
        """,
        (rating, votes, popularity, draft.edition_id),
    )
    return draft.edition_id


def share_source(owner, edition_id, with_edition_id):
    """Makes an edition another VJ's version of the same source title."""
    owner.execute(
        "update public.editions set source_id = "
        "(select source_id from public.editions where id = %s) where id = %s",
        (with_edition_id, edition_id),
    )


def watched(owner, edition_id, *, users=1, days_ago=1, position=600):
    """`users` new viewers who played the edition `days_ago`."""
    item = owner.execute(
        "select id from public.items where edition_id = %s limit 1", (edition_id,)
    ).fetchone()[0]
    ids = []
    for _ in range(users):
        user = uuid.uuid4()
        owner.execute(
            """
            insert into public.watch_history
              (user_id, item_id, last_watched_at, position_seconds, position_at)
            values (%s, %s, now() - %s, %s, now())
            """,
            (user, item, timedelta(days=days_ago), position),
        )
        ids.append(user)
    return ids


@pytest.fixture
def clean_history(owner):
    owner.execute("delete from public.watch_history")
    yield
    owner.execute("delete from public.watch_history")


def rails(api, edition_id):
    response = api.get(f"/api/v1/editions/{edition_id}/rails")
    assert response.status_code == 200, response.text
    return {
        rail["key"]: [card["title"] for card in rail["editions"]]
        for rail in response.json()["rails"]
    }


def keys(api, edition_id):
    response = api.get(f"/api/v1/editions/{edition_id}/rails")
    return [rail["key"] for rail in response.json()["rails"]]


# --- Movies ------------------------------------------------------------------


@pytest.fixture
def movies(owner, clean_history):
    """Fast X by VJ Junior (Action, Crime), and titles around it."""
    junior, emmy = vj(owner, "VJ Junior"), vj(owner, "VJ Emmy")
    seed = title(owner, "Fast X", vj_id=junior, genres=("Action", "Crime"))
    made = {"seed": seed, "junior": junior, "emmy": emmy}
    # By the same VJ, newest last.
    for n, days in ((1, 50), (2, 40), (3, 30)):
        made[f"J{n}"] = title(
            owner, f"J{n}", vj_id=junior, genres=("Drama",), days_ago=days
        )
    made["A1"] = title(owner, "A1", vj_id=emmy, genres=("Action", "Crime"))
    made["A2"] = title(
        owner, "A2", vj_id=emmy, genres=("Action",), rating=9.0, votes=100
    )
    made["A3"] = title(owner, "A3", vj_id=junior, genres=("Action",), days_ago=70)
    # Another VJ's Fast X: never recommended from Fast X.
    made["other"] = title(owner, "Fast X by Emmy", vj_id=emmy, genres=("Action",))
    share_source(owner, made["other"], seed)
    # A series and a test film: never in a movie's rails.
    title(owner, "Kabaka", vj_id=junior, kind="series", genres=("Action",))
    film = add_movie(owner, details(42, "The Matrix"))
    set_published(owner, str(film), True)
    return made


def test_a_movie_has_its_rails_in_order(api, movies):
    assert keys(api, movies["seed"]) == ["vj", "recommended", "popular", "recent"]


def test_more_from_the_vj_is_newest_first(api, movies):
    # A3 is by Junior too, but older than all three.
    assert rails(api, movies["seed"])["vj"] == ["J3", "J2", "J1", "A3"]


def test_recommended_scores_shared_genres_vj_and_rating(api, movies):
    # A1: two shared genres, 6. A3: one, and the same VJ, 4. A2: one, and a
    # 9.0 rating, 3.9. The J titles share no genre.
    assert rails(api, movies["seed"])["recommended"] == ["A1", "A3", "A2"]


def test_a_recent_title_gets_a_small_bonus(api, owner, movies):
    owner.execute(
        "update public.editions set published_at = now() - interval '2 days' "
        "where id = %s",
        (movies["A2"],),
    )

    # A2 now scores 4.4, above A3's 4.
    assert rails(api, movies["seed"])["recommended"] == ["A1", "A2", "A3"]


def test_no_rail_has_the_title_another_vjs_version_a_series_or_a_test_film(api, movies):
    for titles in rails(api, movies["seed"]).values():
        assert "Fast X" not in titles
        assert "Fast X by Emmy" not in titles
        assert "Kabaka" not in titles
        assert "The Matrix" not in titles


def test_a_rail_with_fewer_than_three_titles_is_left_out(api, owner, movies):
    # Only two titles share a genre with A2 once A1 and A3 are hidden.
    for name in ("A1", "A3"):
        owner.execute(
            "update public.editions set status = 'hidden' where id = %s",
            (movies[name],),
        )

    found = rails(api, movies["seed"])
    assert "recommended" not in found
    assert "top_rated" not in found


def test_most_popular_counts_our_own_viewers_then_tmdb(api, owner, movies):
    watched(owner, movies["J1"], users=3)
    watched(owner, movies["A2"], users=2)
    # Not counted: too long ago, and a grant with nothing played.
    watched(owner, movies["J2"], users=5, days_ago=40)
    watched(owner, movies["J3"], users=5, position=None)
    owner.execute(
        "update public.sources set tmdb_popularity = 50 where id = "
        "(select source_id from public.editions where id = %s)",
        (movies["A3"],),
    )

    popular = rails(api, movies["seed"])["popular"]

    assert popular[:3] == ["J1", "A2", "A3"]


def test_top_rated_needs_ten_votes(api, owner, movies):
    for name, rating, votes in (
        ("J1", 8.0, 50),
        ("J2", 9.5, 9),
        ("J3", 7.0, 10),
    ):
        owner.execute(
            "update public.sources set tmdb_rating = %s, tmdb_vote_count = %s "
            "where id = (select source_id from public.editions where id = %s)",
            (rating, votes, movies[name]),
        )

    # A2 (9.0), J1 (8.0), J3 (7.0). J2 has too few votes.
    assert rails(api, movies["seed"])["top_rated"] == ["A2", "J1", "J3"]


def test_recently_added_is_newest_first(api, movies):
    recent = rails(api, movies["seed"])["recent"]

    assert recent[:3] == ["J3", "J2", "J1"]
    assert len(recent) == 6


def test_a_draft_or_unknown_edition_has_no_rails(api, owner, movies):
    draft = editions.create_draft(owner, kind="movie", title="Secret")
    for edition_id in (draft.edition_id, uuid.uuid4()):
        response = api.get(f"/api/v1/editions/{edition_id}/rails")
        assert response.status_code == 404


# --- Series ------------------------------------------------------------------


def test_a_series_has_new_episodes_this_week(api, owner, clean_history):
    emmy = vj(owner, "VJ Emmy")
    seed = title(owner, "Kabaka", vj_id=emmy, kind="series")
    for name, days in (("S1", 1), ("S2", 3), ("S3", 6), ("Old", 20)):
        title(owner, name, vj_id=emmy, kind="series", days_ago=days)

    found = rails(api, seed)

    assert found["new_episodes"] == ["S1", "S2", "S3"]
    assert found["vj"] == ["S1", "S2", "S3", "Old"]
    assert "recent" not in found
    assert keys(api, seed) == ["vj", "recommended", "popular", "new_episodes"]


# --- Viewers -----------------------------------------------------------------


def test_edition_viewers_gives_counts_and_never_who(app_url, owner, movies):
    users = watched(owner, movies["J1"], users=2)

    with psycopg.connect(app_url) as conn:
        cursor = conn.execute("select * from public.edition_viewers(30)")
        names = [column.name for column in cursor.description]
        rows = dict(cursor.fetchall())

    assert names == ["edition_id", "viewers"]
    assert rows[movies["J1"]] == 2
    assert all(str(user) not in str(rows) for user in users)


def test_the_api_role_still_cant_read_others_history(app_url, owner, movies):
    watched(owner, movies["J1"], users=2)

    with psycopg.connect(app_url) as conn:
        seen = conn.execute("select count(*) from public.watch_history").fetchone()

    assert seen == (0,)


def test_only_the_api_role_may_count_viewers(owner_url):
    with psycopg.connect(owner_url) as conn:
        allowed = conn.execute(
            """
            select r.rolname from pg_roles r
            where has_function_privilege(
              r.oid, 'public.edition_viewers(integer)', 'execute')
              and r.rolname like 'veloraug_%%'
            """
        ).fetchall()

    assert ("veloraug_app",) in allowed
    assert ("veloraug_media",) not in allowed
    assert ("veloraug_editor",) not in allowed


# --- Because you watched -----------------------------------------------------


def because(api, edition_id, user):
    return api.get(
        f"/api/v1/me/because-you-watched/{edition_id}", headers=as_user(user)
    )


def test_because_you_watched_uses_the_viewers_latest_title(api, owner, movies):
    title(owner, "A4", vj_id=movies["emmy"], genres=("Crime",), days_ago=80)
    (viewer,) = watched(owner, movies["J1"], days_ago=5)
    item = owner.execute(
        "select id from public.items where edition_id = %s", (movies["A1"],)
    ).fetchone()[0]
    owner.execute(
        """
        insert into public.watch_history
          (user_id, item_id, last_watched_at, position_seconds, position_at)
        values (%s, %s, now() - interval '1 day', 300, now())
        """,
        (viewer, item),
    )

    body = because(api, movies["seed"], viewer).json()

    # A1 (Action, Crime) is the latest. Titles like it, without A1, Fast X
    # or another VJ's Fast X.
    assert body["watched_title"] == "A1"
    assert body["watched_id"] == str(movies["A1"])
    titles = [card["title"] for card in body["editions"]]
    # Like A1 (Action, Crime, by VJ Emmy): A2 (Action, Emmy, 9.0) scores 4.9,
    # A4 (Crime, Emmy) 4, A3 (Action, Junior) 3.
    assert titles == ["A2", "A4", "A3"]
    assert not {"A1", "Fast X", "Fast X by Emmy"} & set(titles)


def test_because_you_watched_is_null_without_history(api, movies):
    response = because(api, movies["seed"], uuid.uuid4())

    assert response.status_code == 200
    assert response.json() is None


def test_because_you_watched_ignores_another_viewers_history(api, owner, movies):
    watched(owner, movies["A1"])

    assert because(api, movies["seed"], uuid.uuid4()).json() is None


def test_because_you_watched_needs_sign_in(api, movies):
    response = api.get(f"/api/v1/me/because-you-watched/{movies['seed']}")

    assert response.status_code == 401
