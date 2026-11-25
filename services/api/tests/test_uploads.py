"""Upload keys, originals and qualities: migration 0003 and the owner's commands.

The database tests run on a real local Postgres, as the owner, the API's role
and the media role. Skipped without one: see tests/db_support.py.
"""

import hashlib
import uuid
from datetime import UTC, datetime, timedelta

import psycopg
import pytest
from psycopg import errors

from scripts import catalogue
from scripts.check_database import run_checks
from scripts.upload_keys import (
    KEY_PREFIX,
    ItemUploads,
    Original,
    UploadKey,
    UploadKeyError,
    clean_label,
    describe_uploads,
    grant_upload,
    key_hash,
    list_uploads,
    new_key,
    revoke_upload,
    size_text,
)
from tests.db_support import needs_database, new_item

NOW = datetime(2026, 11, 12, 12, 0, tzinfo=UTC)

# --- Needs no database -------------------------------------------------------


def test_keys_are_long_random_and_recognisable():
    keys = {new_key() for _ in range(50)}

    assert len(keys) == 50
    for key in keys:
        assert key.startswith(KEY_PREFIX)
        assert len(key) == len(KEY_PREFIX) + 43


def test_only_the_hash_is_kept_and_stray_spaces_dont_matter():
    key = new_key()

    assert key_hash(key) == hashlib.sha256(key.encode()).digest()
    assert key_hash(f"  {key}\n") == key_hash(key)
    assert len(key_hash(key)) == 32


@pytest.mark.parametrize("label", ["", "   ", "x" * 101])
def test_a_key_must_say_who_it_is_for(label):
    with pytest.raises(UploadKeyError):
        clean_label(label)


def test_labels_are_tidied():
    assert clean_label("  Kampala   Films ") == "Kampala Films"


def test_sizes_read_naturally():
    assert size_text(4_200_000_000) == "4.2 GB"
    assert size_text(52_000_000) == "52.0 MB"
    assert size_text(900) == "900 bytes"


def _key(**changes) -> UploadKey:
    fields = {
        "id": uuid.UUID(int=1),
        "item_id": uuid.UUID(int=2),
        "label": "Kampala Films",
        "created_at": NOW - timedelta(days=1),
        "expires_at": NOW + timedelta(days=6),
        "used_at": None,
        "revoked_at": None,
    } | changes
    return UploadKey(**fields)


def test_a_key_has_one_state():
    assert _key().state(NOW) == "unused"
    assert _key(expires_at=NOW).state(NOW) == "expired"
    assert _key(used_at=NOW).state(NOW) == "used"
    assert _key(used_at=NOW, revoked_at=NOW).state(NOW) == "revoked"


def test_uploads_lists_each_key_with_its_original():
    refused = _key(id=uuid.UUID(int=3), used_at=NOW)
    ready = _key(id=uuid.UUID(int=5), used_at=NOW)
    originals = [
        Original(
            id=uuid.UUID(int=4),
            upload_key_id=refused.id,
            state="refused",
            size_bytes=900_000,
            height=240,
            video_codec="h264",
            audio_codec=None,
            reason="The video is 240 lines high. VeloraUG needs at least 360.",
        ),
        Original(
            id=uuid.UUID(int=6),
            upload_key_id=ready.id,
            state="ready",
            size_bytes=6_200_000_000,
            height=720,
            video_codec="hevc",
            audio_codec="ac3",
            reason=None,
            qualities=(360, 480, 720),
        ),
    ]
    item = ItemUploads(
        uuid.UUID(int=2),
        uuid.UUID(int=9),
        "Fight Club",
        None,
        None,
        [_key(), refused, ready],
        originals,
    )

    lines = describe_uploads(item, NOW)

    assert lines == [
        f"Fight Club  item {uuid.UUID(int=2)}",
        f"  key for Kampala Films: expires 18 Nov 12:00 UTC  key id {uuid.UUID(int=1)}",
        f"  key for Kampala Films: used  key id {uuid.UUID(int=3)}",
        f"    original {uuid.UUID(int=4)}: refused, 900.0 KB, 240p H264. "
        "The video is 240 lines high. VeloraUG needs at least 360.",
        f"  key for Kampala Films: used  key id {uuid.UUID(int=5)}",
        f"    original {uuid.UUID(int=6)}: ready, 6.2 GB, 720p HEVC/AC3. "
        "Qualities: 360p, 480p, 720p",
    ]


def test_the_commands_explain_themselves(capsys):
    for command in ("grant-upload", "revoke-upload", "uploads"):
        with pytest.raises(SystemExit):
            catalogue.parser().parse_args([command, "--help"])
    assert "who the key is for" in capsys.readouterr().out


def test_grant_upload_needs_to_know_who_for():
    with pytest.raises(SystemExit):
        catalogue.parser().parse_args(["grant-upload", "550"])


# --- On a real Postgres ------------------------------------------------------


@pytest.fixture
def movie(owner_url, app_url):
    """A movie of its own for each test, committed so other roles see it."""
    with psycopg.connect(owner_url) as conn:
        movie_id = new_item(conn)
    return movie_id


def grant(owner_url, movie_id, days=7, label="Kampala Films"):
    with psycopg.connect(owner_url) as conn:
        return grant_upload(conn, movie_id, label, days)


def claim(conn, key):
    """What the pre-create hook will do: use the key once, while it's valid."""
    return conn.execute(
        """
        update public.upload_keys set used_at = now()
        where key_hash = %s and used_at is null and revoked_at is null
          and expires_at > now()
        returning id, item_id
        """,
        (key_hash(key),),
    ).fetchone()


def add_original(conn, key_id, movie_id):
    original_id = uuid.uuid4()
    conn.execute(
        """
        insert into public.media_originals
          (id, item_id, upload_key_id, size_bytes, filename)
        values (%s, %s, %s, %s, %s)
        """,
        (original_id, movie_id, key_id, 1_000_000, "film.mp4"),
    )
    return original_id


@needs_database
def test_a_key_is_stored_only_as_its_hash(owner_url, movie):
    key, text = grant(owner_url, movie)

    with psycopg.connect(owner_url) as conn:
        stored = conn.execute(
            "select key_hash, label, expires_at - created_at from public.upload_keys "
            "where id = %s",
            (key.id,),
        ).fetchone()
        everything = str(
            conn.execute(
                "select * from public.upload_keys where id = %s", (key.id,)
            ).fetchone()
        )
    assert stored[0] == key_hash(text)
    assert stored[1] == "Kampala Films"
    assert stored[2] == timedelta(days=7)
    assert text not in everything
    assert key.state(datetime.now(UTC)) == "unused"


@needs_database
@pytest.mark.parametrize("days", [0, 31])
def test_a_key_lasts_one_to_30_days(owner_url, movie, days):
    with pytest.raises(UploadKeyError):
        grant(owner_url, movie, days=days)


@needs_database
def test_the_media_role_uses_a_key_once_and_adds_its_original(
    owner_url, media_url, movie
):
    key, text = grant(owner_url, movie)

    with psycopg.connect(media_url) as conn:
        claimed = claim(conn, text)
        assert claimed == (key.id, movie)
        original_id = add_original(conn, key.id, movie)
        conn.commit()
        assert claim(conn, text) is None
        conn.execute(
            "update public.media_originals set state = 'received' where id = %s",
            (original_id,),
        )
        conn.commit()

    with psycopg.connect(owner_url) as conn:
        [uploads] = list_uploads(conn, movie)
    assert uploads.keys[0].used_at is not None
    assert [(o.id, o.state) for o in uploads.originals] == [(original_id, "received")]


@needs_database
def test_wrong_expired_and_revoked_keys_dont_work(owner_url, media_url, movie):
    _, expired = grant(owner_url, movie)
    revoked_key, revoked = grant(owner_url, movie)
    with psycopg.connect(owner_url) as conn:
        conn.execute(
            "update public.upload_keys set created_at = now() - interval '9 days', "
            "expires_at = now() - interval '1 day' where key_hash = %s",
            (key_hash(expired),),
        )
        assert revoke_upload(conn, str(revoked_key.id)).revoked_at is not None

    with psycopg.connect(media_url) as conn:
        assert claim(conn, new_key()) is None
        assert claim(conn, expired) is None
        assert claim(conn, revoked) is None


@needs_database
def test_an_original_needs_a_used_key_for_the_same_movie(owner_url, media_url, movie):
    unused_key, _ = grant(owner_url, movie)
    used_key, used = grant(owner_url, movie)
    with psycopg.connect(owner_url) as conn:
        other_movie = new_item(conn)
    with psycopg.connect(media_url) as conn:
        claim(conn, used)
        conn.commit()

    for key_id, movie_id in [(unused_key.id, movie), (used_key.id, other_movie)]:
        with (
            psycopg.connect(media_url) as conn,
            pytest.raises(errors.InsufficientPrivilege),
        ):
            add_original(conn, key_id, movie_id)


@needs_database
@pytest.mark.parametrize(
    "statement",
    [
        "insert into public.upload_keys (item_id, key_hash, label, expires_at) "
        "select id, sha256('x'), 'x', now() + interval '1 day' "
        "from public.media_originals",
        "update public.upload_keys set revoked_at = null",
        "update public.upload_keys set label = 'x'",
        "delete from public.upload_keys",
        "delete from public.media_originals",
        "update public.media_originals set item_id = id",
        "update public.media_renditions set width = 1",
        "select label from public.upload_keys",
        "select count(*) from public.editions",
        "update public.editions set status = 'published'",
        "select count(*) from public.sources",
        "select count(*) from public.admins",
        "select count(*) from public.profiles",
    ],
)
def test_the_media_role_can_do_nothing_else(media_url, statement):
    with (
        psycopg.connect(media_url) as conn,
        pytest.raises(errors.InsufficientPrivilege),
    ):
        conn.execute(statement)


@needs_database
@pytest.mark.parametrize(
    "statement",
    [
        "select count(*) from public.upload_keys",
        "select filename from public.media_originals",
        "select size_bytes, reason from public.media_originals",
        "select count(*) from public.media_renditions",
        "update public.upload_keys set used_at = now()",
        "update public.media_originals set state = 'ready'",
        "delete from public.media_originals",
        "insert into public.media_originals (id, item_id, upload_key_id, size_bytes) "
        "values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 1)",
    ],
)
def test_the_api_role_cant_see_uploads(app_url, statement):
    with psycopg.connect(app_url) as conn, pytest.raises(errors.InsufficientPrivilege):
        conn.execute(statement)


@needs_database
def test_the_database_checks_cover_uploads(app_url):
    results = {result.name: result for result in run_checks(app_url)}

    for name in (
        "RLS and forced RLS on the upload tables",
        "can't read or change upload keys or qualities",
        "reads only the ID, item, state and duration of originals, and changes none",
        "sees ready originals of published, approved items only",
    ):
        assert results[name].passed, results[name]
    assert all(result.passed for result in results.values())


@needs_database
def test_the_owner_commands_end_to_end(owner_url, movie, monkeypatch, capsys):
    monkeypatch.setenv("VELORAUG_MIGRATION_DATABASE_URL", owner_url)

    def run(*args):
        monkeypatch.setattr("sys.argv", ["catalogue.py", *args])
        code = catalogue.main()
        return code, capsys.readouterr()

    code, out = run("grant-upload", str(movie), "--for", "Owner", "--days", "2")
    assert code == 0
    [key] = [line.strip() for line in out.out.splitlines() if KEY_PREFIX in line]
    assert key.startswith(KEY_PREFIX)
    assert "shown only this once" in out.out

    code, out = run("uploads", str(movie))
    assert code == 0
    assert "key for Owner: expires" in out.out
    assert key not in out.out
    [key_id] = [
        line.rsplit("key id ", 1)[1]
        for line in out.out.splitlines()
        if "key id" in line
    ]

    code, out = run("revoke-upload", key_id)
    assert code == 0
    assert out.out.splitlines()[-1] == "Key for Owner revoked. It can't be used now."

    code, out = run("uploads", str(movie))
    assert "key for Owner: revoked" in out.out

    code, out = run("revoke-upload", "not-an-id")
    assert code == 1
    assert "isn't a key ID" in out.err


def ready_original(owner_url, media_url, movie, heights=(360, 480)):
    """An original taken all the way to 'ready', as the worker will."""
    key, text = grant(owner_url, movie)
    with psycopg.connect(media_url) as conn:
        claim(conn, text)
        original_id = add_original(conn, key.id, movie)
        conn.execute(
            "update public.media_originals set state = 'publishing' where id = %s",
            (original_id,),
        )
        for height in heights:
            add_quality(conn, original_id, height)
        conn.execute(
            "update public.media_originals set state = 'ready', ready_at = now() "
            "where id = %s",
            (original_id,),
        )
    return original_id


def add_quality(conn, original_id, height):
    conn.execute(
        """
        insert into public.media_renditions
          (original_id, height, width, bandwidth, size_bytes)
        values (%s, %s, %s, %s, %s)
        """,
        (original_id, height, height * 16 // 9, 1_000_000, 50_000_000),
    )


@needs_database
def test_qualities_are_added_while_publishing_and_listed(owner_url, media_url, movie):
    original_id = ready_original(owner_url, media_url, movie, (360, 480, 720, 1080))

    with psycopg.connect(owner_url) as conn:
        [uploads] = list_uploads(conn, movie)
    assert uploads.originals[0].id == original_id
    assert uploads.originals[0].qualities == (360, 480, 720, 1080)


@needs_database
def test_qualities_cant_be_added_outside_publishing_or_above_1080p(
    owner_url, media_url, movie
):
    original_id = ready_original(owner_url, media_url, movie)

    with psycopg.connect(media_url) as conn:
        with pytest.raises(errors.InsufficientPrivilege):
            add_quality(conn, original_id, 720)

    with psycopg.connect(media_url) as conn:
        conn.execute(
            "update public.media_originals set state = 'publishing', ready_at = null "
            "where id = %s",
            (original_id,),
        )
        with pytest.raises(errors.CheckViolation):
            add_quality(conn, original_id, 2160)


@needs_database
def test_qualities_are_deleted_only_while_removing(owner_url, media_url, movie):
    original_id = ready_original(owner_url, media_url, movie)
    delete = "delete from public.media_renditions where original_id = %s"

    with psycopg.connect(media_url) as conn:
        assert conn.execute(delete, (original_id,)).rowcount == 0
        conn.execute(
            "update public.media_originals set state = 'removing' where id = %s",
            (original_id,),
        )
        assert conn.execute(delete, (original_id,)).rowcount == 2


@needs_database
def test_a_movie_has_one_ready_original(owner_url, media_url, movie):
    ready_original(owner_url, media_url, movie)

    with pytest.raises(errors.UniqueViolation):
        ready_original(owner_url, media_url, movie)
