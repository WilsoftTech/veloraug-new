"""The media worker: checks each received upload and converts it to HLS.

It takes one 'received' original at a time from Neon, as veloraug_media. It
checks the file with FFprobe, then converts it in one FFmpeg pass to every
quality from 360p to 1080p that the original can fill, never larger. All
qualities are H.264 video and stereo AAC sound, in 6-second fMP4 chunks, with
a keyframe every 2 seconds in every quality, so a player can switch between
them cleanly. See "Conversion" in docs/step-07a-uploads-plan.md.

States: received -> checking -> converting -> publishing -> ready, or
refused or failed. While converting and publishing, it writes how far it has
got, from FFmpeg's own progress and the bytes sent to R2, as a whole
percentage the admin's Drafts tab shows.

With R2 set up, it publishes each converted original, see
app/media_publisher.py, and removes originals marked 'removing'. Without R2, a
converted original waits in 'publishing', with its HLS files in the output
folder, until R2 is set up. It also deletes the rows of editions an admin
deleted, once their files are gone.

Run with:

    python -m app.media_worker
"""

import json
import logging
import math
import os
import re
import shutil
import signal
import subprocess
import threading
import time
import uuid
from collections.abc import Callable
from dataclasses import dataclass, replace
from pathlib import Path

from app.db import Database, DatabaseUnavailable
from app.media_hooks import MediaSettings
from app.media_publisher import Publisher, R2Settings, R2Store
from app.playback import DOWNLOAD_FILE

logger = logging.getLogger("veloraug.media_worker")

ORIGINAL_INPUT = [
    "-protocol_whitelist",
    "file",
    "-format_whitelist",
    "mov,mp4,m4a,3gp,3g2,mj2,matroska,webm,avi,mpegts,mpeg,flv",
]
MAX_CONVERSION_SECONDS = 12 * 60 * 60
MAX_JOIN_SECONDS = 30 * 60
MAX_IDLE_SECONDS = 10 * 60
MIN_FREE_BYTES = 1024**3
MAX_OUTPUT_BYTES = 80 * 1024**3
MAX_LOG_BYTES = 8192
TOOL_ENV = {"PATH": os.defpath, "LANG": "C.UTF-8"}
if os.name == "nt":
    TOOL_ENV["SystemRoot"] = os.environ.get("SystemRoot", r"C:\Windows")


@dataclass(frozen=True)
class Rung:
    """One quality: the box a picture is scaled to fit, and its bitrates."""

    name: str
    width: int
    height: int
    video_bps: int
    audio_bps: int


LADDER = (
    Rung("360p", 640, 360, 800_000, 96_000),
    Rung("480p", 854, 480, 1_400_000, 128_000),
    Rung("720p", 1280, 720, 2_800_000, 128_000),
    Rung("1080p", 1920, 1080, 5_000_000, 128_000),
)
# A quality never gets more video bitrate than the original's: more bits
# can't add detail the original doesn't have, only size in R2 and time to
# publish. Never below this, so a wrongly reported bitrate can't make a film
# unwatchable.
MIN_VIDEO_BPS = 400_000
# Each quality gets at most this share of the bitrate of the one above it,
# so no two qualities are nearly the same size.
STEP = 0.6
# The lowest quality is left out when it would have this share of the top's
# bitrate or more: it would save viewers almost nothing.
NEAR_TOP = 0.8
# An original this close to a quality's size counts as filling it: a VJ file
# cropped to 1916×1076 is still 1080p. Its picture is then scaled up by at
# most 1%, which adds no visible softness.
FILL_TOLERANCE = 0.99
# x264's quality target, under each quality's bitrate cap. 23 is x264's own
# default; lower is better and larger.
CRF = 23
# Audio assumed when a file reports a total bitrate but not its audio's.
ASSUMED_AUDIO_BPS = 128_000
SEGMENT_SECONDS = 6
KEYFRAME_SECONDS = 2
ATTEMPTS = 3
# An upload left in 'uploading' this long, with a complete file, missed its
# post-finish hook.
STALE_UPLOAD_SECONDS = 120
# After a failed publish or removal, wait this long times the failures so far.
RETRY_SECONDS = 60
# Progress is written at most this often, or sooner after this big a step,
# so a long film costs a few hundred small updates, not thousands.
PROGRESS_SECONDS = 5
PROGRESS_STEP = 5


class Refused(Exception):
    """The file can't be made into a movie. The message is shown to the owner."""


class ConversionFailed(Exception):
    """FFmpeg failed. The message is shown to the owner."""


@dataclass(frozen=True)
class Probe:
    width: int
    height: int
    duration_seconds: float
    video_codec: str
    audio_codec: str | None
    # The file's own tags, for suggesting the VJ's credit. Never trusted.
    credit_hints: str | None = None
    # The original's video bitrate, when it can be told. Caps every quality.
    video_bps: int | None = None


# Tags that sometimes name the VJ, in the file or its first video track.
CREDIT_TAGS = ("title", "artist", "album_artist", "comment", "description")
MAX_CREDIT_HINTS = 500


def credit_hints(data: dict) -> str | None:
    """The tags in CREDIT_TAGS, as "tag: value" on one line each, or None.

    Tag names are matched ignoring case. Values are cut to plain text on one
    line, and the whole to MAX_CREDIT_HINTS characters."""
    sources = [data.get("format") or {}]
    sources += [s for s in data.get("streams") or [] if s.get("codec_type") == "video"][
        :1
    ]
    lines: list[str] = []
    for source in sources:
        tags = {str(k).lower(): v for k, v in (source.get("tags") or {}).items()}
        for name in CREDIT_TAGS:
            value = " ".join(str(tags.get(name) or "").split())
            value = "".join(ch for ch in value if ch.isprintable())
            line = f"{name}: {value}"
            if value and line not in lines:
                lines.append(line)
    text = "\n".join(lines)[:MAX_CREDIT_HINTS].strip()
    return text or None


def _bps(value) -> int | None:
    try:
        number = int(float(value))
    except (TypeError, ValueError):
        return None
    return number if number > 0 else None


def _stream_bps(stream: dict | None) -> int | None:
    """A stream's bitrate, from FFprobe, or from the BPS tag Matroska files
    carry instead, such as BPS-eng."""
    if not stream:
        return None
    found = _bps(stream.get("bit_rate"))
    if found:
        return found
    for name, value in (stream.get("tags") or {}).items():
        if str(name).upper().split("-")[0] == "BPS":
            found = _bps(value)
            if found:
                return found
    return None


def source_video_bps(
    data: dict, video: dict, audio: dict | None, duration: float
) -> int | None:
    """The original's video bitrate: the video track's own, or else the
    whole file's less its audio. None when the file says neither."""
    found = _stream_bps(video)
    if found:
        return found
    form = data.get("format") or {}
    total = _bps(form.get("bit_rate"))
    if total is None:
        size = _bps(form.get("size"))
        total = int(size * 8 / duration) if size and duration > 0 else None
    if total is None:
        return None
    if audio is not None:
        total -= _stream_bps(audio) or ASSUMED_AUDIO_BPS
    return total if total > 0 else None


def _rotation(stream: dict) -> int:
    for item in stream.get("side_data_list") or []:
        if "rotation" in item:
            return int(float(item["rotation"]))
    rotate = (stream.get("tags") or {}).get("rotate")
    return int(float(rotate)) if rotate else 0


def parse_probe(data: dict) -> Probe:
    """What FFprobe found, or the reason the file is refused."""
    streams = data.get("streams") or []
    if len(streams) > 32:
        raise Refused("The file has too many tracks.")
    video = next(
        (
            s
            for s in streams
            if s.get("codec_type") == "video"
            and not (s.get("disposition") or {}).get("attached_pic")
        ),
        None,
    )
    if video is None:
        raise Refused("No video track found.")
    width, height = int(video.get("width") or 0), int(video.get("height") or 0)
    if width <= 0 or height <= 0:
        raise Refused("The video's size can't be read.")
    if width * height > 4096 * 2304:
        raise Refused("The video exceeds the supported pixel count.")
    # FFmpeg turns a phone's sideways video upright, so the upright size counts.
    if abs(_rotation(video)) % 180 == 90:
        width, height = height, width
    duration = 0.0
    for source in (data.get("format") or {}, video):
        try:
            duration = float(source.get("duration") or 0)
        except (TypeError, ValueError):
            duration = 0.0
        if duration > 0:
            break
    if duration <= 0:
        raise Refused("The file's length can't be read.")
    if not math.isfinite(duration) or duration > 8 * 3600:
        raise Refused("The video exceeds the supported duration.")
    audio = next((s for s in streams if s.get("codec_type") == "audio"), None)
    probe = Probe(
        width=width,
        height=height,
        duration_seconds=round(duration, 3),
        video_codec=str(video.get("codec_name") or "unknown")[:50],
        audio_codec=str(audio.get("codec_name") or "unknown")[:50] if audio else None,
        credit_hints=credit_hints(data),
        video_bps=source_video_bps(data, video, audio, duration),
    )
    if not ladder(probe):
        raise Refused(
            f"The video is {width}×{height}. VeloraUG needs at least 360 lines, "
            "or 640 pixels across."
        )
    return probe


def ladder(probe: Probe) -> list[Rung]:
    """The qualities made from an original, lowest first.

    Only qualities the original can fill in at least one direction, within
    FILL_TOLERANCE, so a picture is never made more than 1% larger. A wide
    film, 1920×800, gets 1080p, and so does one cropped to 1916×1076.

    When the original's bitrate is known, the ladder is sized from it:
    - the top quality gets at most the original's bitrate;
    - each quality below gets at most STEP of the one above it;
    - a middle quality that would come out too close to the lowest is left
      out, and so is the lowest when it would be almost the top.
    A typical VJ file, 1080p at 2.4 Mbit/s, gets 1080p at 2.4, 720p at 1.44
    and 360p at 0.8: about 2.6 GB for 75 minutes instead of 4.3 GB with
    480p and a 720p as large as 1080p. A rich original keeps the full table."""
    rungs = [
        r
        for r in LADDER
        if probe.width >= r.width * FILL_TOLERANCE
        or probe.height >= r.height * FILL_TOLERANCE
    ]
    if probe.video_bps is None or not rungs:
        return rungs
    cap = max(probe.video_bps, MIN_VIDEO_BPS)
    top, *below = reversed(rungs)
    lowest = rungs[0]
    kept = [replace(top, video_bps=min(top.video_bps, cap))]
    for rung in below:
        bps = max(min(rung.video_bps, int(kept[-1].video_bps * STEP)), MIN_VIDEO_BPS)
        if rung is lowest:
            if bps < kept[0].video_bps * NEAR_TOP:
                kept.append(replace(rung, video_bps=bps))
        elif bps >= lowest.video_bps / STEP:
            kept.append(replace(rung, video_bps=bps))
    return kept[::-1]


def ffmpeg_command(source: Path, rungs: list[Rung], has_audio: bool) -> list[str]:
    """One FFmpeg run making every quality, written to the current folder."""
    count = len(rungs)
    labels = [f"v{i}" for i in range(count)]
    split = f"[0:v:0]split={count}" + "".join(f"[s{i}]" for i in range(count))
    scales = [
        f"[s{i}]scale=w={r.width}:h={r.height}:force_original_aspect_ratio=decrease"
        f":force_divisible_by=2[{labels[i]}]"
        for i, r in enumerate(rungs)
    ]
    command = [
        "ffmpeg",
        "-hide_banner",
        "-nostdin",
        "-y",
        "-v",
        "error",
        # key=value lines on stdout, such as out_time_us=, for progress.
        "-progress",
        "pipe:1",
        "-nostats",
        *ORIGINAL_INPUT,
        "-i",
        str(source),
        "-filter_complex",
        ";".join([split, *scales]),
    ]
    for label in labels:
        command += ["-map", f"[{label}]"]
    if has_audio:
        command += ["-map", "0:a:0"] * count
    command += [
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-profile:v",
        "high",
        "-pix_fmt",
        "yuv420p",
        "-sc_threshold",
        "0",
        "-force_key_frames",
        f"expr:gte(t,n_forced*{KEYFRAME_SECONDS})",
    ]
    # Capped quality: each scene gets the bits it needs for CRF's quality,
    # and never more than the quality's bitrate. Easy scenes cost less. On
    # two clips of a VJ file, 35-42% smaller than a fixed bitrate, with the
    # same SSIM and the same time to convert.
    command += ["-crf", str(CRF)]
    for i, r in enumerate(rungs):
        command += [
            f"-maxrate:v:{i}",
            str(r.video_bps),
            f"-bufsize:v:{i}",
            str(r.video_bps * 2),
        ]
    if has_audio:
        command += ["-c:a", "aac", "-ac", "2"]
        for i, r in enumerate(rungs):
            command += [f"-b:a:{i}", str(r.audio_bps)]
    streams = " ".join(
        f"v:{i}" + (f",a:{i}" if has_audio else "") + f",name:{r.name}"
        for i, r in enumerate(rungs)
    )
    command += [
        "-max_muxing_queue_size",
        "1024",
        "-f",
        "hls",
        "-hls_time",
        str(SEGMENT_SECONDS),
        "-hls_playlist_type",
        "vod",
        "-hls_segment_type",
        "fmp4",
        "-hls_flags",
        "independent_segments",
        "-hls_fmp4_init_filename",
        "init.mp4",
        "-hls_segment_filename",
        "%v/seg_%05d.m4s",
        "-master_pl_name",
        "master.m3u8",
        "-var_stream_map",
        streams,
        "%v/index.m3u8",
    ]
    return command


def download_command(quality: str) -> list[str]:
    """Joins one quality's init file and chunks into <quality>/download.mp4,
    copying the video and sound as they are, with the index at the start so
    it plays before it has fully downloaded. Run from the output folder."""
    return [
        "ffmpeg",
        "-hide_banner",
        "-nostdin",
        "-y",
        "-i",
        f"{quality}/index.m3u8",
        "-map",
        "0",
        "-c",
        "copy",
        "-movflags",
        "+faststart",
        f"{quality}/{DOWNLOAD_FILE}",
    ]


def playlist_seconds(text: str) -> float:
    """How long a quality's playlist says its video is."""
    return sum(float(x) for x in re.findall(r"#EXTINF:([\d.]+)", text))


def measure_seconds(source: str, run=subprocess.run) -> float | None:
    """How long a video file is, by FFprobe, from its index alone: a local
    path, or an address it can read. None if it can't be read."""
    try:
        result = run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "csv=p=0",
                source,
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
        return float((result.stdout or "").strip())
    except (ValueError, OSError, subprocess.TimeoutExpired):
        return None


def length_matches(got: float | None, want: float) -> bool:
    """A joined file as long as its playlist: within 2 s, or 0.5% of it.
    Shorter means chunks were missing when it was joined."""
    return got is not None and abs(got - want) <= max(2.0, want * 0.005)


_OUT_TIME = re.compile(r"^out_time_(?:us|ms)=(\d+)$")


def progress_percent(line: str, duration_seconds: float) -> int | None:
    """The percentage an FFmpeg -progress line shows, or None. Its out_time
    is in microseconds, whether it is called _us or, in old builds, _ms.
    Never 100: that is for when the files are checked."""
    match = _OUT_TIME.match(line.strip())
    if not match or duration_seconds <= 0:
        return None
    done = int(match.group(1)) / 1_000_000 / duration_seconds
    return max(0, min(99, int(done * 100)))


def output_size(folder: Path) -> int:
    total = 0
    for path in folder.rglob("*"):
        if path.is_file():
            try:
                total += path.stat().st_size
            except FileNotFoundError:
                continue
    return total


def stream_process(
    command: list[str], cwd: Path, on_line: Callable[[str], None]
) -> subprocess.CompletedProcess:
    """Forward progress, bound the stderr tail and stop stalled conversions."""
    with subprocess.Popen(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=TOOL_ENV,
        start_new_session=os.name == "posix",
    ) as process:
        assert process.stdout is not None and process.stderr is not None
        tail = bytearray()
        stop = threading.Event()
        failure = []
        last_progress = time.monotonic()
        position = -1

        def drain_errors():
            while chunk := process.stderr.read1(4096):
                tail.extend(chunk)
                del tail[:-MAX_LOG_BYTES]

        def supervise():
            deadline = time.monotonic() + MAX_CONVERSION_SECONDS
            while not stop.wait(1):
                if process.poll() is not None:
                    return
                if time.monotonic() >= deadline:
                    failure.append("Media conversion exceeded its time limit.")
                elif time.monotonic() - last_progress >= MAX_IDLE_SECONDS:
                    failure.append("Media conversion stopped making progress.")
                elif (
                    output_size(cwd) > MAX_OUTPUT_BYTES
                    or shutil.disk_usage(cwd).free < MIN_FREE_BYTES
                ):
                    failure.append("Media conversion exceeded its output limit.")
                if failure:
                    try:
                        if os.name == "posix":
                            os.killpg(process.pid, signal.SIGKILL)
                        else:
                            process.kill()
                    except ProcessLookupError:
                        pass
                    return

        stderr = threading.Thread(target=drain_errors)
        watchdog = threading.Thread(target=supervise)
        stderr.start()
        watchdog.start()
        try:
            while line := process.stdout.readline(4096):
                text = line.decode("utf-8", errors="replace").rstrip("\n")
                if match := re.fullmatch(r"out_time_us=([0-9]{1,18})", text):
                    current = int(match[1])
                    if current > position:
                        position = current
                        last_progress = time.monotonic()
                on_line(text)
        except BaseException:
            process.kill()
            raise
        finally:
            stop.set()
            watchdog.join()
            code = process.wait()
            stderr.join()
        if failure:
            raise ConversionFailed(failure[0])
        return subprocess.CompletedProcess(
            command, code, "", tail.decode("utf-8", errors="replace")
        )


def last_line(text: str, source: Path) -> str:
    """FFmpeg's last error line, without the server's paths."""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    line = lines[-1] if lines else "no message"
    for path in {str(source), source.as_posix()}:
        line = line.replace(path, "the upload")
    return line[:300]


class Worker:
    def __init__(
        self,
        database: Database,
        upload_dir: Path,
        output_dir: Path,
        run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
        clock: Callable[[], float] = time.monotonic,
        publisher: Publisher | None = None,
        stream: Callable[..., subprocess.CompletedProcess] | None = None,
    ) -> None:
        self.database = database
        self.upload_dir = upload_dir
        self.output_dir = output_dir
        self.run = run
        self.clock = clock
        self.publisher = publisher
        # FFmpeg's conversion, read line by line for its progress. A `run`
        # given in tests answers it too, with its stdout read afterwards.
        if stream is None:
            stream = stream_process if run is subprocess.run else self._run_then_read
        self.stream = stream
        # The last progress written: original ID -> (percent, when).
        self._progress: dict[uuid.UUID, tuple[int, float]] = {}
        # Failed publishes and removals: original ID -> (failures, next try).
        self.retries: dict[uuid.UUID, tuple[int, float]] = {}

    # --- The queue, in Neon -------------------------------------------------

    def recover(self) -> int:
        """Puts back originals a stopped worker was in the middle of. One
        worker runs at a time, so anything 'checking' or 'converting' at
        start-up was interrupted."""
        with self.database.anonymous() as conn:
            return conn.execute(
                """
                update public.media_originals
                set state = 'received', updated_at = now()
                where state in ('checking', 'converting')
                """
            ).rowcount

    def sweep_finished_uploads(self) -> int:
        """Receives uploads whose file is complete but whose post-finish hook
        was missed, such as when the database was briefly unreachable."""
        with self.database.anonymous() as conn:
            waiting = conn.execute(
                """
                select id, size_bytes from public.media_originals
                where state = 'uploading'
                  and updated_at < now() - make_interval(secs => %s)
                """,
                (STALE_UPLOAD_SECONDS,),
            ).fetchall()
        found = 0
        for original_id, size in waiting:
            info = self.upload_dir / f"{original_id}.info"
            try:
                offset = json.loads(info.read_text(encoding="utf-8")).get("Offset")
            except (OSError, ValueError):
                continue
            if offset == size:
                with self.database.anonymous() as conn:
                    found += conn.execute(
                        """
                        update public.media_originals
                        set state = 'received', updated_at = now()
                        where id = %s and state = 'uploading'
                        """,
                        (original_id,),
                    ).rowcount
        return found

    def claim(self) -> uuid.UUID | None:
        with self.database.anonymous() as conn:
            row = conn.execute(
                """
                update public.media_originals set state = 'checking', updated_at = now()
                where id = (
                  select id from public.media_originals
                  where state = 'received'
                  order by created_at
                  for update skip locked
                  limit 1
                )
                returning id
                """
            ).fetchone()
        return row[0] if row else None

    def _set(self, original_id: uuid.UUID, state: str, **fields) -> None:
        """Moves an original to a new state. Its progress starts again at 0
        in a stage that reports it, and is cleared in any other."""
        fields["progress"] = 0 if state in ("converting", "publishing") else None
        self._progress.pop(original_id, None)
        columns = ", ".join(f"{name} = %({name})s" for name in fields)
        with self.database.anonymous() as conn:
            conn.execute(
                "update public.media_originals set state = %(state)s, "
                f"updated_at = now(), progress_at = now(), {columns} "
                "where id = %(id)s",
                {"id": original_id, "state": state, **fields},
            )

    def report(self, original_id: uuid.UUID, percent: int) -> None:
        """Writes how far converting or publishing has got, now and then.
        A failure to write it never stops the work."""
        now = self.clock()
        # The first call sets the baseline, so small steps are still written
        # every few seconds before the first big one.
        last, at = self._progress.setdefault(original_id, (0, now))
        if percent <= last or (
            percent - last < PROGRESS_STEP and now - at < PROGRESS_SECONDS
        ):
            return
        self._progress[original_id] = (percent, now)
        try:
            with self.database.anonymous() as conn:
                conn.execute(
                    """
                    update public.media_originals
                    set progress = %s, progress_at = now()
                    where id = %s and state in ('converting', 'publishing')
                    """,
                    (percent, original_id),
                )
        except Exception as error:  # The database, briefly away.
            logger.warning("progress of %s not saved: %s", original_id, error)

    def _run_then_read(
        self, command: list[str], cwd: Path, on_line: Callable[[str], None]
    ) -> subprocess.CompletedProcess:
        result = self.run(command, cwd=cwd, capture_output=True, text=True)
        for line in (result.stdout or "").splitlines():
            on_line(line)
        return result

    def purge_deleted(self) -> int:
        """Deletes the rows of editions an admin deleted, once their files
        are gone. See migration 0015."""
        with self.database.anonymous() as conn:
            return conn.execute("select public.purge_deleted_editions()").fetchone()[0]

    # --- One original -------------------------------------------------------

    def probe(self, source: Path) -> Probe:
        result = self.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-print_format",
                "json",
                "-show_format",
                "-show_streams",
                *ORIGINAL_INPUT,
                str(source),
            ],
            capture_output=True,
            text=True,
            timeout=300,
            env=TOOL_ENV,
        )
        try:
            data = json.loads(result.stdout or "{}")
        except ValueError:
            data = {}
        if result.returncode != 0 or not data.get("streams"):
            raise Refused("The file isn't a video VeloraUG can read.")
        return parse_probe(data)

    def convert(
        self,
        source: Path,
        out: Path,
        rungs: list[Rung],
        audio: bool,
        on_progress: Callable[[int], None] | None = None,
        duration_seconds: float = 0,
    ) -> None:
        error = "no message"

        def read(line: str) -> None:
            percent = progress_percent(line, duration_seconds)
            if percent is not None and on_progress is not None:
                on_progress(percent)

        for attempt in range(1, ATTEMPTS + 1):
            shutil.rmtree(out, ignore_errors=True)
            out.mkdir(parents=True)
            result = self.stream(ffmpeg_command(source, rungs, audio), out, read)
            missing = [
                r.name for r in rungs if not (out / r.name / "index.m3u8").exists()
            ]
            if (
                result.returncode == 0
                and not missing
                and (out / "master.m3u8").exists()
            ):
                problem = self.make_download_files(out, rungs)
                if problem is None:
                    return
                error = problem
                logger.warning("conversion attempt %s failed: %s", attempt, error)
                continue
            error = last_line(result.stderr or "", source)
            if result.returncode == 0:
                error = f"No playlist for {', '.join(missing) or 'the master'}"
            logger.warning("conversion attempt %s failed: %s", attempt, error)
        raise ConversionFailed(f"Converting failed {ATTEMPTS} times: {error}")

    def make_download_files(self, out: Path, rungs: list[Rung]) -> str | None:
        """Each quality's chunks joined into one .mp4 that viewers download
        and keep. Copied, not converted again, so it takes seconds. Answers
        what went wrong, or None."""
        for rung in rungs:
            remaining = min(
                MAX_OUTPUT_BYTES - output_size(out),
                shutil.disk_usage(out).free - MIN_FREE_BYTES,
            )
            if remaining <= 0:
                return "The conversion exceeded the available output space."
            command = download_command(rung.name)
            command[-1:-1] = ["-fs", str(remaining)]
            result = self.run(
                command,
                cwd=out,
                capture_output=True,
                text=True,
                timeout=MAX_JOIN_SECONDS,
                env=TOOL_ENV,
            )
            made = out / rung.name / DOWNLOAD_FILE
            if result.returncode != 0 or not made.exists():
                line = (result.stderr or "").strip().splitlines()
                return f"Joining {rung.name} for download failed: " + (
                    line[-1] if line else "no message"
                )
            want = playlist_seconds((out / rung.name / "index.m3u8").read_text())
            got = measure_seconds(str(made), self.run)
            if not length_matches(got, want):
                return (
                    f"Joining {rung.name} for download made "
                    f"{got or 0:.0f} s of {want:.0f} s"
                )
        return None

    def process(self, original_id: uuid.UUID) -> str:
        """Takes one claimed original as far as it can go. Returns its state."""
        source = self.upload_dir / str(original_id)
        if not source.is_file():
            self._set(original_id, "failed", reason="The uploaded file is missing.")
            return "failed"
        try:
            probe = self.probe(source)
        except (
            Refused,
            ConversionFailed,
            subprocess.TimeoutExpired,
            OSError,
        ) as refusal:
            reason = (
                str(refusal)
                if isinstance(refusal, Refused)
                else "Could not probe the media."
            )
            self._set(original_id, "refused", reason=reason)
            # Nothing can come of a refused file, so it isn't kept.
            source.unlink(missing_ok=True)
            source.with_name(source.name + ".info").unlink(missing_ok=True)
            logger.info("original %s refused: %s", original_id, reason)
            return "refused"

        rungs = ladder(probe)
        self._set(
            original_id,
            "converting",
            width=probe.width,
            height=probe.height,
            duration_seconds=probe.duration_seconds,
            video_codec=probe.video_codec,
            audio_codec=probe.audio_codec,
            credit_hints=probe.credit_hints,
            reason=None,
        )
        logger.info(
            "original %s: %s×%s %s/%s, %.0f s, %s, making %s",
            original_id,
            probe.width,
            probe.height,
            probe.video_codec,
            probe.audio_codec or "no sound",
            probe.duration_seconds,
            f"{probe.video_bps / 1e6:.1f} Mbit/s"
            if probe.video_bps
            else "bitrate unknown",
            ", ".join(r.name for r in rungs),
        )
        started = self.clock()
        try:
            self.convert(
                source,
                self.output_dir / str(original_id),
                rungs,
                bool(probe.audio_codec),
                on_progress=lambda percent: self.report(original_id, percent),
                duration_seconds=float(probe.duration_seconds),
            )
        except (ConversionFailed, OSError, subprocess.TimeoutExpired) as failure:
            shutil.rmtree(self.output_dir / str(original_id), ignore_errors=True)
            reason = (
                str(failure)
                if isinstance(failure, ConversionFailed)
                else "Media conversion timed out."
            )
            self._set(original_id, "failed", reason=reason)
            logger.error("original %s failed: %s", original_id, reason)
            return "failed"
        elapsed = self.clock() - started
        self._set(original_id, "publishing")
        logger.info(
            "original %s converted in %.0f s, %.2f s per second of film",
            original_id,
            elapsed,
            elapsed / probe.duration_seconds,
        )
        if self.publisher is None:
            return "publishing"
        return "ready" if self.try_publish(original_id) else "publishing"

    # --- Publishing and removing, from Step 7E -----------------------------

    def _due(self, state: str) -> uuid.UUID | None:
        """The oldest original in this state that isn't waiting to retry."""
        with self.database.anonymous() as conn:
            ids = [
                row[0]
                for row in conn.execute(
                    """
                    select id from public.media_originals
                    where state = %s order by updated_at limit 50
                    """,
                    (state,),
                )
            ]
        now = self.clock()
        return next((i for i in ids if self.retries.get(i, (0, 0))[1] <= now), None)

    def _attempt(self, original_id: uuid.UUID, action, what: str) -> bool:
        """Runs a publish or removal. A failure is tried again later, after
        a growing wait. Publishing that fails 3 times is marked 'failed'."""
        try:
            action(original_id)
        except DatabaseUnavailable:
            raise
        except Exception as error:  # boto3, the network or the files
            failures = self.retries.get(original_id, (0, 0))[0] + 1
            message = f"{type(error).__name__}: {str(error)[:200]}"
            logger.warning(
                "%s %s failed (%s): %s", what, original_id, failures, message
            )
            if what == "publishing" and failures >= ATTEMPTS:
                self.retries.pop(original_id, None)
                self._set(
                    original_id,
                    "failed",
                    reason=f"Publishing to R2 failed {ATTEMPTS} times: {message}",
                )
                return False
            self.retries[original_id] = (
                failures,
                self.clock() + RETRY_SECONDS * failures,
            )
            return False
        self.retries.pop(original_id, None)
        return True

    def try_publish(self, original_id: uuid.UUID) -> bool:
        def publish(original: uuid.UUID) -> None:
            self.publisher.publish(
                original, on_progress=lambda percent: self.report(original, percent)
            )

        return self._attempt(original_id, publish, "publishing")

    def run_once(self) -> bool:
        """Does one piece of work. False when there was nothing to do."""
        self.sweep_finished_uploads()
        # Before claiming, so a deleted draft's upload is never converted.
        self.purge_deleted()
        original_id = self.claim()
        if original_id is not None:
            self.process(original_id)
            return True
        if self.publisher is None:
            return False
        original_id = self._due("publishing")
        if original_id is not None:
            self.try_publish(original_id)
            return True
        original_id = self._due("removing")
        if original_id is not None:
            if self._attempt(original_id, self.publisher.remove, "removing"):
                self.purge_deleted()
            return True
        return False

    def run_forever(self, poll_seconds: float = 10) -> None:
        recovered = self.recover()
        if recovered:
            logger.info("put back %s interrupted original(s)", recovered)
        while True:
            try:
                if not self.run_once():
                    time.sleep(poll_seconds)
            except DatabaseUnavailable as error:
                logger.warning("database unavailable (%s); waiting", error)
                time.sleep(poll_seconds * 3)


class WorkerSettings(MediaSettings):
    """VELORAUG_MEDIA_* environment variables, as for the hooks, plus where
    uploads arrive and where converted files go."""

    upload_dir: Path = Path("/srv/uploads")
    output_dir: Path = Path("/srv/output")
    poll_seconds: float = 10


def main() -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(levelname)s:     %(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    settings = WorkerSettings()
    r2 = R2Settings()
    database = Database(settings.database_url.get_secret_value(), max_size=2)
    database.open()
    publisher = None
    if r2.configured:
        store = R2Store(r2)
        publisher = Publisher(database, store, settings.upload_dir, settings.output_dir)
        logger.info("media worker started, publishing to R2 bucket %s", r2.bucket)
    else:
        logger.info(
            "media worker started. R2 isn't set up, so converted originals wait "
            "in 'publishing'"
        )
    try:
        from app import media_converter

        Worker(
            database,
            settings.upload_dir,
            settings.output_dir,
            publisher=publisher,
            run=media_converter.run,
            stream=media_converter.stream,
        ).run_forever(settings.poll_seconds)
    finally:
        database.close()


if __name__ == "__main__":
    main()
