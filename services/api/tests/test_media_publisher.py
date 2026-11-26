"""Publishing to R2 and removing from it, with an in-memory stand-in for the
bucket. The real bucket is checked in the owner's run: see
docs/step-07e-report.md.

The database tests run on a real local Postgres, as veloraug_media. Skipped
without one: see tests/db_support.py.
"""

import os
import uuid
from pathlib import Path

import psycopg
import pytest
from pydantic import ValidationError

from app.db import Database
from app.media_publisher import (
    IMMUTABLE,
    Publisher,
    PublishError,
    Quality,
    R2Settings,
    R2Store,
    read_master,
)
from app.media_worker import ATTEMPTS, RETRY_SECONDS, Worker
from scripts.create_app_role import scram_verifier
from scripts.upload_keys import UploadKeyError, list_uploads, request_removal
from tests.db_support import needs_database, new_item, url_for

MEDIA_PASSWORD = "local-test-media-password"

MASTER = """#EXTM3U
#EXT-X-VERSION:7
#EXT-X-STREAM-INF:BANDWIDTH=895245,AVERAGE-BANDWIDTH=887776,RESOLUTION=640x360,CODECS="avc1.64001e,mp4a.40.2"
360p/index.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=2914299,AVERAGE-BANDWIDTH=2906341,RESOLUTION=1280x534,CODECS="avc1.64001f,mp4a.40.2"
720p/index.m3u8
"""


class FakeBucket:
    """Keeps what was uploaded: key -> (bytes, content type, cache, class)."""

    def __init__(self, wrong_size_for: str | None = None, fail_uploads: int = 0):
        self.objects: dict[str, tuple[bytes, str, str | None, str]] = {}
        self.order: list[str] = []
        self.wrong_size_for = wrong_size_for
        self.fail_uploads = fail_uploads

    def upload(self, path, key, content_type, cache_control=None, infrequent=False):
        if self.fail_uploads:
            self.fail_uploads -= 1
            raise ConnectionError("R2 hung up")
        data = Path(path).read_bytes()
        if self.wrong_size_for and key.endswith(self.wrong_size_for):
            data = data[:-1]
        cls = "STANDARD_IA" if infrequent else "STANDARD"
        self.objects[key] = (data, content_type, cache_control, cls)
        self.order.append(key)

    def size(self, key):
        found = self.objects.get(key)
        return len(found[0]) if found else None

    def download(self, key, path):
        Path(path).write_bytes(self.objects[key][0])

    def read_url(self, key):
        return f"r2://{key}"

    def put(self, key, data: bytes):
        """Puts a file there directly, as an earlier publish did."""
        self.objects[key] = (data, "", IMMUTABLE, "STANDARD")

    def delete_prefix(self, prefix):
        keys = [k for k in self.objects if k.startswith(prefix)]
        for key in keys:
            del self.objects[key]
        return len(keys)


def converted(output: Path, uploads: Path, original_id, qualities=("360p", "720p")):
    """The files FFmpeg and tusd leave for one original."""
    out = output / str(original_id)
    for index, name in enumerate(qualities):
        (out / name).mkdir(parents=True)
        (out / name / f"init_{index}.mp4").write_bytes(os.urandom(700))
        for n in range(3):
            (out / name / f"seg_{n:05d}.m4s").write_bytes(os.urandom(1000 + n))
        (out / name / "index.m3u8").write_text("#EXTM3U\n")
        (out / name / "download.mp4").write_bytes(os.urandom(4000))
    (out / "master.m3u8").write_text(MASTER)
    (uploads / str(original_id)).write_bytes(os.urandom(5000))
    (uploads / f"{original_id}.info").write_text("{}")


# --- Needs no database -------------------------------------------------------


def test_the_master_playlist_gives_each_qualitys_size_and_bandwidth(tmp_path):
    (tmp_path / "master.m3u8").write_text(MASTER)

    assert read_master(tmp_path / "master.m3u8") == [
        Quality("360p", 640, 360, 895245),
        Quality("720p", 1280, 534, 2914299),
    ]


def test_r2_settings_are_all_or_none():
    assert R2Settings().configured is False
    with pytest.raises(ValidationError):
        R2Settings(endpoint="https://abc.r2.cloudflarestorage.com")


@pytest.mark.parametrize(
    "endpoint",
    [
        "http://abc.r2.cloudflarestorage.com",
        "https://evil.example",
        "https://abc.r2.cloudflarestorage.com/another-bucket",
    ],
)
def test_only_an_r2_endpoint_is_accepted(endpoint):
    with pytest.raises(ValidationError) as error:
        R2Settings(
            endpoint=endpoint,
            bucket="veloraug-dev",
            access_key_id="id",
            secret_access_key="very-secret",
        )
    assert "very-secret" not in str(error.value)


def test_a_full_r2_setup_is_accepted_and_tidied():
    settings = R2Settings(
        endpoint="https://abc123.r2.cloudflarestorage.com/",
        bucket="veloraug-dev",
        access_key_id="id",
        secret_access_key="Zq9-not-shown",
    )

    assert settings.configured
    assert settings.endpoint == "https://abc123.r2.cloudflarestorage.com"
    assert "Zq9-not-shown" not in repr(settings)


def test_the_r2_store_sets_types_cache_and_infrequent_access(monkeypatch, tmp_path):
    settings = R2Settings(
        endpoint="https://abc123.r2.cloudflarestorage.com",
        bucket="veloraug-dev",
        access_key_id="id",
        secret_access_key="secret",
    )
    store = R2Store(settings)
    calls = []
    monkeypatch.setattr(
        store.client,
        "upload_file",
        lambda *args, **kwargs: calls.append((args, kwargs)),
    )
    path = tmp_path / "f"
    path.write_bytes(b"x")

    store.upload(path, "movies/a/b/360p/seg_00000.m4s", "video/iso.segment", IMMUTABLE)
    store.upload(path, "originals/b", "application/octet-stream", infrequent=True)

    assert calls[0][0][1:] == ("veloraug-dev", "movies/a/b/360p/seg_00000.m4s")
    assert calls[0][1]["ExtraArgs"] == {
        "ContentType": "video/iso.segment",
        "CacheControl": IMMUTABLE,
    }
    assert calls[1][1]["ExtraArgs"] == {
        "ContentType": "application/octet-stream",
        "StorageClass": "STANDARD_IA",
    }
    assert store.client.meta.endpoint_url == "https://abc123.r2.cloudflarestorage.com"


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
def folders(tmp_path):
    uploads, output = tmp_path / "uploads", tmp_path / "output"
    uploads.mkdir()
    output.mkdir()
    return uploads, output


@pytest.fixture
def quiet_queue(owner_url, app_url):
    """Nothing else waiting, so each test's worker picks its own originals."""
    with psycopg.connect(owner_url) as conn:
        conn.execute(
            "update public.media_originals set state = 'failed' where state in "
            "('received', 'checking', 'converting', 'uploading', 'publishing', "
            "'removing')"
        )


@pytest.fixture
def movie(owner_url, app_url):
    with psycopg.connect(owner_url) as conn:
        movie_id = new_item(conn)
    return movie_id


def waiting_original(owner_url, movie_id, state="publishing"):
    original_id = uuid.uuid4()
    with psycopg.connect(owner_url) as conn:
        (key_id,) = conn.execute(
            """
            insert into public.upload_keys
              (item_id, key_hash, label, expires_at, used_at)
            values (%s, %s, 'Test', now() + interval '1 day', now()) returning id
            """,
            (movie_id, os.urandom(32)),
        ).fetchone()
        conn.execute(
            """
            insert into public.media_originals
              (id, item_id, upload_key_id, size_bytes, state)
            values (%s, %s, %s, 5000, %s)
            """,
            (original_id, movie_id, key_id, state),
        )
    return original_id


def state_of(owner_url, original_id):
    with psycopg.connect(owner_url) as conn:
        return conn.execute(
            "select state, reason from public.media_originals where id = %s",
            (original_id,),
        ).fetchone()


def qualities_of(owner_url, original_id):
    with psycopg.connect(owner_url) as conn:
        return conn.execute(
            """
            select height, width, bandwidth, size_bytes from public.media_renditions
            where original_id = %s order by height
            """,
            (original_id,),
        ).fetchall()


@needs_database
def test_publishing_uploads_everything_in_order_and_marks_it_ready(
    owner_url, media_database, folders, movie, quiet_queue
):
    uploads, output = folders
    original_id = waiting_original(owner_url, movie)
    converted(output, uploads, original_id)
    bucket = FakeBucket()
    publisher = Publisher(media_database, bucket, uploads, output)

    assert Worker(media_database, uploads, output, publisher=publisher).run_once()

    prefix = f"movies/{movie}/{original_id}"
    keys = bucket.order
    assert len(keys) == 2 * 6 + 1
    assert keys[-1] == f"{prefix}/master.m3u8"
    # The original isn't kept in R2: the owner keeps their own copy.
    assert not any(k.startswith("originals/") for k in keys)
    for quality in ("360p", "720p"):
        playlist = keys.index(f"{prefix}/{quality}/index.m3u8")
        chunks = [
            i for i, k in enumerate(keys) if k.startswith(f"{prefix}/{quality}/seg")
        ]
        assert max(chunks) < playlist
    assert bucket.objects[f"{prefix}/360p/seg_00000.m4s"][1:] == (
        "video/iso.segment",
        IMMUTABLE,
        "STANDARD",
    )
    assert bucket.objects[f"{prefix}/master.m3u8"][1] == "application/vnd.apple.mpegurl"
    assert state_of(owner_url, original_id) == ("ready", None)
    assert bucket.objects[f"{prefix}/720p/download.mp4"][1] == "video/mp4"
    heights = [(h, w, b) for h, w, b, _ in qualities_of(owner_url, original_id)]
    assert heights == [(360, 640, 895245), (720, 1280, 2914299)]
    # A quality's size is what is streamed, not the download file as well.
    streamed = 700 + 1000 + 1001 + 1002 + len("#EXTM3U" + os.linesep)
    sizes = [size for *_, size in qualities_of(owner_url, original_id)]
    assert sizes == [streamed, streamed]
    assert not (output / str(original_id)).exists()
    assert not (uploads / str(original_id)).exists()
    assert not (uploads / f"{original_id}.info").exists()


@needs_database
def test_a_size_that_doesnt_match_stops_it_before_ready(
    owner_url, media_database, folders, movie, quiet_queue
):
    uploads, output = folders
    original_id = waiting_original(owner_url, movie)
    converted(output, uploads, original_id)
    publisher = Publisher(
        media_database, FakeBucket(wrong_size_for="seg_00001.m4s"), uploads, output
    )

    with pytest.raises(PublishError):
        publisher.publish(original_id)

    assert state_of(owner_url, original_id)[0] == "publishing"
    assert qualities_of(owner_url, original_id) == []
    assert (output / str(original_id) / "master.m3u8").exists()


@needs_database
def test_failures_wait_longer_each_time_then_give_up(
    owner_url, media_database, folders, movie, quiet_queue
):
    uploads, output = folders
    original_id = waiting_original(owner_url, movie)
    converted(output, uploads, original_id)
    now = [1000.0]
    bucket = FakeBucket(fail_uploads=99)
    worker = Worker(
        media_database,
        uploads,
        output,
        clock=lambda: now[0],
        publisher=Publisher(media_database, bucket, uploads, output),
    )

    assert worker.run_once() is True
    assert worker.run_once() is False  # waiting to retry
    now[0] += RETRY_SECONDS
    assert worker.run_once() is True
    now[0] += RETRY_SECONDS * 2
    assert worker.run_once() is True

    state, reason = state_of(owner_url, original_id)
    assert state == "failed"
    assert reason == (
        f"Publishing to R2 failed {ATTEMPTS} times: ConnectionError: R2 hung up"
    )
    assert (uploads / str(original_id)).exists()


@needs_database
def test_a_new_original_takes_over_and_the_old_one_is_removed(
    owner_url, media_database, folders, movie, quiet_queue
):
    uploads, output = folders
    bucket = FakeBucket()
    publisher = Publisher(media_database, bucket, uploads, output)
    worker = Worker(media_database, uploads, output, publisher=publisher)
    first = waiting_original(owner_url, movie)
    converted(output, uploads, first)
    worker.run_once()
    second = waiting_original(owner_url, movie)
    converted(output, uploads, second)

    worker.run_once()

    assert state_of(owner_url, second)[0] == "ready"
    assert state_of(owner_url, first)[0] == "removing"
    assert any(str(first) in key for key in bucket.objects)

    worker.run_once()

    assert state_of(owner_url, first)[0] == "removed"
    assert qualities_of(owner_url, first) == []
    assert not any(str(first) in key for key in bucket.objects)
    assert any(str(second) in key for key in bucket.objects)


@needs_database
def test_the_owner_can_mark_an_original_for_removal(
    owner_url, media_database, folders, movie, quiet_queue
):
    uploads, output = folders
    bucket = FakeBucket()
    publisher = Publisher(media_database, bucket, uploads, output)
    original_id = waiting_original(owner_url, movie)
    converted(output, uploads, original_id)
    Worker(media_database, uploads, output, publisher=publisher).run_once()

    with psycopg.connect(owner_url) as conn:
        assert request_removal(conn, str(original_id)) == "ready"
        with pytest.raises(UploadKeyError):
            request_removal(conn, str(original_id))
        with pytest.raises(UploadKeyError):
            request_removal(conn, "nope")
    Worker(media_database, uploads, output, publisher=publisher).run_once()

    assert state_of(owner_url, original_id)[0] == "removed"
    assert bucket.objects == {}
    with psycopg.connect(owner_url) as conn:
        [movie_uploads] = list_uploads(conn, movie)
    assert movie_uploads.originals[0].state == "removed"


@needs_database
def test_without_r2_a_converted_original_waits(
    owner_url, media_database, folders, movie, quiet_queue
):
    uploads, output = folders
    original_id = waiting_original(owner_url, movie)
    converted(output, uploads, original_id)

    assert Worker(media_database, uploads, output).run_once() is False
    assert state_of(owner_url, original_id)[0] == "publishing"


def test_the_dashboards_address_with_the_bucket_on_the_end_is_accepted():
    settings = R2Settings(
        endpoint="https://abc123.r2.cloudflarestorage.com/veloraug-dev",
        bucket="veloraug-dev",
        access_key_id="id",
        secret_access_key="key",
    )

    assert settings.endpoint == "https://abc123.r2.cloudflarestorage.com"


def test_check_r2_explains_bad_settings_without_a_traceback(monkeypatch, capsys):
    from scripts import check_r2

    monkeypatch.setattr(check_r2, "ENV_FILE", check_r2.API_DIR / "no-such.env")
    monkeypatch.setenv("VELORAUG_R2_ENDPOINT", "https://x.r2.cloudflarestorage.com/a/b")
    monkeypatch.setenv("VELORAUG_R2_BUCKET", "veloraug-dev")
    monkeypatch.setenv("VELORAUG_R2_ACCESS_KEY_ID", "id")
    monkeypatch.setenv("VELORAUG_R2_SECRET_ACCESS_KEY", "Zq9-not-shown")

    assert check_r2.main() == 1
    out = capsys.readouterr().out
    assert "without /a/b on the end" in out
    assert "Zq9-not-shown" not in out


@needs_database
def test_publishing_reports_the_share_of_bytes_sent(
    owner_url, media_database, folders, movie, quiet_queue
):
    uploads, output = folders
    original_id = waiting_original(owner_url, movie)
    converted(output, uploads, original_id)
    heard = []

    Publisher(media_database, FakeBucket(), uploads, output).publish(
        original_id, on_progress=heard.append
    )

    # One report per file sent, rising, and 100 only once it is ready.
    assert len(heard) == 2 * 6 + 1
    assert heard == sorted(heard)
    assert 0 < heard[0] and heard[-1] <= 99
    assert state_of(owner_url, original_id) == ("ready", None)
