"""The upload hooks tusd calls: refusals, using a key once, and finished uploads.

The database tests run on a real local Postgres, as veloraug_media. Skipped
without one: see tests/db_support.py.
"""

import uuid

import psycopg
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.db import Database
from app.media_hooks import (
    BAD_KEY,
    NOT_REMOVABLE,
    UNAVAILABLE,
    Hooks,
    MediaSettings,
    clean_filename,
    create_app,
    header,
)
from app.upload_keys import new_key
from scripts.create_app_role import scram_verifier
from scripts.upload_keys import grant_upload
from tests.db_support import needs_database, new_item, url_for

MEDIA_PASSWORD = "local-test-media-password"


def pre_create(key: str | None = None, size=1_000_000, **upload):
    headers = {"Upload-Key": [key]} if key is not None else {}
    return {
        "Type": "pre-create",
        "Event": {
            "Upload": {
                "ID": "",
                "Size": size,
                "SizeIsDeferred": False,
                "MetaData": {"filename": "C:\\Movies\\Film\x07.mp4"},
                **upload,
            },
            "HTTPRequest": {"Method": "POST", "URI": "/files/", "Header": headers},
        },
    }


def finished(upload_id: str):
    return {"Type": "post-finish", "Event": {"Upload": {"ID": upload_id}}}


def terminate(upload_id: str):
    return {"Type": "pre-terminate", "Event": {"Upload": {"ID": upload_id}}}


class NoDatabase:
    """Fails the test if a refusal reaches the database."""

    def anonymous(self):
        raise AssertionError("the database was used")


# --- Needs no database -------------------------------------------------------


@pytest.mark.parametrize(
    ("body", "status"),
    [
        (pre_create("k", SizeIsDeferred=True), 400),
        (pre_create("k", size=0), 400),
        (pre_create("k", size=50 * 1024**3 + 1), 413),
        (pre_create("k", IsPartial=True), 400),
        (pre_create(None), 403),
        (pre_create("   "), 403),
    ],
)
def test_bad_uploads_are_refused_before_the_database(body, status):
    answer = Hooks(NoDatabase()).handle(body)

    assert answer["RejectUpload"] is True
    assert answer["HTTPResponse"]["StatusCode"] == status
    assert "ChangeFileInfo" not in answer


def test_every_bad_key_gets_the_same_sentence():
    answer = Hooks(NoDatabase()).handle(pre_create(None))

    assert answer["HTTPResponse"]["Body"] == BAD_KEY + "\n"


@pytest.mark.parametrize("body", [None, [], {"Type": "pre-create"}, {"Event": 3}])
def test_nonsense_is_ignored(body):
    assert Hooks(NoDatabase()).handle(body) == {}


def test_headers_are_found_whatever_their_case():
    event = {"HTTPRequest": {"Header": {"upload-key": ["abc"], "Other": "x"}}}

    assert header(event, "Upload-Key") == "abc"
    assert header(event, "Other") is None
    assert header({}, "Upload-Key") is None


@pytest.mark.parametrize(
    ("metadata", "expected"),
    [
        ({"filename": "C:\\Movies\\Film\x07.mp4"}, "Film.mp4"),
        ({"filename": "/home/a/b/film.mkv"}, "film.mkv"),
        ({"filename": "x" * 300}, "x" * 255),
        ({"filename": "\x00\x01"}, None),
        ({}, None),
        (None, None),
    ],
)
def test_filenames_are_tidied(metadata, expected):
    assert clean_filename(metadata) == expected


def test_the_hooks_need_the_media_role():
    with pytest.raises(ValidationError) as error:
        MediaSettings(database_url="postgresql://veloraug_app:secret@db/neondb")

    assert "secret" not in str(error.value)
    assert MediaSettings(database_url="postgresql://veloraug_media:pw@db/x")


def test_the_app_has_no_documentation_pages_and_answers_health():
    settings = MediaSettings(
        database_url="postgresql://veloraug_media:pw@127.0.0.1:1/x"
    )
    with TestClient(create_app(settings)) as client:
        assert client.get("/health").json() == {"status": "ok"}
        for path in ("/docs", "/redoc", "/openapi.json"):
            assert client.get(path).status_code == 404
        assert client.post("/tusd", content=b"not json").json() == {}


@pytest.mark.parametrize("upload_id", ["", "not-a-uuid", None])
def test_removing_an_unknown_upload_is_refused_before_the_database(upload_id):
    answer = Hooks(NoDatabase()).handle(terminate(upload_id))

    assert answer["RejectTermination"] is True
    assert answer["HTTPResponse"]["StatusCode"] == 403


def test_an_unreachable_database_refuses_with_503_and_says_so():
    database = Database(
        "postgresql://veloraug_media:pw@127.0.0.1:1/x", wait_seconds=0.5
    )
    database.open()
    try:
        answer = Hooks(database).handle(pre_create(new_key()))
    finally:
        database.close()

    assert answer["HTTPResponse"]["StatusCode"] == 503
    assert answer["HTTPResponse"]["Body"] == UNAVAILABLE + "\n"


# --- On a real Postgres ------------------------------------------------------


@pytest.fixture(scope="module")
def media_database(owner_url, app_url):
    with psycopg.connect(owner_url) as conn:
        verifier = scram_verifier(MEDIA_PASSWORD)
        conn.execute(f"alter role veloraug_media login password '{verifier}'")
    database = Database(url_for("veloraug_media", MEDIA_PASSWORD))
    database.open()
    yield database
    database.close()


@pytest.fixture
def key(owner_url, app_url):
    """A fresh key for a fresh item: (item id, key text)."""
    with psycopg.connect(owner_url) as conn:
        movie_id = new_item(conn)
        _, text = grant_upload(conn, movie_id, "Kampala Films")
    return movie_id, text


def original(owner_url, original_id):
    with psycopg.connect(owner_url) as conn:
        return conn.execute(
            """
            select o.item_id, o.state, o.size_bytes, o.filename, k.used_at is not null
            from public.media_originals o
            join public.upload_keys k on k.id = o.upload_key_id
            where o.id = %s
            """,
            (original_id,),
        ).fetchone()


@needs_database
def test_a_good_key_is_used_once_and_names_the_upload(owner_url, media_database, key):
    movie_id, text = key
    hooks = Hooks(media_database)

    answer = hooks.handle(pre_create(f" {text} ", size=123_456))

    upload_id = answer["ChangeFileInfo"]["ID"]
    assert original(owner_url, upload_id) == (
        movie_id,
        "uploading",
        123_456,
        "Film.mp4",
        True,
    )
    again = hooks.handle(pre_create(text))
    assert again["HTTPResponse"]["StatusCode"] == 403


@needs_database
def test_a_wrong_key_changes_nothing(owner_url, media_database, key):
    answer = Hooks(media_database).handle(pre_create(new_key()))

    assert answer["HTTPResponse"]["StatusCode"] == 403
    with psycopg.connect(owner_url) as conn:
        used = conn.execute(
            "select count(*) from public.upload_keys where item_id = %s "
            "and used_at is not null",
            (key[0],),
        ).fetchone()[0]
    assert used == 0


@needs_database
def test_a_finished_upload_is_received_once(owner_url, media_database, key):
    hooks = Hooks(media_database)
    upload_id = hooks.handle(pre_create(key[1]))["ChangeFileInfo"]["ID"]

    assert hooks.handle(finished(upload_id)) == {}
    assert original(owner_url, upload_id)[1] == "received"
    assert hooks.handle(finished(upload_id)) == {}
    assert hooks.handle(finished("not-a-uuid")) == {}
    assert hooks.handle(finished(str(uuid.uuid4()))) == {}


@needs_database
def test_an_unfinished_upload_can_be_removed_once(owner_url, media_database, key):
    hooks = Hooks(media_database)
    upload_id = hooks.handle(pre_create(key[1]))["ChangeFileInfo"]["ID"]

    assert hooks.handle(terminate(upload_id)) == {}
    assert original(owner_url, upload_id)[1] == "removed"
    again = hooks.handle(terminate(upload_id))
    assert again["RejectTermination"] is True
    assert again["HTTPResponse"]["StatusCode"] == 403
    # A removed upload that finishes anyway stays removed.
    hooks.handle(finished(upload_id))
    assert original(owner_url, upload_id)[1] == "removed"


@needs_database
def test_a_finished_upload_cant_be_removed(owner_url, media_database, key):
    hooks = Hooks(media_database)
    upload_id = hooks.handle(pre_create(key[1]))["ChangeFileInfo"]["ID"]
    hooks.handle(finished(upload_id))

    answer = hooks.handle(terminate(upload_id))

    assert answer["RejectTermination"] is True
    assert answer["HTTPResponse"]["Body"] == NOT_REMOVABLE + "\n"
    assert original(owner_url, upload_id)[1] == "received"


@needs_database
def test_the_app_answers_tusd_over_http(owner_url, media_database, key):
    settings = MediaSettings(database_url=url_for("veloraug_media", MEDIA_PASSWORD))
    with TestClient(create_app(settings, media_database)) as client:
        answer = client.post("/tusd", json=pre_create(key[1])).json()

    assert original(owner_url, answer["ChangeFileInfo"]["ID"])[1] == "uploading"


# --- The media role's setup and checks ---------------------------------------


def test_the_media_role_gets_its_own_env_file_and_variable(tmp_path):
    from scripts.create_app_role import ROLES, app_database_url, write_env

    role, env_file, name = ROLES["media"]
    assert (role, env_file.name, name) == (
        "veloraug_media",
        ".env.media",
        "VELORAUG_MEDIA_DATABASE_URL",
    )
    url = app_database_url(
        "postgresql://neondb_owner:x@ep-a-b.c-7.eu-central-1.aws.neon.tech/neondb"
        "?sslmode=require",
        "p/w",
        role,
    )
    assert url == (
        "postgresql://veloraug_media:p%2Fw@ep-a-b-pooler.c-7.eu-central-1.aws.neon.tech"
        "/neondb?sslmode=require"
    )
    path = tmp_path / ".env.media"
    path.write_text("OTHER=1\n", encoding="utf-8")
    write_env(path, url, name)
    assert path.read_text(encoding="utf-8") == f"OTHER=1\n{name}={url}\n"


@needs_database
def test_every_media_role_check_passes(media_database):
    from scripts.check_media_role import run_checks

    results = run_checks(url_for("veloraug_media", MEDIA_PASSWORD))

    assert [result for result in results if not result.passed] == []
    assert len(results) == 15
