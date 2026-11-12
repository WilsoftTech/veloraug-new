"""Gate U2: checks conversion with the real FFprobe and FFmpeg.

Runs inside the media worker's image, on clips FFmpeg generates itself, using
the worker's own probe, ladder and convert. Each clip must get exactly the
qualities its size allows, with every chunk of every quality starting on a
keyframe at the same moment, and each quality must play to the end as H.264
with AAC sound. Files that can't become a movie must be refused. It prints
how long converting takes per second of film.

From services/api, with Docker running, and an empty folder for its files:

    docker run --rm --user root -v "<empty folder>:/gate"
      -v "${PWD}/scripts:/checks" --entrypoint python
      veloraug-media-worker:local /checks/check_conversion.py

(one line in PowerShell). It writes frame_360p.png and frame_1080p.png, the
same moment at both sizes, into the folder, to look at by eye.

See docs/step-07d-report.md.
"""

import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, "/srv/api")
from app.media_worker import Refused, Worker, ladder  # noqa: E402

WORK = Path(sys.argv[1] if len(sys.argv) > 1 else "/gate")
CLIPS = WORK / "clips"
OUT = WORK / "out"
CLIPS.mkdir(exist_ok=True)
OUT.mkdir(exist_ok=True)


def run(*args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, check=True, **kwargs)


def make(name, size, seconds, vcodec, acodec, container="mp4"):
    path = CLIPS / f"{name}.{container}"
    if path.exists():
        return path
    command = [
        "ffmpeg",
        "-v",
        "error",
        "-y",
        "-f",
        "lavfi",
        "-i",
        f"testsrc2=size={size}:rate=24:duration={seconds}",
    ]
    if acodec:
        command += ["-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}"]
    command += {
        "h264": ["-c:v", "libx264", "-preset", "ultrafast", "-g", "240"],
        "hevc": [
            "-c:v",
            "libx265",
            "-preset",
            "ultrafast",
            "-x265-params",
            "log-level=error",
        ],
        "vp9": ["-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "8"],
    }[vcodec]
    if acodec:
        command += ["-c:a", acodec, "-shortest"]
    run(*command, str(path))
    return path


def make_odd(name, data_args):
    path = CLIPS / name
    if not path.exists():
        run("ffmpeg", "-v", "error", "-y", *data_args, str(path))
    return path


CASES = [
    # name, file, expected qualities or refusal text
    (
        "1080p H.264 + AAC, 60 s",
        lambda: make("h264_1080", "1920x1080", 60, "h264", "aac"),
        ["360p", "480p", "720p", "1080p"],
    ),
    (
        "2160p HEVC + AC-3",
        lambda: make("hevc_2160", "3840x2160", 12, "hevc", "ac3"),
        ["360p", "480p", "720p", "1080p"],
    ),
    (
        "720p VP9, no sound (WebM)",
        lambda: make("vp9_720", "1280x720", 12, "vp9", None, "webm"),
        ["360p", "480p", "720p"],
    ),
    (
        "Wide 1920×800 H.264 + AAC",
        lambda: make("wide", "1920x800", 12, "h264", "aac"),
        ["360p", "480p", "720p", "1080p"],
    ),
    (
        "360p H.264 + AAC",
        lambda: make("h264_360", "640x360", 12, "h264", "aac"),
        ["360p"],
    ),
    (
        "240p H.264",
        lambda: make("h264_240", "426x240", 6, "h264", "aac"),
        "needs at least 360",
    ),
    (
        "Sound only",
        lambda: make_odd(
            "sound.m4a", ["-f", "lavfi", "-i", "sine=duration=5", "-c:a", "aac"]
        ),
        "No video track",
    ),
]

junk = CLIPS / "junk.mp4"
junk.write_bytes(bytes(range(256)) * 4096)
CASES.append(("Random bytes", lambda: junk, "isn't a video"))

worker = Worker(None, CLIPS, OUT)


def keyframe_times(playlist):
    out = run(
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-skip_frame",
        "nokey",
        "-show_entries",
        "frame=pts_time",
        "-of",
        "csv=p=0",
        str(playlist),
    ).stdout
    return [round(float(x.strip(",")), 3) for x in out.split() if x.strip(",")]


def extinfs(playlist):
    return [
        line for line in playlist.read_text().splitlines() if line.startswith("#EXTINF")
    ]


def stream_info(playlist):
    data = json.loads(
        run(
            "ffprobe",
            "-v",
            "error",
            "-show_streams",
            "-show_format",
            "-print_format",
            "json",
            str(playlist),
        ).stdout
    )
    video = next(s for s in data["streams"] if s["codec_type"] == "video")
    audio = [s["codec_name"] for s in data["streams"] if s["codec_type"] == "audio"]
    return (
        video["width"],
        video["height"],
        video["codec_name"],
        audio,
        float(data["format"]["duration"]),
    )


all_passed = True
for title, make_clip, expected in CASES:
    source = make_clip()
    try:
        probe = worker.probe(source)
    except Refused as refusal:
        ok = isinstance(expected, str) and expected in str(refusal)
        all_passed &= ok
        print(f'{"PASS" if ok else "FAIL"}  {title}: refused, "{refusal}"')
        continue
    if isinstance(expected, str):
        all_passed = False
        print(f"FAIL  {title}: accepted, expected a refusal")
        continue
    rungs = ladder(probe)
    out = OUT / source.stem
    started = time.monotonic()
    worker.convert(source, out, rungs, bool(probe.audio_codec))
    elapsed = time.monotonic() - started
    made = sorted(
        (p.name for p in out.iterdir() if p.is_dir()), key=lambda n: int(n[:-1])
    )
    problems = []
    if made != expected:
        problems.append(f"made {made}")
    master = (out / "master.m3u8").read_text()
    if not all(f"{name}/index.m3u8" in master for name in expected):
        problems.append("master playlist incomplete")
    segment_lists = {name: extinfs(out / name / "index.m3u8") for name in made}
    if len({tuple(v) for v in segment_lists.values()}) != 1:
        problems.append("chunk lengths differ between qualities")
    keys = {name: keyframe_times(out / name / "index.m3u8") for name in made}
    if len({tuple(v) for v in keys.values()}) != 1:
        problems.append("keyframes differ between qualities")
    for name in made:
        init = next((out / name).glob("init*.mp4"))
        for segment in sorted((out / name).glob("seg_*.m4s")):
            joined = WORK / "joined.mp4"
            joined.write_bytes(init.read_bytes() + segment.read_bytes())
            first = run(
                "ffprobe",
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-show_entries",
                "frame=key_frame",
                "-of",
                "csv=p=0",
                "-read_intervals",
                "%+#1",
                str(joined),
            ).stdout.split()
            if not first or first[0].strip(",") != "1":
                problems.append(f"{name}/{segment.name} doesn't start on a keyframe")
    sizes = []
    for name in made:
        playlist = out / name / "index.m3u8"
        decode = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(playlist), "-f", "null", "-"],
            capture_output=True,
            text=True,
        )
        if decode.returncode != 0 or decode.stderr.strip():
            problems.append(
                f"{name} doesn't play cleanly: {decode.stderr.strip()[:120]}"
            )
        width, height, codec, audio, duration = stream_info(playlist)
        if codec != "h264" or (audio != (["aac"] if probe.audio_codec else [])):
            problems.append(f"{name} is {codec}/{audio}")
        if abs(duration - probe.duration_seconds) > 0.5:
            problems.append(f"{name} lasts {duration:.1f} s")
        size_mb = sum(f.stat().st_size for f in (out / name).iterdir()) / 1e6
        sizes.append(f"{name} {width}×{height} {size_mb:.1f} MB")
    ok = not problems
    all_passed &= ok
    chunks = len(segment_lists[made[0]])
    per_second = elapsed / probe.duration_seconds
    print(
        f"{'PASS' if ok else 'FAIL'}  {title} ({probe.width}×{probe.height} "
        f"{probe.video_codec}/{probe.audio_codec or 'none'}): {chunks} chunks; "
        f"{'; '.join(sizes)}; converted in {elapsed:.1f} s = {per_second:.2f} s "
        "per s of film"
    )
    for problem in problems:
        print(f"      {problem}")

# Frames for looking at by eye. -ss after -i decodes from the start: FFmpeg's
# own HLS reader can't jump into the middle of fMP4 chunks, though players can.
for name in ("360p", "1080p"):
    run(
        "ffmpeg",
        "-v",
        "error",
        "-y",
        "-i",
        str(OUT / "h264_1080" / name / "index.m3u8"),
        "-ss",
        "20",
        "-frames:v",
        "1",
        "-update",
        "1",
        str(WORK / f"frame_{name}.png"),
    )
print("\nGATE U2:", "PASSED" if all_passed else "FAILED")
sys.exit(0 if all_passed else 1)
