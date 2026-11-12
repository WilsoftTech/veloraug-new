# Step 7D report: conversion

Date: 12 November 2026. Branch: `feature/step-07-uploads`. This follows the [uploads plan](step-07a-uploads-plan.md#4-conversion).

**Step 7D is complete.** Gate U2 passed with the real FFmpeg. Against the Neon development branch, the worker refused the 8 MB test file from Step 7C, and on 12 November 2026 converted the owner's upload of the 1080p test clip to all four qualities, in 52 seconds, before publishing it. That run was done as part of Step 7E: see the [Step 7E report](step-07e-report.md#results-12-november-2026).

## What changed

| Item | Where |
| --- | --- |
| The media worker: takes one `received` original at a time, checks it with FFprobe, and converts it in one FFmpeg run to every quality from 360p to 1080p it can fill. Puts back interrupted work, and receives uploads whose finish hook was missed | [`services/api/app/media_worker.py`](../services/api/app/media_worker.py) |
| The worker's image: the API's code plus FFmpeg 7.1.5 from Debian | [`services/api/Dockerfile.worker`](../services/api/Dockerfile.worker) |
| The worker in the local Compose file, behind the `uploads` profile, with no ports | [`infra/compose.local.yaml`](../infra/compose.local.yaml) |
| Gate U2, kept to run again, such as on the Oracle server | [`scripts/check_conversion.py`](../services/api/scripts/check_conversion.py) |
| Docs | [API README, Convert uploads](../services/api/README.md#convert-uploads) |

**How conversion works:**
- One FFmpeg run splits the picture, scales each copy to fit its quality's box without changing its shape, and encodes each with libx264, `veryfast`, at the plan's bitrates.
- A keyframe is forced every 2 seconds, with scene-cut keyframes off, so every quality has keyframes at the same moments.
- The output is HLS with fMP4 chunks of 6 seconds and a master playlist, one folder per quality.
- **Which qualities are made:** a quality is made if the original is at least as wide or as tall as it, so a picture is only ever made smaller. A wide film, 1920×800, gets 1080p at 1920×800.
- **Sideways phone videos** count by their upright size.

**Three changes from the plan:**

- **Retries happen in one go.** A failing conversion is tried 3 times straight away, rather than being retried later. The database has no attempt counter, and adding one wasn't needed.
- **One worker at a time.** On start-up, the worker puts back anything left `checking` or `converting`, as if it had been interrupted. Running two workers needs leases, later.
- **Refused files are deleted.** Nothing can come of them, and the reason stays in the database.

## Gate U2: conversion

**Passed** on 12 November 2026, inside the worker's image, with 4 CPUs for Docker. FFmpeg made each test clip itself:

| Clip | Result | Qualities, size |
| --- | --- | --- |
| 1920×1080 H.264 + AAC, 60 s | **Pass**: 10 chunks | 360p 6.7 MB, 480p 11.2 MB, 720p 21.7 MB, 1080p 38.3 MB |
| 3840×2160 HEVC + AC-3, 12 s | **Pass** | 360p, 480p, 720p, 1080p at 1920×1080 |
| 1280×720 VP9, no sound, WebM, 12 s | **Pass**: no sound in any quality | 360p, 480p, 720p |
| 1920×800 H.264 + AAC, 12 s | **Pass** | 640×266, 854×356, 1280×534, 1920×800 |
| 640×360 H.264 + AAC, 12 s | **Pass** | 360p only |
| 426×240 H.264 | **Refused**: "The video is 426×240. VeloraUG needs at least 360 lines, or 640 pixels across." | |
| Sound only | **Refused**: "No video track found." | |
| Random bytes | **Refused**: "The file isn't a video VeloraUG can read." | |

For every converted clip:
- every quality has the same chunk lengths and the same keyframe times;
- every chunk of every quality starts on a keyframe: 64 chunks were checked one by one, each joined to its init file;
- every quality plays to the end with no errors, as H.264 with AAC sound, or without sound for the silent clip, and lasts as long as the original.

**Looked at by eye:** the 360p and 1080p frames at 20 seconds show the same moment, clean and correctly scaled. The test pattern can't judge a real film's picture, so the bitrates stay as drafted until the owner watches a real one at Step 7F.

**One finding:** FFmpeg's own HLS reader prints "Invalid NAL unit size" when asked to jump into the middle of these fMP4 chunks, though it plays them from the start without errors. Every chunk decodes cleanly with its init file, the way players load them, so the files are sound. **Seeking in real players, hls.js on the web and ExoPlayer on Android, is to be tested in Milestone 8.**

### Time and size

| Original | Time to convert, per second of film | A 2-hour film |
| --- | --- | --- |
| 1080p H.264 | 0.66 to 0.74 s | about 80 to 90 minutes |
| 2160p HEVC | 1.0 to 1.5 s | about 2 to 3 hours |
| 720p VP9 | 0.3 s | about 35 minutes |

These were measured on this PC, with 4 CPUs for Docker, on generated test patterns. Real films take longer or shorter depending on their picture. The Oracle server has 4 ARM cores, and Milestone 10 measures it there.

**Size:** the four qualities of the 60-second 1080p clip took 77.9 MB, which is about **9.3 GB for a 2-hour film**. That matches the plan's estimate of 9.4 GB.

## Against Neon

The worker ran in Docker with the owner's `.env.media`. It took the 8 MB of random bytes uploaded in Step 7C, refused it with "The file isn't a video VeloraUG can read.", and deleted it.

A full conversion against Neon was to follow, with a key Claude would make for the hidden movie *The Matrix*. The auto-mode safety check refused that write to the owner's database, so it is in [the owner's run](#the-owners-run) instead. Nothing was changed on Neon by Claude.

## Problems found and fixed

| Problem | Fix |
| --- | --- |
| The gate's first check said chunks didn't start on keyframes | The check was wrong: every keyframe is offset by the encoder's start delay, 0.083 s. Replaced by checking each chunk's first frame directly |
| On Windows, an error line's path wasn't hidden | The path is now hidden in both Windows and Linux forms |
| `docker compose up --build` from the repository root asked for an extra permission to read `Dockerfile.worker` | A Compose 5.6 behaviour with a Dockerfile of another name. Building from the `infra` folder works, as the README now says |

## Tested

| Check | Result |
| --- | --- |
| `ruff format --check`, `ruff check` | Clean |
| `pytest` with a throwaway local Postgres | **354 passed**, including 31 new: reading FFprobe's answer, refusals, sideways videos, which qualities each size gets, the FFmpeg command, hidden paths, the settings, and, with FFprobe and FFmpeg faked against a real database, converting, refusing and deleting, unreadable files, 3 failed tries, a second try succeeding, a missing file, putting back interrupted work, and receiving finished uploads whose hook was missed |
| Gate U2 | **Passed**, twice, the second time from the repository's copy |

## The owner's run

With Docker Desktop running and the media role set up as in Step 7C. A test clip is ready: `C:\Users\Wilsoft\veloraug\local-media\VeloraUG test 1080p.mp4`, the gate's 60-second 1080p test pattern, 98 MB. Git ignores that folder.

```powershell
cd C:\Users\Wilsoft\veloraug\infra
docker compose -f compose.local.yaml --profile uploads build media-worker
docker compose -f compose.local.yaml --profile uploads up -d media-hooks tusd media-worker
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\catalogue.py grant-upload 603 --for "7D check" --days 1
python C:\Users\Wilsoft\veloraug\tools\veloraug_upload.py "C:\Users\Wilsoft\veloraug\local-media\VeloraUG test 1080p.mp4"
```

Then, after about a minute:

```powershell
cd C:\Users\Wilsoft\veloraug\infra
docker compose -f compose.local.yaml --profile uploads logs media-worker
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\catalogue.py uploads 603
```

- 603 is *The Matrix*, which is hidden in the app.
- Paste the key only into the upload script. Leave the `vu_` line out of anything you send.
- The worker's log should say it is making 360p, 480p, 720p and 1080p, then that it converted the original.
- `uploads 603` should show the original as `publishing`, 1920×1080 H264/AAC. Its qualities appear once Step 7E publishes them.
- The HLS files are in `C:\Users\Wilsoft\veloraug\services\worker\transcoding\`, one folder per original.

## Acceptance criteria

| Criterion | State |
| --- | --- |
| Gate U2 passes | **Met** |
| The time to convert is measured and recorded, per minute of film, on this PC | **Met**. See [time and size](#time-and-size) |
| 360p and 1080p frames from a test clip are looked at, and the bitrates kept or changed | **Met** for the test pattern: kept. A real film is watched at Step 7F |
