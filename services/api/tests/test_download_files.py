# Fixtures imported from test_media_publisher are used as arguments.
# ruff: noqa: F811
"""Step 12A: making download.mp4 for films published before downloads.

On a real Postgres, with R2 and FFmpeg faked. Skipped without a local test
Postgres: see tests/db_support.py.
"""

import subprocess
from pathlib import Path

import psycopg
import pytest

from app.download_files import BackfillError, backfill, playlist_files
from tests.db_support import needs_database
from tests.test_admin import ready as make_ready
from tests.test_media_publisher import (  # noqa: F401
    MASTER,
    FakeBucket,
    media_database,
    movie,
    quiet_queue,
)

PLAYLIST = """#EXTM3U
#EXT-X-VERSION:7
#EXT-X-MAP:URI="init_0.mp4"
#EXTINF:6.0,
seg_00000.m4s
#EXTINF:6.0,
seg_00001.m4s
#EXT-X-ENDLIST
"""


class FakeJoin:
    """Stands in for FFmpeg: joins the fetched files, as the real one would."""

    def __init__(self, fails_for: str | None = None):
        self.fails_for = fails_for
        self.runs: list[str] = []

    def __call__(self, command, cwd, **kwargs):
        target = command[-1]
        self.runs.append(target)
        quality = target.split("/")[0]
        if quality == self.fails_for:
            return subprocess.CompletedProcess(command, 1, "", "Invalid data\n")
        folder = Path(cwd) / quality
        joined = b"".join(
            (folder / name).read_bytes()
            for name in ("init_0.mp4", "seg_00000.m4s", "seg_00001.m4s")
        )
        (Path(cwd) / target).write_bytes(joined)
        return subprocess.CompletedProcess(command, 0, "", "")


def published(bucket: FakeBucket, prefix: str) -> None:
    """A film as published before Step 12A: chunks, no download files."""
    bucket.put(f"{prefix}/master.m3u8", MASTER.encode())
    for quality in ("360p", "720p"):
        bucket.put(f"{prefix}/{quality}/index.m3u8", PLAYLIST.encode())
        for name in ("init_0.mp4", "seg_00000.m4s", "seg_00001.m4s"):
            bucket.put(f"{prefix}/{quality}/{name}", f"{quality}/{name};".encode())


@pytest.fixture
def ready(owner_url, movie, quiet_queue):
    with psycopg.connect(owner_url, autocommit=True) as conn:
        # Other tests' ready originals aren't in this test's bucket.
        conn.execute(
            "update public.media_originals set state = 'failed' where state = 'ready'"
        )
        original_id = make_ready(conn, movie)
    return f"movies/{movie}/{original_id}"


def test_a_playlist_names_its_init_file_and_chunks():
    assert playlist_files(PLAYLIST) == ["init_0.mp4", "seg_00000.m4s", "seg_00001.m4s"]


@pytest.mark.parametrize(
    "bad", ["../seg_00000.m4s", "https://elsewhere.test/a.m4s", "seg_1.ts"]
)
def test_a_playlist_naming_anything_else_is_refused(bad):
    with pytest.raises(BackfillError):
        playlist_files(PLAYLIST.replace("seg_00001.m4s", bad))


@needs_database
def test_each_quality_gets_its_file_once(media_database, ready, tmp_path):
    bucket = FakeBucket()
    published(bucket, ready)
    join = FakeJoin()

    made = backfill(media_database, bucket, tmp_path, run=join, say=lambda _: None)

    assert made == (2, 0, 0)
    data, content_type, cache, _ = bucket.objects[f"{ready}/720p/download.mp4"]
    assert data == b"720p/init_0.mp4;720p/seg_00000.m4s;720p/seg_00001.m4s;"
    assert content_type == "video/mp4"
    assert cache == "max-age=31536000, immutable"
    assert list(tmp_path.iterdir()) == []

    # Run again: everything is already there.
    again = backfill(media_database, bucket, tmp_path, run=join, say=lambda _: None)
    assert again == (0, 2, 0)
    assert len(join.runs) == 2


@needs_database
def test_listing_makes_nothing(media_database, ready, tmp_path):
    bucket = FakeBucket()
    published(bucket, ready)
    said = []

    counts = backfill(
        media_database,
        bucket,
        tmp_path,
        list_only=True,
        run=FakeJoin(),
        say=said.append,
    )

    assert counts == (2, 0, 0)
    assert said == [f"to make: {ready}/{q}/download.mp4" for q in ("360p", "720p")]
    assert not any(k.endswith("download.mp4") for k in bucket.objects)


@needs_database
def test_one_quality_failing_doesnt_stop_the_others(media_database, ready, tmp_path):
    bucket = FakeBucket()
    published(bucket, ready)
    said = []

    counts = backfill(
        media_database,
        bucket,
        tmp_path,
        run=FakeJoin(fails_for="360p"),
        say=said.append,
    )

    assert counts == (1, 0, 1)
    assert said[0] == (
        f"FAILED:  {ready}/360p/download.mp4: Joining 360p failed: Invalid data"
    )
    assert f"{ready}/720p/download.mp4" in bucket.objects
    assert f"{ready}/360p/download.mp4" not in bucket.objects


@needs_database
def test_an_upload_r2_cut_short_is_a_failure(media_database, ready, tmp_path):
    bucket = FakeBucket(wrong_size_for="download.mp4")
    published(bucket, ready)

    counts = backfill(
        media_database, bucket, tmp_path, run=FakeJoin(), say=lambda _: None
    )

    assert counts == (0, 0, 2)


@needs_database
def test_a_film_whose_playlist_cant_be_read_is_reported_and_skipped(
    media_database, ready, tmp_path
):
    said = []

    counts = backfill(
        media_database, FakeBucket(), tmp_path, run=FakeJoin(), say=said.append
    )

    assert counts == (0, 0, 1)
    assert said[0].startswith(f"FAILED:  {ready}/master.m3u8: ")
