"""The media worker: what it accepts, which qualities it makes, and how it moves
originals through their states. FFprobe and FFmpeg are faked here. The real
ones run in gate U2, in the worker's image: see docs/step-07d-report.md.

The database tests run on a real local Postgres, as veloraug_media. Skipped
without one: see tests/db_support.py.
"""

import json
import os
import subprocess
import uuid
from pathlib import Path

import psycopg
import pytest

from app.db import Database
from app.media_worker import (
    LADDER,
    Probe,
    Refused,
    Worker,
    WorkerSettings,
    ffmpeg_command,
    ladder,
    last_line,
    parse_probe,
)
from scripts.create_app_role import scram_verifier
from tests.db_support import needs_database, new_item, url_for

MEDIA_PASSWORD = "local-test-media-password"


def probe_json(width=1920, height=1080, audio="aac", duration="7200.5", **video):
    streams = [
        {
            "codec_type": "video",
            "codec_name": "h264",
            "width": width,
            "height": height,
            **video,
        }
    ]
    if audio:
        streams.append({"codec_type": "audio", "codec_name": audio})
    return {"streams": streams, "format": {"duration": duration}}


def names(rungs):
    return [rung.name for rung in rungs]


def size(width, height):
    return Probe(width, height, 60.0, "h264", "aac")


# --- Needs no database -------------------------------------------------------


def test_a_normal_film_is_read():
    assert parse_probe(probe_json()) == Probe(1920, 1080, 7200.5, "h264", "aac")


def test_a_film_without_sound_is_fine():
    assert parse_probe(probe_json(audio=None)).audio_codec is None


def test_tags_that_may_name_the_vj_are_kept_as_hints():
    data = probe_json(tags={"TITLE": "Fast X", "Comment": "Translated by VJ Junior"})
    data["format"]["tags"] = {
        "title": "Fast X  VJ\tJunior\x07",
        "artist": "VJ Junior",
        "encoder": "Lavf60",
    }

    assert parse_probe(data).credit_hints == (
        "title: Fast X VJ Junior\n"
        "artist: VJ Junior\n"
        "title: Fast X\n"
        "comment: Translated by VJ Junior"
    )


def test_a_file_without_tags_has_no_hints_and_long_ones_are_cut():
    assert parse_probe(probe_json()).credit_hints is None
    data = probe_json()
    data["format"]["tags"] = {"description": "x" * 2000}
    assert len(parse_probe(data).credit_hints) == 500


@pytest.mark.parametrize(
    ("data", "reason"),
    [
        ({"streams": [{"codec_type": "audio", "codec_name": "mp3"}]}, "No video track"),
        (
            {
                "streams": [
                    {
                        "codec_type": "video",
                        "codec_name": "mjpeg",
                        "width": 600,
                        "height": 600,
                        "disposition": {"attached_pic": 1},
                    }
                ],
                "format": {"duration": "200"},
            },
            "No video track",
        ),
        (probe_json(426, 240), "The video is 426×240. VeloraUG needs at least 360"),
        (probe_json(duration=None), "length can't be read"),
        (probe_json(0, 0), "size can't be read"),
    ],
)
def test_files_that_cant_become_a_movie_are_refused(data, reason):
    with pytest.raises(Refused) as refusal:
        parse_probe(data)

    assert reason in str(refusal.value)


def test_the_length_can_come_from_the_video_track():
    data = probe_json(duration=None)
    data["streams"][0]["duration"] = "61.2"

    assert parse_probe(data).duration_seconds == 61.2


def test_a_sideways_phone_video_counts_upright():
    data = probe_json(1920, 1080, side_data_list=[{"rotation": -90}])

    assert (parse_probe(data).width, parse_probe(data).height) == (1080, 1920)


@pytest.mark.parametrize(
    ("width", "height", "expected"),
    [
        (3840, 2160, ["360p", "480p", "720p", "1080p"]),
        (1920, 1080, ["360p", "480p", "720p", "1080p"]),
        (1920, 800, ["360p", "480p", "720p", "1080p"]),
        (1280, 720, ["360p", "480p", "720p"]),
        (1280, 544, ["360p", "480p", "720p"]),
        (854, 480, ["360p", "480p"]),
        (640, 360, ["360p"]),
        (480, 360, ["360p"]),
        (1080, 1920, ["360p", "480p", "720p", "1080p"]),
        (426, 240, []),
    ],
)
def test_only_qualities_the_original_can_fill_are_made(width, height, expected):
    assert names(ladder(size(width, height))) == expected


def test_the_original_bitrate_is_read_from_the_video_track_or_the_file():
    assert parse_probe(probe_json(bit_rate="2100000")).video_bps == 2_100_000
    # Matroska keeps it in a tag.
    assert parse_probe(probe_json(tags={"BPS-eng": "1950000"})).video_bps == 1_950_000

    data = probe_json()
    data["format"]["bit_rate"] = "2228000"
    data["streams"][1]["bit_rate"] = "128000"
    assert parse_probe(data).video_bps == 2_100_000

    # The total, less the audio assumed, when the audio's isn't given.
    data = probe_json(duration="100")
    data["format"]["size"] = str(2_628_000 * 100 // 8)
    assert parse_probe(data).video_bps == 2_500_000

    assert parse_probe(probe_json()).video_bps is None


def bitrates(probe: Probe) -> dict[str, int]:
    return {r.name: r.video_bps for r in ladder(probe)}


def test_a_typical_vj_file_gets_three_qualities_sized_from_it():
    # Baby John 2: 1920×800 at about 2.4 Mbit/s of video.
    film = Probe(1920, 800, 4493.0, "h264", "mp3", video_bps=2_400_000)

    # No quality above the original's bitrate, 720p well below 1080p, and no
    # 480p, which would be nearly the size of 360p.
    assert bitrates(film) == {
        "360p": 800_000,
        "720p": 1_440_000,
        "1080p": 2_400_000,
    }
    command = " ".join(ffmpeg_command(Path("/x"), ladder(film), has_audio=True))
    assert "-maxrate:v:2 2400000" in command
    assert "-maxrate:v:0 800000" in command
    assert "split=3" in command


@pytest.mark.parametrize(
    ("probe", "expected"),
    [
        # Rich enough for the full table: nothing changes.
        (
            Probe(1920, 1080, 60.0, "h264", "aac", video_bps=12_000_000),
            {"360p": 800_000, "480p": 1_400_000, "720p": 2_800_000, "1080p": 5_000_000},
        ),
        (
            Probe(1920, 1080, 60.0, "h264", "aac", video_bps=4_000_000),
            {"360p": 800_000, "480p": 1_400_000, "720p": 2_400_000, "1080p": 4_000_000},
        ),
        # A 720p file at 1.5 Mbit/s: 480p would be too close to 360p.
        (
            Probe(1280, 720, 60.0, "h264", "aac", video_bps=1_500_000),
            {"360p": 800_000, "720p": 1_500_000},
        ),
        # Very small originals: one quality, never below the floor.
        (
            Probe(1280, 720, 60.0, "h264", "aac", video_bps=150_000),
            {"720p": 400_000},
        ),
        (
            Probe(1920, 1080, 60.0, "h264", "aac", video_bps=700_000),
            {"360p": 420_000, "1080p": 700_000},
        ),
        (Probe(640, 360, 60.0, "h264", "aac", video_bps=500_000), {"360p": 500_000}),
    ],
)
def test_each_quality_is_sized_from_the_original(probe, expected):
    assert bitrates(probe) == expected
    rates = list(bitrates(probe).values())
    # Lowest first, and each a real step down from the next.
    assert all(low <= high * 0.6 or low == 400_000 for low, high in zip(rates, rates[1:]))


def test_one_command_makes_every_quality_with_shared_keyframes():
    command = ffmpeg_command(Path("/srv/uploads/x"), list(LADDER), has_audio=True)
    text = " ".join(command)

    assert command.count("-map") == 8
    assert command.count("0:a:0") == 4
    assert "split=4[s0][s1][s2][s3]" in text
    assert "scale=w=1920:h=1080:force_original_aspect_ratio=decrease" in text
    assert "expr:gte(t,n_forced*2)" in command
    assert ["-sc_threshold", "0"] == command[
        command.index("-sc_threshold") : command.index("-sc_threshold") + 2
    ]
    assert "libx264" in command and "aac" in command
    assert command[command.index("-var_stream_map") + 1] == (
        "v:0,a:0,name:360p v:1,a:1,name:480p v:2,a:2,name:720p v:3,a:3,name:1080p"
    )
    # Capped quality: CRF, with each quality's bitrate as its ceiling.
    assert command[command.index("-crf") + 1] == "23"
    assert command[command.index("-maxrate:v:3") + 1] == "5000000"
    assert command[command.index("-bufsize:v:3") + 1] == "10000000"
    assert not any(c.startswith("-b:v") for c in command)


def test_a_silent_film_gets_qualities_without_sound():
    command = ffmpeg_command(Path("x"), list(LADDER[:2]), has_audio=False)

    assert "0:a:0" not in command
    assert "-c:a" not in command
    assert command[command.index("-var_stream_map") + 1] == (
        "v:0,name:360p v:1,name:480p"
    )


def test_errors_shown_to_the_owner_hide_the_servers_paths():
    source = Path("/srv/uploads/abc")

    assert last_line("x\n/srv/uploads/abc: Invalid data\n\n", source) == (
        "the upload: Invalid data"
    )
    assert last_line("", source) == "no message"


def test_the_worker_needs_the_media_role():
    with pytest.raises(ValueError):
        WorkerSettings(database_url="postgresql://veloraug_app:pw@db/x")
    settings = WorkerSettings(database_url="postgresql://veloraug_media:pw@db/x")
    assert settings.upload_dir == Path("/srv/uploads")


# --- On a real Postgres, with FFprobe and FFmpeg faked ------------------------


class FakeTools:
    """Answers FFprobe with `probe`, and makes FFmpeg's files unless told to fail."""

    def __init__(self, probe=None, ffmpeg_fails=0):
        self.probe = probe if probe is not None else probe_json()
        self.ffmpeg_fails = ffmpeg_fails
        self.ffmpeg_runs = 0

    def __call__(self, command, **kwargs):
        if command[0] == "ffprobe":
            return subprocess.CompletedProcess(command, 0, json.dumps(self.probe), "")
        self.ffmpeg_runs += 1
        if self.ffmpeg_fails:
            self.ffmpeg_fails -= 1
            return subprocess.CompletedProcess(
                command, 1, "", f"{command[command.index('-i') + 1]}: Broken frame\n"
            )
        out = Path(kwargs["cwd"])
        streams = command[command.index("-var_stream_map") + 1].split()
        for stream in streams:
            name = stream.rsplit("name:", 1)[1]
            (out / name).mkdir()
            (out / name / "index.m3u8").write_text("#EXTM3U\n")
        (out / "master.m3u8").write_text("#EXTM3U\n")
        return subprocess.CompletedProcess(command, 0, "", "")


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
    """Each test starts with nothing else waiting, so it claims its own."""
    with psycopg.connect(owner_url) as conn:
        conn.execute(
            "update public.media_originals set state = 'failed' "
            "where state in ('received', 'checking', 'converting', 'uploading')"
        )


def new_original(owner_url, uploads, state="received", size=1000, age_seconds=0):
    """An original as the hooks would leave it, with its file in uploads."""
    original_id = uuid.uuid4()
    with psycopg.connect(owner_url) as conn:
        movie_id = new_item(conn)
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
              (id, item_id, upload_key_id, size_bytes, state, updated_at)
            values (%s, %s, %s, %s, %s, now() - make_interval(secs => %s))
            """,
            (original_id, movie_id, key_id, size, state, age_seconds),
        )
    (uploads / str(original_id)).write_bytes(b"x" * size)
    return original_id


def row(owner_url, original_id):
    with psycopg.connect(owner_url) as conn:
        return conn.execute(
            """
            select state, width, height, duration_seconds, video_codec, audio_codec,
                   reason
            from public.media_originals where id = %s
            """,
            (original_id,),
        ).fetchone()


@needs_database
def test_a_received_original_is_converted_and_waits_to_publish(
    owner_url, media_database, folders, quiet_queue
):
    uploads, output = folders
    original_id = new_original(owner_url, uploads)
    tools = FakeTools(probe_json(1280, 720, audio="ac3"))
    worker = Worker(media_database, uploads, output, run=tools)

    assert worker.run_once() is True

    state, width, height, duration, video, audio, reason = row(owner_url, original_id)
    assert (state, width, height, float(duration), video, audio, reason) == (
        "publishing",
        1280,
        720,
        7200.5,
        "h264",
        "ac3",
        None,
    )
    made = sorted(p.name for p in (output / str(original_id)).iterdir())
    assert made == ["360p", "480p", "720p", "master.m3u8"]
    assert (uploads / str(original_id)).exists()
    assert worker.run_once() is False


@needs_database
def test_a_refused_file_is_explained_and_deleted(
    owner_url, media_database, folders, quiet_queue
):
    uploads, output = folders
    original_id = new_original(owner_url, uploads)
    (uploads / f"{original_id}.info").write_text("{}")
    tools = FakeTools({"streams": [{"codec_type": "audio", "codec_name": "mp3"}]})

    Worker(media_database, uploads, output, run=tools).run_once()

    assert row(owner_url, original_id)[0] == "refused"
    assert row(owner_url, original_id)[-1] == "No video track found."
    assert not (uploads / str(original_id)).exists()
    assert not (uploads / f"{original_id}.info").exists()
    assert tools.ffmpeg_runs == 0


@needs_database
def test_a_file_ffprobe_cant_read_is_refused(
    owner_url, media_database, folders, quiet_queue
):
    uploads, output = folders
    original_id = new_original(owner_url, uploads)

    def broken(command, **kwargs):
        return subprocess.CompletedProcess(command, 1, "", "Invalid data found")

    Worker(media_database, uploads, output, run=broken).run_once()

    assert row(owner_url, original_id)[0::6] == (
        "refused",
        "The file isn't a video VeloraUG can read.",
    )


@needs_database
def test_conversion_is_tried_three_times_then_fails_with_a_reason(
    owner_url, media_database, folders, quiet_queue
):
    uploads, output = folders
    original_id = new_original(owner_url, uploads)
    tools = FakeTools(ffmpeg_fails=3)

    Worker(media_database, uploads, output, run=tools).run_once()

    state, *_, reason = row(owner_url, original_id)
    assert tools.ffmpeg_runs == 3
    assert state == "failed"
    assert reason == "Converting failed 3 times: the upload: Broken frame"
    assert (uploads / str(original_id)).exists()


@needs_database
def test_a_second_attempt_can_succeed(owner_url, media_database, folders, quiet_queue):
    uploads, output = folders
    original_id = new_original(owner_url, uploads)

    Worker(media_database, uploads, output, run=FakeTools(ffmpeg_fails=1)).run_once()

    assert row(owner_url, original_id)[0] == "publishing"


@needs_database
def test_a_missing_file_fails(owner_url, media_database, folders, quiet_queue):
    uploads, output = folders
    original_id = new_original(owner_url, uploads)
    (uploads / str(original_id)).unlink()

    Worker(media_database, uploads, output, run=FakeTools()).run_once()

    assert row(owner_url, original_id)[0::6] == (
        "failed",
        "The uploaded file is missing.",
    )


@needs_database
def test_interrupted_work_is_put_back(owner_url, media_database, folders, quiet_queue):
    uploads, output = folders
    checking = new_original(owner_url, uploads, state="checking")
    converting = new_original(owner_url, uploads, state="converting")

    assert Worker(media_database, uploads, output).recover() == 2

    assert row(owner_url, checking)[0] == "received"
    assert row(owner_url, converting)[0] == "received"


@needs_database
def test_a_complete_upload_whose_hook_was_missed_is_received(
    owner_url, media_database, folders, quiet_queue
):
    uploads, output = folders
    complete = new_original(owner_url, uploads, "uploading", 500, age_seconds=600)
    partial = new_original(owner_url, uploads, "uploading", 500, age_seconds=600)
    recent = new_original(owner_url, uploads, "uploading", 500, age_seconds=5)
    for original_id, offset in [(complete, 500), (partial, 200), (recent, 500)]:
        (uploads / f"{original_id}.info").write_text(json.dumps({"Offset": offset}))

    found = Worker(media_database, uploads, output).sweep_finished_uploads()

    assert found == 1
    assert [row(owner_url, i)[0] for i in (complete, partial, recent)] == [
        "received",
        "uploading",
        "uploading",
    ]
