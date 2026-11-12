"""The media worker: checks each received upload and converts it to HLS.

It takes one 'received' original at a time from Neon, as veloraug_media. It
checks the file with FFprobe, then converts it in one FFmpeg pass to every
quality from 360p to 1080p that the original can fill, never larger. All
qualities are H.264 video and stereo AAC sound, in 6-second fMP4 chunks, with
a keyframe every 2 seconds in every quality, so a player can switch between
them cleanly. See "Conversion" in docs/step-07a-uploads-plan.md.

States: received -> checking -> converting -> publishing, or refused or
failed. Publishing to R2 comes in Step 7E; until then a converted original
waits in 'publishing', with its HLS files in the output folder.

Run with:

    python -m app.media_worker
"""

import json
import logging
import shutil
import subprocess
import time
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from app.db import Database, DatabaseUnavailable
from app.media_hooks import MediaSettings

logger = logging.getLogger("veloraug.media_worker")


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
SEGMENT_SECONDS = 6
KEYFRAME_SECONDS = 2
ATTEMPTS = 3
# An upload left in 'uploading' this long, with a complete file, missed its
# post-finish hook.
STALE_UPLOAD_SECONDS = 120


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


def _rotation(stream: dict) -> int:
    for item in stream.get("side_data_list") or []:
        if "rotation" in item:
            return int(float(item["rotation"]))
    rotate = (stream.get("tags") or {}).get("rotate")
    return int(float(rotate)) if rotate else 0


def parse_probe(data: dict) -> Probe:
    """What FFprobe found, or the reason the file is refused."""
    streams = data.get("streams") or []
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
    audio = next((s for s in streams if s.get("codec_type") == "audio"), None)
    probe = Probe(
        width=width,
        height=height,
        duration_seconds=round(duration, 3),
        video_codec=str(video.get("codec_name") or "unknown")[:50],
        audio_codec=str(audio.get("codec_name") or "unknown")[:50] if audio else None,
    )
    if not ladder(probe):
        raise Refused(
            f"The video is {width}×{height}. VeloraUG needs at least 360 lines, "
            "or 640 pixels across."
        )
    return probe


def ladder(probe: Probe) -> list[Rung]:
    """Every quality the original can fill in at least one direction, so a
    picture is only ever made smaller. A wide film, 1920×800, gets 1080p."""
    return [r for r in LADDER if probe.width >= r.width or probe.height >= r.height]


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
    for i, r in enumerate(rungs):
        command += [
            f"-b:v:{i}",
            str(r.video_bps),
            f"-maxrate:v:{i}",
            str(int(r.video_bps * 1.07)),
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
    ) -> None:
        self.database = database
        self.upload_dir = upload_dir
        self.output_dir = output_dir
        self.run = run
        self.clock = clock

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
        columns = ", ".join(f"{name} = %({name})s" for name in fields)
        with self.database.anonymous() as conn:
            conn.execute(
                "update public.media_originals set state = %(state)s, "
                f"updated_at = now(){', ' + columns if columns else ''} "
                "where id = %(id)s",
                {"id": original_id, "state": state, **fields},
            )

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
                str(source),
            ],
            capture_output=True,
            text=True,
            timeout=300,
        )
        try:
            data = json.loads(result.stdout or "{}")
        except ValueError:
            data = {}
        if result.returncode != 0 or not data.get("streams"):
            raise Refused("The file isn't a video VeloraUG can read.")
        return parse_probe(data)

    def convert(self, source: Path, out: Path, rungs: list[Rung], audio: bool) -> None:
        error = "no message"
        for attempt in range(1, ATTEMPTS + 1):
            shutil.rmtree(out, ignore_errors=True)
            out.mkdir(parents=True)
            result = self.run(
                ffmpeg_command(source, rungs, audio),
                cwd=out,
                capture_output=True,
                text=True,
            )
            missing = [
                r.name for r in rungs if not (out / r.name / "index.m3u8").exists()
            ]
            if (
                result.returncode == 0
                and not missing
                and (out / "master.m3u8").exists()
            ):
                return
            error = last_line(result.stderr or "", source)
            if result.returncode == 0:
                error = f"No playlist for {', '.join(missing) or 'the master'}"
            logger.warning("conversion attempt %s failed: %s", attempt, error)
        raise ConversionFailed(f"Converting failed {ATTEMPTS} times: {error}")

    def process(self, original_id: uuid.UUID) -> str:
        """Takes one claimed original as far as it can go. Returns its state."""
        source = self.upload_dir / str(original_id)
        if not source.is_file():
            self._set(original_id, "failed", reason="The uploaded file is missing.")
            return "failed"
        try:
            probe = self.probe(source)
        except Refused as refusal:
            self._set(original_id, "refused", reason=str(refusal))
            # Nothing can come of a refused file, so it isn't kept.
            source.unlink(missing_ok=True)
            source.with_name(source.name + ".info").unlink(missing_ok=True)
            logger.info("original %s refused: %s", original_id, refusal)
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
            reason=None,
        )
        logger.info(
            "original %s: %s×%s %s/%s, %.0f s, making %s",
            original_id,
            probe.width,
            probe.height,
            probe.video_codec,
            probe.audio_codec or "no sound",
            probe.duration_seconds,
            ", ".join(r.name for r in rungs),
        )
        started = self.clock()
        try:
            self.convert(
                source,
                self.output_dir / str(original_id),
                rungs,
                bool(probe.audio_codec),
            )
        except ConversionFailed as failure:
            self._set(original_id, "failed", reason=str(failure))
            logger.error("original %s failed: %s", original_id, failure)
            return "failed"
        elapsed = self.clock() - started
        # Waits here for Step 7E to publish it to R2.
        self._set(original_id, "publishing")
        logger.info(
            "original %s converted in %.0f s, %.2f s per second of film",
            original_id,
            elapsed,
            elapsed / probe.duration_seconds,
        )
        return "publishing"

    def run_once(self) -> bool:
        """Does one piece of work. False when there was nothing to do."""
        self.sweep_finished_uploads()
        original_id = self.claim()
        if original_id is None:
            return False
        self.process(original_id)
        return True

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
    database = Database(settings.database_url.get_secret_value(), max_size=2)
    database.open()
    logger.info("media worker started")
    try:
        Worker(database, settings.upload_dir, settings.output_dir).run_forever(
            settings.poll_seconds
        )
    finally:
        database.close()


if __name__ == "__main__":
    main()
