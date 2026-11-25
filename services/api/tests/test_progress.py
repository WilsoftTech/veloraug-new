"""Episode running times and the viewer's progress, Phase 6, on a real
Postgres. Skipped without a local test Postgres: see tests/db_support.py."""

# The owner, api and catalogue fixtures come from test_viewer; ruff reads
# each use of them as a parameter as redefining the import.
# ruff: noqa: F811

import uuid

import psycopg

from tests.db_support import needs_database
from tests.test_database import as_user
from tests.test_viewer import api, catalogue, owner  # noqa: F401

pytestmark = needs_database


def episodes(api, edition_id):
    detail = api.get(f"/api/v1/editions/{edition_id}").json()
    return {
        (e["season"], e["episode"]): e
        for season in detail["seasons"]
        for e in season["episodes"]
    }


def test_an_episode_has_its_videos_running_time(api, owner, catalogue):
    series = catalogue["series"]
    owner.execute(
        "update public.media_originals set duration_seconds = 2520.4 "
        "where item_id = %s",
        (series.item_id,),
    )

    found = episodes(api, series.edition_id)

    # 42 minutes and a bit: rounded up.
    assert found[(1, 1)]["runtime_minutes"] == 43
    # No duration measured yet.
    assert found[(2, 1)]["runtime_minutes"] is None


def test_the_api_role_reads_a_duration_and_nothing_more(app_url, owner, catalogue):
    with psycopg.connect(app_url) as conn:
        conn.execute("select duration_seconds from public.media_originals")
        conn.rollback()
        try:
            conn.execute("select filename from public.media_originals")
        except psycopg.errors.InsufficientPrivilege:
            refused = True
        else:
            refused = False
    assert refused


def history(owner, user, item_id, *, position=None, finished=False):
    owner.execute(
        """
        insert into public.watch_history
          (user_id, item_id, position_seconds, position_at, finished)
        values (%s, %s, %s, now(), %s)
        """,
        (user, item_id, position, finished),
    )


def progress(api, edition_id, user):
    return api.get(f"/api/v1/me/editions/{edition_id}/progress", headers=as_user(user))


def test_progress_lists_what_the_viewer_played_in_this_edition(api, owner, catalogue):
    viewer, other = uuid.uuid4(), uuid.uuid4()
    series = catalogue["series"]
    history(owner, viewer, series.item_id, position=600)
    history(owner, viewer, catalogue["third"].item_id, finished=True)
    # Another edition, another viewer, and a grant with nothing played.
    history(owner, viewer, catalogue["movie"].item_id, position=60)
    history(owner, other, series.item_id, position=1200)
    try:
        response = progress(api, series.edition_id, viewer)

        assert response.status_code == 200
        assert sorted(response.json(), key=lambda p: p["position_seconds"] or 0) == [
            {
                "item_id": str(catalogue["third"].item_id),
                "position_seconds": None,
                "finished": True,
            },
            {
                "item_id": str(series.item_id),
                "position_seconds": 600,
                "finished": False,
            },
        ]
    finally:
        owner.execute(
            "delete from public.watch_history where user_id = any(%s)",
            ([viewer, other],),
        )


def test_a_grant_with_nothing_played_isnt_progress(api, owner, catalogue):
    viewer = uuid.uuid4()
    history(owner, viewer, catalogue["series"].item_id)
    try:
        assert progress(api, catalogue["series"].edition_id, viewer).json() == []
    finally:
        owner.execute("delete from public.watch_history where user_id = %s", (viewer,))


def test_progress_needs_sign_in(api, catalogue):
    response = api.get(f"/api/v1/me/editions/{catalogue['series'].edition_id}/progress")
    assert response.status_code == 401
