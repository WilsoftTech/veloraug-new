# Fixtures imported from test_media_publisher are used as arguments.
# ruff: noqa: F811
"""Step 12A: making download.mp4 for films published before downloads.

On a real Postgres, with R2, FFmpeg and FFprobe faked. Skipped without a
local test Postgres: see tests/db_support.py.
"""

import subprocess
import sys
from pathlib import Path

import psycopg
import pytest

from app.download_files import (
    AlreadyRunning,
    BackfillError,
    backfill,
    only_run,
    playlist_files,
)
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
WHOLE = 12.0


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


class FakeLength:
    """Stands in for FFprobe: every file is whole, except those whose
    address or path contains one of [short], which last 5 s."""

    def __init__(self, *short: str):
        self.short = short
        self.measured: list[str] = []

    def __call__(self, source: str) -> float:
        self.measured.append(source)
        return 5.0 if any(s in source for s in self.short) else WHOLE


def published(bucket: FakeBucket, prefix: str) -> None:
    """A film as published before Step 12A: chunks, no download files."""
    bucket.put(f"{prefix}/master.m3u8", MASTER.encode())
    for quality in ("360p", "720p"):
        bucket.put(f"{prefix}/{quality}/index.m3u8", PLAYLIST.encode())
        for name in ("init_0.mp4", "seg_00000.m4s", "seg_00001.m4s"):
            bucket.put(f"{prefix}/{quality}/{name}", f"{quality}/{name};".encode())


def run(database, bucket, work, *, join=None, length=None, say=None, **options):
    return backfill(
        database,
        bucket,
        work,
        run=join or FakeJoin(),
        measure=length or FakeLength(),
        say=say or (lambda _: None),
        **options,
    )


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

    assert run(media_database, bucket, tmp_path, join=join) == (2, 0, 0)

    data, content_type, cache, _ = bucket.objects[f"{ready}/720p/download.mp4"]
    assert data == b"720p/init_0.mp4;720p/seg_00000.m4s;720p/seg_00001.m4s;"
    assert content_type == "video/mp4"
    assert cache == "max-age=31536000, immutable"
    assert list(tmp_path.iterdir()) == []

    # Run again: everything is already there, and measured whole.
    length = FakeLength()
    again = run(media_database, bucket, tmp_path, join=join, length=length)
    assert again == (0, 2, 0)
    assert len(join.runs) == 2
    assert length.measured == [
        f"r2://{ready}/{q}/download.mp4" for q in ("360p", "720p")
    ]


@needs_database
def test_a_join_shorter_than_its_playlist_is_never_uploaded(
    media_database, ready, tmp_path
):
    bucket = FakeBucket()
    published(bucket, ready)
    said = []

    counts = run(
        media_database, bucket, tmp_path, length=FakeLength("360p"), say=said.append
    )

    assert counts == (1, 0, 1)
    assert said[0] == (
        f"FAILED:  {ready}/360p/download.mp4: Joining 360p made 5 s of 12 s."
    )
    assert f"{ready}/360p/download.mp4" not in bucket.objects


@needs_database
def test_a_short_file_already_in_r2_is_made_again(media_database, ready, tmp_path):
    bucket = FakeBucket()
    published(bucket, ready)
    bucket.put(f"{ready}/720p/download.mp4", b"cut short")
    bucket.put(f"{ready}/360p/download.mp4", b"whole")
    said = []

    counts = run(
        media_database,
        bucket,
        tmp_path,
        length=FakeLength(f"r2://{ready}/720p"),
        say=said.append,
    )

    assert counts == (1, 1, 0)
    assert said[0] == f"short:   {ready}/720p/download.mp4: 5 s of 12 s"
    assert bucket.objects[f"{ready}/720p/download.mp4"][0].startswith(b"720p/init")
    assert bucket.objects[f"{ready}/360p/download.mp4"][0] == b"whole"


@needs_database
def test_listing_makes_nothing(media_database, ready, tmp_path):
    bucket = FakeBucket()
    published(bucket, ready)
    said = []

    counts = run(media_database, bucket, tmp_path, list_only=True, say=said.append)

    assert counts == (2, 0, 0)
    assert said == [f"to make: {ready}/{q}/download.mp4" for q in ("360p", "720p")]
    assert not any(k.endswith("download.mp4") for k in bucket.objects)


@needs_database
def test_one_quality_failing_doesnt_stop_the_others(media_database, ready, tmp_path):
    bucket = FakeBucket()
    published(bucket, ready)
    said = []

    counts = run(
        media_database,
        bucket,
        tmp_path,
        join=FakeJoin(fails_for="360p"),
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

    assert run(media_database, bucket, tmp_path) == (0, 0, 2)


@needs_database
def test_a_film_whose_playlist_cant_be_read_is_reported_and_skipped(
    media_database, ready, tmp_path
):
    said = []

    counts = run(media_database, FakeBucket(), tmp_path, say=said.append)

    assert counts == (0, 0, 1)
    assert said[0].startswith(f"FAILED:  {ready}/master.m3u8: ")


@pytest.mark.skipif(sys.platform == "win32", reason="the lock is Linux's flock")
def test_only_one_run_at_a_time(tmp_path):
    lock = tmp_path / "work.lock"
    with only_run(lock):
        with pytest.raises(AlreadyRunning), only_run(lock):
            pass
    # Released once the first run ends.
    with only_run(lock):
        pass
