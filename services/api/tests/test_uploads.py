"""Upload keys and media versions: migration 0003 and the owner's commands.

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
from scripts.create_app_role import scram_verifier
from scripts.upload_keys import (
    KEY_PREFIX,
    MovieUploads,
    UploadKey,
    UploadKeyError,
    Version,
    clean_label,
    describe_uploads,
    grant_upload,
    key_hash,
    list_uploads,
    new_key,
    revoke_upload,
    size_text,
)
from tests.db_support import needs_database, url_for

MEDIA_PASSWORD = "local-test-media-password"
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
        "movie_id": uuid.UUID(int=2),
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


def test_uploads_lists_each_key_with_its_version():
    used = _key(id=uuid.UUID(int=3), used_at=NOW)
    version = Version(
        id=uuid.UUID(int=4),
        upload_key_id=used.id,
        state="refused",
        size_bytes=1_500_000_000,
        height=1080,
        video_codec="h264",
        audio_codec="ac3",
        reason="Audio is AC-3. VeloraUG accepts AAC or MP3 audio.",
    )
    movie = MovieUploads(uuid.UUID(int=2), 550, "Fight Club", [_key(), used], [version])

    lines = describe_uploads(movie, NOW)

    assert lines == [
        "Fight Club  TMDB 550",
        f"  key for Kampala Films: expires 18 Nov 12:00 UTC  key id {uuid.UUID(int=1)}",
        f"  key for Kampala Films: used  key id {uuid.UUID(int=3)}",
        f"    version {uuid.UUID(int=4)}: refused, 1.5 GB, 1080p H264/AC3. "
        "Audio is AC-3. VeloraUG accepts AAC or MP3 audio.",
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


@pytest.fixture(scope="module")
def media_url(owner_url, app_url):
    """The media role, given a login as Step 7C's script will."""
    with psycopg.connect(owner_url) as conn:
        verifier = scram_verifier(MEDIA_PASSWORD)
        conn.execute(f"alter role veloraug_media login password '{verifier}'")
    return url_for("veloraug_media", MEDIA_PASSWORD)


@pytest.fixture
def movie(owner_url, app_url):
    """A movie of its own for each test, committed so other roles see it."""
    with psycopg.connect(owner_url) as conn:
        (movie_id,) = conn.execute(
            "insert into public.movies (tmdb_id) values (%s) returning id",
            (1_000_000 + uuid.uuid4().int % 1_000_000_000,),
        ).fetchone()
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
        returning id, movie_id
        """,
        (key_hash(key),),
    ).fetchone()


def add_version(conn, key_id, movie_id):
    version_id = uuid.uuid4()
    conn.execute(
        """
        insert into public.media_versions
          (id, movie_id, upload_key_id, size_bytes, filename)
        values (%s, %s, %s, %s, %s)
        """,
        (version_id, movie_id, key_id, 1_000_000, "film.mp4"),
    )
    return version_id


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
def test_the_media_role_uses_a_key_once_and_adds_its_version(
    owner_url, media_url, movie
):
    key, text = grant(owner_url, movie)

    with psycopg.connect(media_url) as conn:
        claimed = claim(conn, text)
        assert claimed == (key.id, movie)
        version_id = add_version(conn, key.id, movie)
        conn.commit()
        assert claim(conn, text) is None
        conn.execute(
            "update public.media_versions set state = 'received' where id = %s",
            (version_id,),
        )
        conn.commit()

    with psycopg.connect(owner_url) as conn:
        [uploads] = list_uploads(conn, movie)
    assert uploads.keys[0].used_at is not None
    assert [(v.id, v.state) for v in uploads.versions] == [(version_id, "received")]


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
def test_a_version_needs_a_used_key_for_the_same_movie(owner_url, media_url, movie):
    unused_key, _ = grant(owner_url, movie)
    used_key, used = grant(owner_url, movie)
    with psycopg.connect(owner_url) as conn:
        (other_movie,) = conn.execute(
            "insert into public.movies (tmdb_id) values (%s) returning id",
            (1_000_000 + uuid.uuid4().int % 1_000_000_000,),
        ).fetchone()
    with psycopg.connect(media_url) as conn:
        claim(conn, used)
        conn.commit()

    for key_id, movie_id in [(unused_key.id, movie), (used_key.id, other_movie)]:
        with (
            psycopg.connect(media_url) as conn,
            pytest.raises(errors.InsufficientPrivilege),
        ):
            add_version(conn, key_id, movie_id)


@needs_database
@pytest.mark.parametrize(
    "statement",
    [
        "insert into public.upload_keys (movie_id, key_hash, label, expires_at) "
        "select id, sha256('x'), 'x', now() + interval '1 day' "
        "from public.media_versions",
        "update public.upload_keys set revoked_at = null",
        "update public.upload_keys set label = 'x'",
        "delete from public.upload_keys",
        "delete from public.media_versions",
        "update public.media_versions set movie_id = id",
        "select label from public.upload_keys",
        "select count(*) from public.movies",
        "update public.movies set published = true",
        "select count(*) from public.tmdb_movie_details",
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
        "select count(*) from public.media_versions",
        "update public.upload_keys set used_at = now()",
        "insert into public.media_versions (id, movie_id, upload_key_id, size_bytes) "
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
        "RLS and forced RLS on upload_keys and media_versions",
        "can't read or change upload keys or media versions",
    ):
        assert results[name].passed, results[name]
    assert all(result.passed for result in results.values())


@needs_database
def test_the_owner_commands_end_to_end(owner_url, movie, monkeypatch, capsys):
    with psycopg.connect(owner_url) as conn:
        (tmdb_id,) = conn.execute(
            "select tmdb_id from public.movies where id = %s", (movie,)
        ).fetchone()
    monkeypatch.setenv("VELORAUG_MIGRATION_DATABASE_URL", owner_url)

    def run(*args):
        monkeypatch.setattr("sys.argv", ["catalogue.py", *args])
        code = catalogue.main()
        return code, capsys.readouterr()

    code, out = run("grant-upload", str(tmdb_id), "--for", "Owner", "--days", "2")
    assert code == 0
    [key] = [line.strip() for line in out.out.splitlines() if KEY_PREFIX in line]
    assert key.startswith(KEY_PREFIX)
    assert "shown only this once" in out.out

    code, out = run("uploads", str(tmdb_id))
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

    code, out = run("uploads", str(tmdb_id))
    assert "key for Owner: revoked" in out.out

    code, out = run("revoke-upload", "not-an-id")
    assert code == 1
    assert "isn't a key ID" in out.err
