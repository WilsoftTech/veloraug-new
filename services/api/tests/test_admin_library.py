"""The admin's Library, Step 13H Phase 2: published, hidden and withdrawn
titles, their details, single episodes, and changes to many at once.

The database tests need a local test Postgres: see tests/db_support.py.
"""

# The owner, admin, api and tmdb fixtures come from test_admin; ruff reads
# each use of them as a parameter as redefining the import.
# ruff: noqa: F811

import uuid

import pytest

from app import editions
from app.admin_catalogue import AdminError, trailer_key
from tests.db_support import needs_database
from tests.test_admin import admin, api, draft, edition, owner, ready, tmdb  # noqa: F401
from tests.test_admin_drafts import original
from tests.test_database import as_user
from tests.test_discovery import title, watched
from tests.test_viewer import vj

LIBRARY = "/api/v1/admin/library"


def library(api, admin, **params):
    response = api.get(LIBRARY, params=params, headers=as_user(admin))
    assert response.status_code == 200, response.text
    return response.json()


def titles(api, admin, **params):
    return [t["display_title"] for t in library(api, admin, **params)["titles"]]


def viewer_sees(api, edition_id):
    """The edition as viewers get it, or None when they can't."""
    response = api.get(f"/api/v1/editions/{edition_id}")
    return response.json() if response.status_code == 200 else None


def series(owner, name, *, vj_id, episodes=3, days_ago=1):
    """A published series with `episodes` ready, approved episodes. Its ID and
    its items' IDs, in order."""
    edition_id = title(owner, name, vj_id=vj_id, kind="series", days_ago=days_ago)
    for number in range(2, episodes + 1):
        made = editions.create_draft(
            owner, kind="series", series_edition=edition_id, season=1, episode=number
        )
        ready(owner, made.item_id)
        editions.approve_item(owner, made.item_id)
    items = [
        row[0]
        for row in owner.execute(
            "select id from public.items where edition_id = %s order by episode",
            (edition_id,),
        ).fetchall()
    ]
    return edition_id, items


def episodes_seen(api, edition_id):
    seen = viewer_sees(api, edition_id)
    return [
        (e["season"], e["episode"])
        for s in (seen or {}).get("seasons", [])
        for e in s["episodes"]
    ]


# --- Without a database -----------------------------------------------------------


@pytest.mark.parametrize(
    ("typed", "key"),
    [
        ("https://www.youtube.com/watch?v=abc123XYZ_-", "abc123XYZ_-"),
        ("youtube.com/watch?feature=share&v=abc123XYZ", "abc123XYZ"),
        ("https://youtu.be/abc123XYZ?t=10", "abc123XYZ"),
        ("https://m.youtube.com/embed/abc123XYZ", "abc123XYZ"),
        ("https://www.youtube.com/shorts/abc123XYZ", "abc123XYZ"),
        ("abc123XYZ", "abc123XYZ"),
        ("   ", None),
    ],
)
def test_a_trailer_is_read_from_a_youtube_address(typed, key):
    assert trailer_key(typed) == key


@pytest.mark.parametrize(
    "typed", ["https://vimeo.com/123456", "not a key!", "https://youtu.be/x"]
)
def test_other_addresses_are_refused(typed):
    with pytest.raises(AdminError, match="YouTube"):
        trailer_key(typed)


# --- The list -------------------------------------------------------------------------


@needs_database
def test_the_library_lists_what_viewers_see_or_once_could(api, admin, owner):
    junior, emmy = vj(owner, "VJ Junior"), vj(owner, "VJ Emmy")
    fast = title(owner, "Fast X", vj_id=junior, days_ago=3)
    kabaka, _ = series(owner, "Kabaka", vj_id=emmy)
    hidden = title(owner, "Hidden One", vj_id=junior, days_ago=10)
    editions.hide(owner, hidden)
    withdrawn = title(owner, "Withdrawn One", vj_id=emmy, days_ago=20)
    owner.execute(
        "update public.editions set status = 'draft' where id = %s", (withdrawn,)
    )
    # Never in the Library: drafts never published, test films, deleted.
    draft(api, admin, title="Just a draft")
    test_film = title(owner, "Test film", vj_id=junior)
    owner.execute("update public.editions set test = true where id = %s", (test_film,))
    gone = title(owner, "Deleted", vj_id=junior)
    owner.execute(
        "update public.editions set deleted_at = now() where id = %s", (gone,)
    )
    watched(owner, fast, users=3)
    watched(owner, kabaka, users=1)

    page = library(api, admin)

    assert page["total"] == 4
    assert page["viewer_days"] == 30
    rows = {t["display_title"]: t for t in page["titles"]}
    assert list(rows) == ["Kabaka", "Fast X", "Hidden One", "Withdrawn One"]
    assert {name: t["state"] for name, t in rows.items()} == {
        "Kabaka": "published",
        "Fast X": "published",
        "Hidden One": "hidden",
        "Withdrawn One": "withdrawn",
    }
    assert rows["Fast X"]["viewers"] == 3
    assert rows["Fast X"]["vj_name"] == "VJ Junior"
    assert rows["Kabaka"]["episodes"] == 3
    assert rows["Kabaka"]["kind"] == "series"
    assert rows["Fast X"]["poster_url"] is not None
    assert rows["Fast X"]["id"] == str(fast)


@needs_database
def test_the_library_is_searched_filtered_and_sorted(api, admin, owner):
    junior, emmy = vj(owner, "VJ Junior"), vj(owner, "VJ Emmy")
    fast = title(owner, "Fast X", vj_id=junior, days_ago=3)
    title(owner, "Commando", vj_id=emmy, days_ago=5)
    series(owner, "Kabaka", vj_id=emmy)
    hidden = title(owner, "Hidden One", vj_id=junior, days_ago=10)
    editions.hide(owner, hidden)
    owner.execute(
        "insert into public.categories (name, slug) values ('Indian', 'indian-t') "
        "on conflict do nothing"
    )
    api.put(
        f"/api/v1/admin/editions/{fast}/categories",
        json={"names": ["Indian"]},
        headers=as_user(admin),
    )
    watched(owner, hidden, users=5)

    assert titles(api, admin, q="fast") == ["Fast X"]
    # A VJ's name finds their titles too.
    assert titles(api, admin, q="emmy") == ["Kabaka", "Commando"]
    assert titles(api, admin, vj=str(junior)) == ["Fast X", "Hidden One"]
    assert titles(api, admin, kind="series") == ["Kabaka"]
    assert titles(api, admin, category="indian") == ["Fast X"]
    assert titles(api, admin, state="hidden") == ["Hidden One"]
    assert titles(api, admin, sort="title") == [
        "Commando",
        "Fast X",
        "Hidden One",
        "Kabaka",
    ]
    assert titles(api, admin, sort="oldest")[0] == "Hidden One"
    # Viewers of hidden titles aren't counted: they can't watch them now.
    assert library(api, admin, state="hidden")["titles"][0]["viewers"] == 0

    page = library(api, admin, sort="title", offset=3)
    assert [t["display_title"] for t in page["titles"]] == ["Kabaka"]
    assert page["total"] == 4
    page = library(api, admin, offset=50)
    assert (page["titles"], page["total"]) == ([], 4)


@needs_database
def test_bad_filters_are_refused_and_only_admins_get_in(api, admin, owner):
    for params in ({"kind": "film"}, {"state": "draft"}, {"sort": "random"}):
        response = api.get(LIBRARY, params=params, headers=as_user(admin))
        assert response.status_code == 422
    assert api.get(LIBRARY, headers=as_user(uuid.uuid4())).status_code == 403


# --- Details -------------------------------------------------------------------------


@needs_database
def test_an_editions_own_details_show_over_its_sources(api, admin, owner):
    fast = title(owner, "Fast X", vj_id=vj(owner, "VJ Junior"))
    source = viewer_sees(api, fast)
    backdrop = f"posters/{fast}/{'a' * 22}.jpg"

    response = api.patch(
        f"/api/v1/admin/editions/{fast}",
        json={
            "display_title": "Fast X (VJ Junior)",
            "submitted_year": 2023,
            "overview": "Dom Toretto, in Luganda.",
            "trailer": "https://youtu.be/abc123XYZ",
            "backdrop_path": backdrop,
        },
        headers=as_user(admin),
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["overview"] == "Dom Toretto, in Luganda."
    assert body["trailer_key"] == "abc123XYZ"
    assert body["backdrop_url"].endswith(f"/i/{backdrop}")
    assert body["source_overview"] == source["overview"]
    seen = viewer_sees(api, fast)
    assert seen["title"] == "Fast X (VJ Junior)"
    assert seen["overview"] == "Dom Toretto, in Luganda."
    assert seen["trailer_url"] == "https://www.youtube.com/watch?v=abc123XYZ"
    assert seen["backdrop_url"].endswith(f"/i/{backdrop}")

    # Cleared: the source's show again. Fields not sent stay as they are.
    response = api.patch(
        f"/api/v1/admin/editions/{fast}",
        json={"overview": "", "trailer": "", "backdrop_path": ""},
        headers=as_user(admin),
    )
    assert response.status_code == 200
    seen = viewer_sees(api, fast)
    assert seen["overview"] == source["overview"]
    assert seen["trailer_url"] == source["trailer_url"]
    assert seen["backdrop_url"] == source["backdrop_url"]
    assert seen["title"] == "Fast X (VJ Junior)"


@needs_database
def test_bad_details_are_refused(api, admin, owner):
    fast = title(owner, "Fast X", vj_id=vj(owner, "VJ Junior"))
    other = title(owner, "Other", vj_id=vj(owner, "VJ Emmy"))

    for body, status in [
        ({"trailer": "https://vimeo.com/1"}, 400),
        ({"backdrop_path": f"posters/{other}/{'a' * 22}.jpg"}, 400),
        ({"backdrop_path": "/tmdb.jpg"}, 400),
        ({"language": "xx"}, 400),
        ({"display_title": None}, 400),
        ({"submitted_year": 1800}, 422),
        ({"overview": "x" * 5001}, 422),
    ]:
        response = api.patch(
            f"/api/v1/admin/editions/{fast}", json=body, headers=as_user(admin)
        )
        assert response.status_code == status, (body, response.text)


# --- Hiding, withdrawing, deleting ------------------------------------------------


@needs_database
def test_a_withdrawn_title_goes_back_to_drafts_until_published_again(api, admin, owner):
    fast = title(owner, "Fast X", vj_id=vj(owner, "VJ Junior"))

    response = api.post(
        f"/api/v1/admin/editions/{fast}/withdraw", headers=as_user(admin)
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "draft"
    assert viewer_sees(api, fast) is None
    drafts = api.get("/api/v1/admin/drafts", headers=as_user(admin)).json()
    assert str(fast) in [e["id"] for e in drafts["editions"]]
    assert titles(api, admin, state="withdrawn") == ["Fast X"]
    again = api.post(f"/api/v1/admin/editions/{fast}/withdraw", headers=as_user(admin))
    assert again.status_code == 400

    published_at = owner.execute(
        "select published_at from public.editions where id = %s", (fast,)
    ).fetchone()[0]
    api.post(f"/api/v1/admin/editions/{fast}/publish", headers=as_user(admin))
    assert viewer_sees(api, fast) is not None
    # It keeps its place among the newest: its first publishing date.
    assert (
        owner.execute(
            "select published_at from public.editions where id = %s", (fast,)
        ).fetchone()[0]
        == published_at
    )


@needs_database
def test_a_published_title_is_deleted_only_when_asked_for_plainly(api, admin, owner):
    fast = title(owner, "Fast X", vj_id=vj(owner, "VJ Junior"))

    refused = api.delete(f"/api/v1/admin/editions/{fast}", headers=as_user(admin))
    assert refused.status_code == 400
    assert viewer_sees(api, fast) is not None

    response = api.delete(
        f"/api/v1/admin/editions/{fast}",
        params={"published": "true"},
        headers=as_user(admin),
    )
    assert response.status_code == 200
    assert viewer_sees(api, fast) is None
    assert titles(api, admin) == []


# --- Single episodes ------------------------------------------------------------------


@needs_database
def test_an_episode_is_hidden_and_shown_on_its_own(api, admin, owner):
    kabaka, (one, two, three) = series(owner, "Kabaka", vj_id=vj(owner, "VJ Emmy"))

    response = api.post(f"/api/v1/admin/items/{two}/hide", headers=as_user(admin))

    assert response.status_code == 200
    assert episodes_seen(api, kabaka) == [(1, 1), (1, 3)]
    items = {i["id"]: i for i in edition(api, admin, kabaka)["items"]}
    assert items[str(two)]["hidden"] is True
    # Hidden isn't waiting for approval: Drafts doesn't list the series.
    drafts = api.get("/api/v1/admin/drafts", headers=as_user(admin)).json()
    assert str(kabaka) not in [e["id"] for e in drafts["editions"]]
    assert library(api, admin)["titles"][0]["hidden_episodes"] == 1

    api.post(f"/api/v1/admin/items/{two}/show", headers=as_user(admin))
    assert episodes_seen(api, kabaka) == [(1, 1), (1, 2), (1, 3)]


@needs_database
def test_a_withdrawn_episode_waits_for_approval_again(api, admin, owner):
    kabaka, (_, two, _) = series(owner, "Kabaka", vj_id=vj(owner, "VJ Emmy"))

    api.post(f"/api/v1/admin/items/{two}/withdraw", headers=as_user(admin))

    assert episodes_seen(api, kabaka) == [(1, 1), (1, 3)]
    drafts = api.get("/api/v1/admin/drafts", headers=as_user(admin)).json()
    assert str(kabaka) in [e["id"] for e in drafts["editions"]]
    assert library(api, admin)["titles"][0]["waiting"] == 1
    api.post(f"/api/v1/admin/items/{two}/approve", headers=as_user(admin))
    assert episodes_seen(api, kabaka) == [(1, 1), (1, 2), (1, 3)]


@needs_database
def test_an_episode_is_deleted_for_good_once_its_video_is_gone(api, admin, owner):
    kabaka, (one, two, three) = series(owner, "Kabaka", vj_id=vj(owner, "VJ Emmy"))
    video = owner.execute(
        "select id from public.media_originals where item_id = %s", (two,)
    ).fetchone()[0]

    response = api.delete(f"/api/v1/admin/items/{two}", headers=as_user(admin))

    assert response.status_code == 200, response.text
    assert episodes_seen(api, kabaka) == [(1, 1), (1, 3)]
    assert [i["id"] for i in edition(api, admin, kabaka)["items"]] == [
        str(one),
        str(three),
    ]
    state = owner.execute(
        "select state from public.media_originals where id = %s", (video,)
    ).fetchone()[0]
    assert state == "removing"
    # Deleted again: it's gone already.
    again = api.delete(f"/api/v1/admin/items/{two}", headers=as_user(admin))
    assert again.status_code == 404

    owner.execute(
        "update public.media_originals set state = 'removed' where id = %s", (video,)
    )
    api.get("/api/v1/admin/drafts", headers=as_user(admin))
    assert (
        owner.execute("select 1 from public.items where id = %s", (two,)).fetchone()
        is None
    )
    assert episodes_seen(api, kabaka) == [(1, 1), (1, 3)]


@needs_database
def test_a_movies_video_and_a_series_last_episode_go_with_their_title(
    api, admin, owner
):
    fast = title(owner, "Fast X", vj_id=vj(owner, "VJ Junior"))
    movie_item = owner.execute(
        "select id from public.items where edition_id = %s", (fast,)
    ).fetchone()[0]
    kabaka, (only,) = series(owner, "Kabaka", vj_id=vj(owner, "VJ Emmy"), episodes=1)

    response = api.delete(f"/api/v1/admin/items/{movie_item}", headers=as_user(admin))
    assert response.status_code == 400
    assert "delete the movie" in response.json()["detail"]
    response = api.delete(f"/api/v1/admin/items/{only}", headers=as_user(admin))
    assert response.status_code == 400
    assert "only episode" in response.json()["detail"]


@needs_database
def test_episodes_are_renamed_and_put_in_order(api, admin, owner):
    kabaka, (one, two, three) = series(owner, "Kabaka", vj_id=vj(owner, "VJ Emmy"))

    response = api.patch(
        f"/api/v1/admin/items/{three}",
        json={"episode": 1, "episode_title": "  The  Beginning "},
        headers=as_user(admin),
    )

    assert response.status_code == 200, response.text
    numbers = {
        i["id"]: (i["episode"], i["episode_title"])
        for i in edition(api, admin, kabaka)["items"]
    }
    # Swapped with the episode that had number 1.
    assert numbers[str(three)] == (1, "The Beginning")
    assert numbers[str(one)][0] == 3
    assert numbers[str(two)][0] == 2

    # A free number: moved, nothing swapped. Season 2 is fine too.
    api.patch(
        f"/api/v1/admin/items/{two}",
        json={"season": 2, "episode": 1},
        headers=as_user(admin),
    )
    seasons = {i["id"]: i["season"] for i in edition(api, admin, kabaka)["items"]}
    assert seasons[str(two)] == 2

    for body in ({"episode": 0}, {"season": 1000}):
        response = api.patch(
            f"/api/v1/admin/items/{one}", json=body, headers=as_user(admin)
        )
        assert response.status_code == 422


# --- Many at once -------------------------------------------------------------------


@needs_database
def test_many_titles_are_changed_at_once_each_on_its_own(api, admin, owner):
    junior, emmy = vj(owner, "VJ Junior"), vj(owner, "VJ Emmy")
    fast = title(owner, "Fast X", vj_id=junior)
    commando = title(owner, "Commando", vj_id=junior)
    withdrawn = title(owner, "Withdrawn", vj_id=junior)
    owner.execute(
        "update public.editions set status = 'draft' where id = %s", (withdrawn,)
    )

    response = api.post(
        f"{LIBRARY}/bulk",
        json={"ids": [str(fast), str(commando), str(withdrawn)], "action": "hide"},
        headers=as_user(admin),
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["changed"] == 2
    reasons = {r["id"]: r["reason"] for r in body["results"]}
    assert reasons[str(withdrawn)] == "Only a published title can be hidden"
    assert sorted(titles(api, admin, state="hidden")) == ["Commando", "Fast X"]

    body = api.post(
        f"{LIBRARY}/bulk",
        json={
            "ids": [str(fast), str(commando)],
            "action": "credit",
            "vj_id": str(emmy),
        },
        headers=as_user(admin),
    ).json()
    assert body["changed"] == 2
    assert titles(api, admin, vj=str(emmy)) != []

    body = api.post(
        f"{LIBRARY}/bulk",
        json={"ids": [str(fast), str(commando), str(withdrawn)], "action": "show"},
        headers=as_user(admin),
    ).json()
    assert body["changed"] == 3
    assert viewer_sees(api, withdrawn) is not None


@needs_database
def test_a_title_that_isnt_ready_isnt_shown_and_says_why(api, admin, owner):
    made = draft(api, admin, title="Unfinished")
    original(owner, made["item_id"], "converting", progress=10)
    # Published once, then its poster was lost.
    fast = title(owner, "Fast X", vj_id=vj(owner, "VJ Junior"))
    api.post(f"/api/v1/admin/editions/{fast}/withdraw", headers=as_user(admin))
    owner.execute(
        "update public.editions set poster_path = null where id = %s", (fast,)
    )

    body = api.post(
        f"{LIBRARY}/bulk",
        json={"ids": [str(fast)], "action": "show"},
        headers=as_user(admin),
    ).json()

    assert body["changed"] == 0
    assert body["results"][0]["reason"] == "Still needs a chosen poster"


@needs_database
def test_bulk_changes_are_checked(api, admin, owner):
    fast = title(owner, "Fast X", vj_id=vj(owner, "VJ Junior"))
    for body in (
        {"ids": [], "action": "hide"},
        {"ids": [str(fast)], "action": "delete"},
        {"ids": [str(uuid.uuid4())] * 201, "action": "hide"},
    ):
        response = api.post(f"{LIBRARY}/bulk", json=body, headers=as_user(admin))
        assert response.status_code == 422, body
    response = api.post(
        f"{LIBRARY}/bulk",
        json={"ids": [str(fast)], "action": "credit"},
        headers=as_user(admin),
    )
    assert response.status_code == 400
    response = api.post(
        f"{LIBRARY}/bulk",
        json={"ids": [str(fast)], "action": "hide"},
        headers=as_user(uuid.uuid4()),
    )
    assert response.status_code == 403
    assert viewer_sees(api, fast) is not None
