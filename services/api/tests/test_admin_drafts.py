"""Drafts, Step 13H Phase 1: progress, incomplete uploads, and deleting.

The database tests need a local test Postgres: see tests/db_support.py.
"""

# The owner, admin, api and tmdb fixtures come from test_admin; ruff reads
# each use of them as a parameter as redefining the import.
# ruff: noqa: F811

import logging
import os
import uuid

from tests.db_support import needs_database
from tests.test_admin import admin, api, draft, edition, owner, ready, tmdb  # noqa: F401
from tests.test_database import as_user

DRAFTS = "/api/v1/admin/drafts"


def original(owner, item_id, state, *, progress=None, seconds_in=0, age=0):
    """An original in any state, as the hooks and worker would leave it.
    [seconds_in] is how long it has been in this stage by its last report."""
    (key_id,) = owner.execute(
        """
        insert into public.upload_keys (item_id, key_hash, label, expires_at, used_at)
        values (%s, %s, 'Test', now() + interval '1 day', now()) returning id
        """,
        (item_id, os.urandom(32)),
    ).fetchone()
    original_id = uuid.uuid4()
    owner.execute(
        """
        insert into public.media_originals (id, item_id, upload_key_id, size_bytes,
          state, ready_at, progress, created_at, updated_at, progress_at)
        values (%s, %s, %s, 5000, %s, case when %s = 'ready' then now() end, %s,
          now() - make_interval(secs => %s),
          now() - make_interval(secs => %s), now())
        """,
        (original_id, item_id, key_id, state, state, progress, age, seconds_in),
    )
    return original_id


def drafts(api, admin):
    response = api.get(DRAFTS, headers=as_user(admin))
    assert response.status_code == 200, response.text
    return {e["id"]: e for e in response.json()["editions"]}


def state_of(owner, original_id):
    row = owner.execute(
        "select state from public.media_originals where id = %s", (original_id,)
    ).fetchone()
    return row[0] if row else None


def exists(owner, edition_id):
    return (
        owner.execute(
            "select 1 from public.editions where id = %s", (edition_id,)
        ).fetchone()
        is not None
    )


# --- Progress ------------------------------------------------------------------


@needs_database
def test_each_video_says_how_far_it_has_got(api, admin, owner):
    owner.execute(
        "update public.media_originals set state = 'failed' where state = 'received'"
    )
    converting = draft(api, admin, title="Converting")
    original(owner, converting["item_id"], "converting", progress=40, seconds_in=60)
    first = draft(api, admin, title="First in line")
    original(owner, first["item_id"], "received", age=20)
    second = draft(api, admin, title="Second in line")
    original(owner, second["item_id"], "received", age=10)
    checking = draft(api, admin, title="Checking")
    original(owner, checking["item_id"], "checking")

    found = drafts(api, admin)

    item = found[converting["edition_id"]]["items"][0]
    assert (item["video"], item["progress"], item["size_bytes"]) == (
        "converting",
        40,
        5000,
    )
    # 60 s for 40%, so 90 s for the other 60%.
    assert 89 <= item["eta_seconds"] <= 91
    assert found[first["edition_id"]]["items"][0]["queue_position"] == 1
    assert found[second["edition_id"]]["items"][0]["queue_position"] == 2
    # FFprobe gives no progress: the screen shows a moving bar.
    item = found[checking["edition_id"]]["items"][0]
    assert (item["progress"], item["eta_seconds"], item["queue_position"]) == (
        None,
        None,
        None,
    )


@needs_database
def test_no_time_is_guessed_before_the_first_report(api, admin, owner):
    made = draft(api, admin, title="Just started")
    original(owner, made["item_id"], "converting", progress=0, seconds_in=30)

    item = drafts(api, admin)[made["edition_id"]]["items"][0]

    assert (item["progress"], item["eta_seconds"]) == (0, None)


@needs_database
def test_drafts_without_a_finished_upload_are_marked_incomplete(api, admin, owner):
    waiting = draft(api, admin, title="No video yet")
    uploading = draft(api, admin, title="Uploading")
    original(owner, uploading["item_id"], "uploading")
    failed = draft(api, admin, title="Failed")
    original(owner, failed["item_id"], "failed")
    done = draft(api, admin, title="Uploaded")
    ready(owner, done["item_id"])
    series = draft(api, admin, kind="series", title="Kabaka", season=1, episode=1)
    ready(owner, series["item_id"])
    episode = draft(
        api,
        admin,
        kind="series",
        series_edition_id=series["edition_id"],
        season=1,
        episode=2,
    )
    original(owner, episode["item_id"], "uploading")

    found = drafts(api, admin)

    assert {
        found[made["edition_id"]]["display_title"]: found[made["edition_id"]][
            "incomplete"
        ]
        for made in (waiting, uploading, failed, done, series)
    } == {
        "No video yet": True,
        "Uploading": True,
        # A failed video was uploaded: the admin needs to see why it failed.
        "Failed": False,
        "Uploaded": False,
        # One episode is uploaded, so the series is listed.
        "Kabaka": False,
    }


# --- Deleting one ----------------------------------------------------------------


@needs_database
def test_a_draft_is_deleted_for_good_once_its_files_are_gone(api, admin, owner, caplog):
    made = draft(api, admin)
    video = ready(owner, made["item_id"])
    other = draft(api, admin, title="Kept")

    with caplog.at_level(logging.INFO, logger="veloraug.audit"):
        response = api.delete(
            f"/api/v1/admin/editions/{made['edition_id']}", headers=as_user(admin)
        )

    assert response.status_code == 200, response.text
    assert response.json() == {"deleted": 1}
    assert '"event":"edition_deleted"' in caplog.text
    assert made["edition_id"] in caplog.text
    # Gone from every list at once, though the worker hasn't run yet.
    assert made["edition_id"] not in drafts(api, admin)
    assert other["edition_id"] in drafts(api, admin)
    gone = api.get(
        f"/api/v1/admin/editions/{made['edition_id']}", headers=as_user(admin)
    )
    assert gone.status_code == 404
    assert state_of(owner, video) == "removing"
    (live_keys,) = owner.execute(
        "select count(*) from public.upload_keys where item_id = %s "
        "and revoked_at is null",
        (made["item_id"],),
    ).fetchone()
    assert live_keys == 0
    assert exists(owner, made["edition_id"])

    # The worker removes the files, and the next look at Drafts tidies up.
    owner.execute(
        "update public.media_originals set state = 'removed' where id = %s", (video,)
    )
    drafts(api, admin)

    assert not exists(owner, made["edition_id"])
    assert state_of(owner, video) is None
    assert exists(owner, other["edition_id"])


@needs_database
def test_a_draft_without_a_video_goes_at_once(api, admin, owner):
    made = draft(api, admin)

    response = api.delete(
        f"/api/v1/admin/editions/{made['edition_id']}", headers=as_user(admin)
    )

    assert response.status_code == 200
    assert not exists(owner, made["edition_id"])


@needs_database
def test_a_video_being_converted_is_left_to_finish_then_removed(api, admin, owner):
    made = draft(api, admin)
    video = original(owner, made["item_id"], "converting", progress=50)

    api.delete(f"/api/v1/admin/editions/{made['edition_id']}", headers=as_user(admin))

    # FFmpeg is still writing its files: the worker would only put it back.
    assert state_of(owner, video) == "converting"
    owner.execute(
        "update public.media_originals set state = 'publishing' where id = %s",
        (video,),
    )
    drafts(api, admin)
    assert state_of(owner, video) == "removing"


@needs_database
def test_published_and_test_editions_arent_deleted_from_drafts(api, admin, owner):
    made = draft(api, admin)
    owner.execute(
        "update public.editions set status = 'hidden' where id = %s",
        (made["edition_id"],),
    )
    test_film = draft(api, admin, title="Test film")
    owner.execute(
        "update public.editions set test = true where id = %s",
        (test_film["edition_id"],),
    )
    response = api.delete(
        f"/api/v1/admin/editions/{test_film['edition_id']}", headers=as_user(admin)
    )
    assert response.status_code == 400
    assert "owner's script" in response.json()["detail"]

    published = draft(api, admin, title="Published")
    (vj_id,) = owner.execute(
        "insert into public.vjs (name, slug) values ('VJ Kept', 'vj-kept') returning id"
    ).fetchone()
    (source_id,) = owner.execute(
        "insert into public.sources (kind, title, details_from) "
        "values ('movie', 'Published', 'manual') returning id"
    ).fetchone()
    owner.execute(
        """
        update public.editions set status = 'published', published_at = now(),
          source_id = %s, vj_id = %s, poster_path = '/p.jpg' where id = %s
        """,
        (source_id, vj_id, published["edition_id"]),
    )
    response = api.delete(
        f"/api/v1/admin/editions/{published['edition_id']}", headers=as_user(admin)
    )
    assert response.status_code == 400
    assert response.json()["detail"] == (
        "This is published. Hide it first, then delete it"
    )
    assert exists(owner, published["edition_id"])

    # A hidden one can be.
    response = api.delete(
        f"/api/v1/admin/editions/{made['edition_id']}", headers=as_user(admin)
    )
    assert response.status_code == 200


@needs_database
def test_deleting_needs_an_admin_and_a_real_edition(api, admin, owner):
    made = draft(api, admin)

    stranger = api.delete(
        f"/api/v1/admin/editions/{made['edition_id']}", headers=as_user(uuid.uuid4())
    )
    assert stranger.status_code == 403
    assert exists(owner, made["edition_id"])

    missing = api.delete(
        f"/api/v1/admin/editions/{uuid.uuid4()}", headers=as_user(admin)
    )
    assert missing.status_code == 404


@needs_database
def test_a_deleted_series_takes_no_episodes_and_cant_be_published(api, admin, owner):
    series = draft(api, admin, kind="series", title="Kabaka", season=1, episode=1)
    video = original(owner, series["item_id"], "checking")
    api.delete(f"/api/v1/admin/editions/{series['edition_id']}", headers=as_user(admin))
    assert state_of(owner, video) == "checking"

    response = api.post(
        DRAFTS,
        json={
            "kind": "series",
            "series_edition_id": series["edition_id"],
            "season": 1,
            "episode": 2,
        },
        headers=as_user(admin),
    )
    assert response.status_code == 400

    response = api.post(
        f"/api/v1/admin/editions/{series['edition_id']}/publish",
        headers=as_user(admin),
    )
    assert response.status_code == 400
    assert "being deleted" in response.json()["detail"]

    series_list = api.get("/api/v1/admin/series", headers=as_user(admin)).json()
    assert series["edition_id"] not in [s["id"] for s in series_list]


# --- Deleting every draft ------------------------------------------------------------


@needs_database
def test_every_draft_is_deleted_only_with_the_word(api, admin, owner, caplog):
    first = draft(api, admin, title="One")
    second = draft(api, admin, title="Two")
    ready(owner, second["item_id"])
    hidden = draft(api, admin, title="Hidden")
    owner.execute(
        "update public.editions set status = 'hidden' where id = %s",
        (hidden["edition_id"],),
    )

    for body in ({}, {"confirm": "yes"}, {"confirm": "delete"}):
        response = api.post(f"{DRAFTS}/delete-all", json=body, headers=as_user(admin))
        assert response.status_code == 422
    assert exists(owner, first["edition_id"])

    with caplog.at_level(logging.INFO, logger="veloraug.audit"):
        response = api.post(
            f"{DRAFTS}/delete-all", json={"confirm": "DELETE"}, headers=as_user(admin)
        )

    assert response.status_code == 200, response.text
    assert response.json() == {"deleted": 2}
    assert '"count":2' in caplog.text
    left = drafts(api, admin)
    assert first["edition_id"] not in left
    assert second["edition_id"] not in left
    # Hidden editions were published once: they stay.
    assert hidden["edition_id"] in left


@needs_database
def test_deleting_every_draft_needs_an_admin(api, admin, owner):
    made = draft(api, admin)

    response = api.post(
        f"{DRAFTS}/delete-all",
        json={"confirm": "DELETE"},
        headers=as_user(uuid.uuid4()),
    )

    assert response.status_code == 403
    assert exists(owner, made["edition_id"])
