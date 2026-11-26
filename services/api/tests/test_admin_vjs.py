"""VJs, Step 13H Phase 3: profiles, active or not, featured and ordered,
links, merging duplicates and deleting.

The database tests need a local test Postgres: see tests/db_support.py.
"""

# The owner, admin, api and tmdb fixtures come from test_admin; ruff reads
# each use of them as a parameter as redefining the import.
# ruff: noqa: F811

import uuid

import pytest

from app import editions
from app.admin_catalogue import AdminError, clean_links
from tests.db_support import needs_database
from tests.test_admin import admin, api, draft, owner, tmdb  # noqa: F401
from tests.test_admin_library import series
from tests.test_database import as_user
from tests.test_discovery import share_source, title, watched
from tests.test_viewer import vj

VJS = "/api/v1/admin/vjs"


def admin_vj(api, admin, vj_id):
    response = api.get(f"{VJS}/{vj_id}", headers=as_user(admin))
    assert response.status_code == 200, response.text
    return response.json()


def change(api, admin, vj_id, **body):
    return api.patch(f"{VJS}/{vj_id}", json=body, headers=as_user(admin))


def viewer_vjs(api):
    return [v["name"] for v in api.get("/api/v1/vjs").json()]


# --- Without a database -----------------------------------------------------------


def test_links_are_checked_and_empty_ones_dropped():
    assert clean_links(
        {
            "facebook": "https://www.facebook.com/vjjunior",
            "tiktok": " https://www.tiktok.com/@vjjunior ",
            "x": "",
            "website": "https://vjjunior.ug",
        }
    ) == {
        "facebook": "https://www.facebook.com/vjjunior",
        "tiktok": "https://www.tiktok.com/@vjjunior",
        "website": "https://vjjunior.ug",
    }


@pytest.mark.parametrize(
    ("links", "message"),
    [
        ({"myspace": "https://myspace.com/a"}, "Unknown link"),
        ({"facebook": "http://facebook.com/a"}, "should start with"),
        ({"instagram": "https://evil.example/a"}, "should start with"),
        ({"website": "https://a b"}, "space"),
        ({"website": "https://" + "a" * 300}, "too long"),
    ],
)
def test_bad_links_are_refused(links, message):
    with pytest.raises(AdminError, match=message):
        clean_links(links)


# --- The list -----------------------------------------------------------------------


@needs_database
def test_each_vj_has_their_titles_counted(api, admin, owner):
    junior = vj(owner, "VJ Junior")
    fast = title(owner, "Fast X", vj_id=junior)
    hidden = title(owner, "Hidden One", vj_id=junior)
    editions.hide(owner, hidden)
    made = draft(api, admin, title="A draft")
    owner.execute(
        "update public.editions set vj_id = %s where id = %s",
        (junior, made["edition_id"]),
    )
    gone = title(owner, "Deleted", vj_id=junior)
    owner.execute(
        "update public.editions set deleted_at = now() where id = %s", (gone,)
    )
    watched(owner, fast, users=4)

    found = admin_vj(api, admin, junior)

    assert {
        k: found[k]
        for k in ("editions", "published", "hidden", "drafts", "viewers", "active")
    } == {
        "editions": 3,
        "published": 1,
        "hidden": 1,
        "drafts": 1,
        "viewers": 4,
        "active": True,
    }
    assert found["featured"] is False
    assert found["links"] == {}
    listed = api.get(VJS, headers=as_user(admin)).json()
    assert [v["name"] for v in listed] == ["VJ Junior"]
    assert api.get(f"{VJS}/{uuid.uuid4()}", headers=as_user(admin)).status_code == 404


# --- Active, featured, ordered, linked --------------------------------------------


@needs_database
def test_an_inactive_vj_leaves_browsing_but_keeps_their_credits(api, admin, owner):
    junior = vj(owner, "VJ Junior")
    fast = title(owner, "Fast X", vj_id=junior)

    response = change(api, admin, junior, active=False)

    assert response.status_code == 200, response.text
    assert response.json()["active"] is False
    assert viewer_vjs(api) == []
    assert api.get("/api/v1/vjs/vj-junior").status_code == 404
    # Their titles still show, credited to them.
    edition = api.get(f"/api/v1/editions/{fast}").json()
    assert edition["vj_name"] == "VJ Junior"

    change(api, admin, junior, active=True)
    assert viewer_vjs(api) == ["VJ Junior"]


@needs_database
def test_featured_vjs_come_first_then_the_admins_order(api, admin, owner):
    names = ["VJ Alpha", "VJ Bravo", "VJ Charlie", "VJ Delta"]
    ids = {name: vj(owner, name) for name in names}
    for name in names:
        title(owner, f"Film by {name}", vj_id=ids[name])

    change(api, admin, ids["VJ Delta"], sort_order=1)
    change(api, admin, ids["VJ Charlie"], sort_order=2)
    change(api, admin, ids["VJ Bravo"], featured=True)

    assert viewer_vjs(api) == ["VJ Bravo", "VJ Delta", "VJ Charlie", "VJ Alpha"]
    assert api.get("/api/v1/vjs").json()[0]["featured"] is True

    # Out of the order again.
    change(api, admin, ids["VJ Delta"], sort_order=None)
    assert viewer_vjs(api) == ["VJ Bravo", "VJ Charlie", "VJ Alpha", "VJ Delta"]
    # Fields not sent stay as they were.
    change(api, admin, ids["VJ Bravo"], bio="New bio.")
    assert admin_vj(api, admin, ids["VJ Bravo"])["featured"] is True


@needs_database
def test_links_show_on_the_vjs_page(api, admin, owner):
    junior = vj(owner, "VJ Junior")
    title(owner, "Fast X", vj_id=junior)

    response = change(
        api,
        admin,
        junior,
        links={
            "facebook": "https://facebook.com/vjjunior",
            "youtube": "https://youtube.com/@vjjunior",
        },
    )

    assert response.status_code == 200, response.text
    page = api.get("/api/v1/vjs/vj-junior").json()
    assert page["links"] == {
        "facebook": "https://facebook.com/vjjunior",
        "youtube": "https://youtube.com/@vjjunior",
    }
    bad = change(api, admin, junior, links={"facebook": "https://evil.example"})
    assert bad.status_code == 400
    assert change(api, admin, junior, sort_order=0).status_code == 422


# --- Names -------------------------------------------------------------------


@needs_database
def test_a_vj_cant_take_another_vjs_spelling(api, admin, owner):
    response = api.post(
        VJS,
        json={"name": "VJ Junior", "match_names": ["Junior", "VJ Jr"]},
        headers=as_user(admin),
    )
    assert response.status_code == 201
    junior = response.json()["id"]

    for name in ("Junior", "vj jr"):
        response = api.post(VJS, json={"name": name}, headers=as_user(admin))
        assert response.status_code == 400
        assert "Files already spell VJ Junior" in response.json()["detail"]
    same = api.post(VJS, json={"name": "vj junior"}, headers=as_user(admin))
    assert same.status_code == 400
    assert "already a VJ with that name" in same.json()["detail"]

    emmy = api.post(VJS, json={"name": "VJ Emmy"}, headers=as_user(admin)).json()
    renamed = change(api, admin, emmy["id"], name="Junior")
    assert renamed.status_code == 400
    assert "Merge the two" in renamed.json()["detail"]
    # Their own spelling is fine for themselves.
    assert change(api, admin, junior, name="Junior").status_code == 200


# --- Merging -----------------------------------------------------------------


@needs_database
def test_a_duplicate_vj_is_merged_into_the_right_one(api, admin, owner):
    junior = vj(owner, "VJ Junior")
    owner.execute(
        "update public.vjs set match_names = '{Junior}', photo_path = null, "
        "bio = null where id = %s",
        (junior,),
    )
    duplicate = vj(owner, "Vj Jnr")
    owner.execute(
        "update public.vjs set match_names = '{Jnr, Junior}', "
        "photo_path = 'vjs/' || id || '/abcdefghijklmnop.jpg' where id = %s",
        (duplicate,),
    )
    title(owner, "Fast X", vj_id=junior)
    kept = title(owner, "Commando", vj_id=duplicate)
    kabaka, _ = series(owner, "Kabaka", vj_id=duplicate)

    response = api.post(
        f"{VJS}/{duplicate}/merge",
        json={"into_id": str(junior)},
        headers=as_user(admin),
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["moved"] == 2
    into = body["into"]
    assert into["published"] == 3
    assert into["match_names"] == ["Junior", "Vj Jnr", "Jnr"]
    # They had no photo or bio: they take the duplicate's.
    assert into["photo_path"] == f"vjs/{duplicate}/abcdefghijklmnop.jpg"
    assert into["bio"] == "About Vj Jnr."
    assert api.get(f"{VJS}/{duplicate}", headers=as_user(admin)).status_code == 404
    for moved in (kept, kabaka):
        assert api.get(f"/api/v1/editions/{moved}").json()["vj_name"] == "VJ Junior"


@needs_database
def test_vjs_with_an_edition_of_the_same_film_arent_merged(api, admin, owner):
    junior, duplicate = vj(owner, "VJ Junior"), vj(owner, "Vj Jnr")
    fast = title(owner, "Fast X", vj_id=junior)
    other = title(owner, "Fast X again", vj_id=duplicate)
    share_source(owner, other, fast)

    response = api.post(
        f"{VJS}/{duplicate}/merge",
        json={"into_id": str(junior)},
        headers=as_user(admin),
    )

    assert response.status_code == 400
    assert "Both have an edition of Fast X again" in response.json()["detail"]
    assert admin_vj(api, admin, duplicate)["published"] == 1


@needs_database
def test_merging_is_checked(api, admin, owner):
    junior = vj(owner, "VJ Junior")
    for body, status in [
        ({"into_id": str(junior)}, 400),
        ({"into_id": str(uuid.uuid4())}, 404),
        ({}, 422),
    ]:
        response = api.post(f"{VJS}/{junior}/merge", json=body, headers=as_user(admin))
        assert response.status_code == status, body
    stranger = api.post(
        f"{VJS}/{junior}/merge",
        json={"into_id": str(vj(owner, "VJ Emmy"))},
        headers=as_user(uuid.uuid4()),
    )
    assert stranger.status_code == 403


# --- Deleting ----------------------------------------------------------------


@needs_database
def test_only_a_vj_without_titles_is_deleted(api, admin, owner):
    junior, unused = vj(owner, "VJ Junior"), vj(owner, "VJ Unused")
    title(owner, "Fast X", vj_id=junior)

    refused = api.delete(f"{VJS}/{junior}", headers=as_user(admin))
    assert refused.status_code == 400
    assert "Merge them into another VJ" in refused.json()["detail"]
    assert (
        api.delete(f"{VJS}/{unused}", headers=as_user(uuid.uuid4())).status_code == 403
    )

    assert api.delete(f"{VJS}/{unused}", headers=as_user(admin)).status_code == 200
    assert api.get(f"{VJS}/{unused}", headers=as_user(admin)).status_code == 404
    assert api.delete(f"{VJS}/{unused}", headers=as_user(admin)).status_code == 404
