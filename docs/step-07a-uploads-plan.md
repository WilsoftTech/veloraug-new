# Step 7A plan: uploads and processing

Date: 12 November 2026, revised the same day after the owner chose to convert movies. This plans Milestone 7 in the [roadmap](roadmap.md). **Milestone 7 is not complete.** Step 7B's migration exists locally and hasn't run on Neon. No service, bucket or new dependency exists yet. Everything else below is a draft that has never run.

Facts about tusd, R2 and Telegram come from the [pages listed at the end](#sources), as read on this date.

## Summary

- **The owner and trusted uploaders can upload.** The owner's choice. A trusted uploader needs no VeloraUG account. The owner gives them a **one-time upload key** for one movie, and they upload one file with it. Keys expire, can be revoked, and are stored only as a hash.
- **Uploads come from a script, not the app.** The owner's choice. The owner issues keys with the catalogue script they already use. Anyone holding a key, the owner included, uploads with a small separate script that needs only Python and never touches the database. Uploads resume after a dropped connection, with [tusd](#sources).
- **Each movie is converted to 360p, 480p, 720p and 1080p.** The owner's choice, 12 November 2026. Video becomes H.264 and sound becomes AAC, which play in every browser and on every Android phone. The player picks the quality to suit the viewer's connection, and switches smoothly, because all qualities are cut at the same moments. **A movie never gets a quality higher than its original:** a 720p upload gets 360p, 480p and 720p.
- **The original is kept, in R2's cheaper Infrequent Access storage.** Qualities can be added or remade from it later without anyone uploading again. **Changed on 19 November 2026:** originals are no longer sent to R2. The owner keeps their own copies, on their PC or a USB drive, which saves about a third of each film's storage. 1080p is close enough to the original to convert again from if a copy is lost. See the notes under [Decisions](#decisions) for the other changes that day.
- **Finished movies go to private Cloudflare R2.** Viewers reach them only through the Worker, in Milestone 8. Nothing in Milestone 7 lets anyone watch.
- **Telegram isn't in Milestone 7.** The owner may later fetch originals **from** a private Telegram channel. Telegram isn't the only copy of anything: the original is kept in R2. See [Telegram, later](#telegram-later).
- **Everything runs on this PC in Docker for now.** tusd, the upload hooks and the media worker join the API in the local Compose file. Trusted uploaders outside this PC can't reach it until the Oracle server in Milestone 10.

## Implementation sequence

| Step | Scope | Finished when |
| --- | --- | --- |
| **7A**, this step | This plan | The owner approves it. **Approved 12 November 2026** |
| **7B** | Migration `0003`: upload keys, originals, qualities and the media role. The owner's `grant-upload`, `revoke-upload` and `uploads` commands | [7B criteria](#7b-database-and-keys) pass |
| **7C** | tusd in Compose, the upload hooks, and the upload script | [7C criteria](#7c-uploads) pass, including [gate U1](#gate-u1-resume) |
| **7D** | The media worker: FFprobe checks and conversion to the four qualities as HLS | [7D criteria](#7d-conversion) pass, including [gate U2](#gate-u2-conversion) |
| **7E** | Publishing to private R2, keeping the original, and removing local copies | [7E criteria](#7e-r2) pass |
| **7F** | End-to-end checks, the report, and closing the milestone | [7F criteria](#7f-end-to-end) pass |

Not in Milestone 7: playback, the Worker and the player (Milestone 8); an upload screen in the app; uploader accounts; 4K; subtitles; more than one sound track; Telegram; deployment (Milestone 10).

## Decisions

| # | Decision | Why |
| --- | --- | --- |
| 1 | Uploads are authorized by one-time **upload keys** the owner issues, each for **one file for one movie** | The owner wants trusted uploaders. Keys need no accounts, roles or app screens, and limit the damage of a leaked key to one file |
| 2 | A key is 32 random bytes, shown once, stored as a SHA-256 hash. It expires after **7 days** by default, at most 30, and can be revoked | A database leak doesn't reveal usable keys. A key that is never used stops working by itself |
| 3 | The owner issues keys with `scripts/catalogue.py`, as the database owner | The same tool and the same trust as adding and publishing movies |
| 4 | Uploaders use `tools/veloraug_upload.py`, which needs only Python 3, no packages | Trusted uploaders can run it without the repository's setup. It speaks the tus protocol itself, which is three kinds of request |
| 5 | tusd checks each new upload with a **pre-create hook** to a separate, internal **media hooks** service, which is never published outside Docker's network | tusd's blocking pre-create hook can refuse an upload before any data arrives. Keeping the hooks off the public API means no one outside can call them |
| 6 | tusd runs with downloads and deletion turned off. A resumed upload is reached only by its upload address, a random ID only the uploader receives | Nobody can read or delete an upload through tusd. The pre-create hook runs once, so the address itself is the permission to resume. **Changed in Step 9G:** deletion is on for unfinished uploads only, for the browser's Remove. A `pre-terminate` hook refuses it for any upload that has finished |
| 7 | The hooks and the media worker use a new database role, **`veloraug_media`**, with row-level security | The API's role, `veloraug_app`, still can't change the catalogue or uploads. The media role can't publish movies |
| 8 | **The quality ladder:** 360p, 480p, 720p and 1080p, H.264 video and stereo AAC sound, in HLS with fMP4 chunks of 6 seconds. Only the qualities at or below the original's height are made | The owner's choice. H.264 and AAC play everywhere. A fixed keyframe every 2 seconds, the same in every quality, lets the player switch cleanly |
| 9 | Accepted: any file FFprobe reads with a video track **at least 360 lines** high. The first video track and the first sound track are used | Conversion means almost any format works. Below 360 lines there is no quality to make |
| 10 | **One original per movie.** It can be replaced: a new upload's qualities take over once they're all ready, and the old original is then removed | Simple for viewers and the owner. A better copy can replace a poor one without a gap |
| 11 | Uploads are at most **50 GB** each | A long 4K original fits. A runaway or mistaken upload is stopped |
| 12 | The original is kept in R2 **Infrequent Access**, and deleted from this PC once it and its qualities are safely in R2 | The owner approved keeping the master copy somewhere dependable. Infrequent Access costs less to store, and originals are rarely read |
| 13 | Paths in R2: `movies/<movie id>/<original id>/<quality>/…`, `movies/<movie id>/<original id>/master.m3u8`, and `originals/<original id>` | VeloraUG's IDs only, never TMDB's or a filename, so nothing personal or guessable is in a path |
| 14 | Development runs everything on this PC in Docker. Test videos are **made by FFmpeg**, not downloaded | Milestone 10 deploys to Oracle. Generated clips need no rights or downloads, and can be any size, format and resolution |

Draft bitrates, to be checked by eye at 7D:

| Quality | Size | Video | Sound | 2-hour film |
| --- | --- | --- | --- | --- |
| 360p | 640 × 360 | 800 kbit/s | 96 kbit/s | about 0.8 GB |
| 480p | 854 × 480 | 1,400 kbit/s | 128 kbit/s | about 1.4 GB |
| 720p | 1280 × 720 | 2,800 kbit/s | 128 kbit/s | about 2.6 GB |
| 1080p | 1920 × 1080 | 5,000 kbit/s | 128 kbit/s | about 4.6 GB |
| **All four** | | | | **about 9.4 GB** |

Widths follow the original's shape: a wider film keeps its proportions, and only the height is fixed.

**Changed on 18 November 2026:** no quality gets more video bitrate than the original's own, read by FFprobe from the video track, from Matroska's `BPS` tag, or from the whole file's less its sound. The first real translated film, a 2.0 Mbit/s 1920 × 800 rip, was stored at 6.7 GB with the table above, its 1080p at about 4.8 Mbit/s. With the cap, 720p and 1080p get 2.0 Mbit/s and the film about 4.2 GB, with nothing visible lost. The floor is 400 kbit/s, and a file whose bitrate can't be read keeps the table.

**Changed on 19 November 2026:** the ladder is sized from the original. The top quality gets at most the original's bitrate, and each quality below at most 60% of the one above it. A middle quality that would come out within 60% of the lowest is left out, and the lowest is left out when it would have 80% of the top's bitrate or more. With the cap alone, a typical VJ file still came out at about 3× its size: Baby John 2, 1.49 GB at 2.4 Mbit/s, made 4.34 GB, because 720p got the same 2.4 Mbit/s as 1080p and 480p sat close to 360p. Now it gets 1080p at 2.4, 720p at 1.44 and 360p at 0.8 Mbit/s, about 2.6 GB. An original rich enough for the table, 4.7 Mbit/s or more at 1080p, still gets all four qualities at the table's bitrates. Films already converted keep their qualities.

**Also changed on 19 November 2026: capped quality.** Video is encoded at x264 CRF 23 with each quality's bitrate as its ceiling (`-maxrate`, and twice that as `-bufsize`), not at a fixed bitrate. Easy scenes use fewer bits, and hard ones at most what they used before. On two 90-second clips of a VJ file, 1080p at 2.4 Mbit/s, CRF 23 at `veryfast` came out 35% and 42% smaller than the fixed bitrate, with SSIM 0.9479 against 0.9483 and 0.9780 against 0.9799, and the same time to convert. The `faster` and `fast` presets at CRF 23 came out larger, aiming at a higher quality, and `fast` took up to 10× as long, so `veryfast` stays. FFmpeg measures each quality's `BANDWIDTH` for the master playlist from the chunks themselves. On a 30-second piece of the same film, the three qualities took 14.9 MB, about 2.6 GB for its 88 minutes, where the old ladder made about 5.3 GB.

### Routes ruled out

| Route | Why not |
| --- | --- |
| An upload screen in the app | The owner chose the script. It would need admin roles, an upload UI and a Dart tus client. It can come later, using the same keys. **Built in Step 9G**, in the admin screens, with the same keys. The script stays for trusted uploaders |
| Uploader accounts with roles | More than one-time keys need now. Keys can be tied to accounts later |
| Keeping the original's quality without converting | Compared with the owner on 12 November. Viewers on mobile data would get one large stream, HEVC and 4K don't play everywhere, and many files would be refused |
| 4K | Most viewers watch on phones, and it would roughly double storage again. It can be made later from the kept originals |
| Uploading straight to R2 from the uploader | No resume across days, no check before data arrives, and the uploader would need R2 credentials |
| Hooks on the public API | Anyone could call them, so they'd need their own secret. A service with no public port needs none |
| Telegram as the only copy of originals | Telegram promises nothing about keeping files, and can remove channels |

## 1. Database

Migration `0003_uploads`, in `services/api/migrations/`, beside `0001` and `0002`:

- **`upload_keys`:** the movie, the key's SHA-256, who it is for, when it was made, when it expires, and when it was used or revoked.
- **`media_originals`:** one per upload. Its ID is also tusd's upload ID. Its state moves through `uploading`, `received`, `checking`, `converting`, `publishing` and `ready`, or ends `refused` or `failed`; later `removing` and `removed`. It records the size, the uploader's filename, what FFprobe found, and the reason for any refusal or failure. At most one original per movie is `ready`.
- **`media_renditions`:** one per quality made from an original: its height, width, bitrate and size. Rows are added as each quality is published.

Rules, enforced by grants and forced row-level security:

- **`veloraug_media`** reads keys and marks one used, once, while it is valid. It adds an original only for a used key and that key's movie, and moves it through its states. It adds and deletes qualities. It can't create, relabel or revoke keys, delete originals, or read movies, their details or profiles.
- **`veloraug_app`**, the API, can't read keys, originals or qualities in Milestone 7. Milestone 8 adds what playback needs.
- **The owner** does everything through the script.

## 2. The owner's commands

New commands in `scripts/catalogue.py`:

| Command | What it does |
| --- | --- |
| `grant-upload 550 --for "Kampala Films" [--days 7]` | Prints a new key once. The movie must be in the catalogue. It doesn't need to be published |
| `revoke-upload <key id>` | Stops an unused key working |
| `uploads [550]` | Every key and its original: who it was for, its state, size, resolution, the qualities made, and any reason it was refused |
| `remove-original <original id>`, at 7E | Marks an original for removal. The worker deletes its files from R2. Asks first |

The key reaches a trusted uploader through a channel the owner chooses. It is never put in a URL or a commit.

## 3. Uploads

```text
uploader --tus, with Upload-Key header--> tusd --pre-create hook--> media hooks --> Neon
                                          tusd --post-finish hook--> media hooks --> Neon: 'received'
media worker --picks a 'received' original--> FFprobe, FFmpeg --> R2 --> Neon: 'ready'
```

- **tusd** v2.10.1, the official image, which has ARM64 builds. Flags: `-hooks-http` to the hooks service, `-hooks-enabled-events pre-create,post-finish,post-terminate`, `-disable-download`, `-disable-termination`, `-max-size 53687091200`, and a Docker volume for its files. Locally on `127.0.0.1:1080` only.
- **Pre-create** checks, in one transaction: the key exists, is unused, unexpired and unrevoked; the size is declared and within limit. It marks the key used, creates the original in `uploading`, and tells tusd to use the original's ID as the upload ID. Any failure refuses the upload with `403` and one plain sentence, the same for every bad key.
- **Post-finish** moves the original to `received`.
- **The upload script:** `python veloraug_upload.py <file>`, asking for the key hidden, or reading it from `VELORAUG_UPLOAD_KEY`. It saves the upload address beside the file, so running the same command again resumes. It sends 50 MB at a time and shows progress. It never prints the key.

## 4. Conversion

The media worker, in `services/worker/`, is a Python service in an image with FFmpeg from Debian. It takes one `received` original at a time, with `for update skip locked`, so a second worker could share the queue later.

1. **Check**, with FFprobe: a video track at least 360 lines high, and a duration. Anything else is `refused`, with a reason such as "No video track found."
2. **Convert**, with FFmpeg, one pass making every quality at or below the original's height. Roughly:

   ```text
   ffmpeg -i <original> -map 0:v:0 -map 0:a:0? (once per quality)
          -c:v libx264 -preset veryfast -profile:v high -b:v <rate> -maxrate <1.07 × rate> -bufsize <2 × rate>
          -g <2 s of frames> -keyint_min <same> -sc_threshold 0 -vf scale=-2:<height>
          -c:a aac -ac 2 -b:a <rate>
          -f hls -hls_time 6 -hls_playlist_type vod -hls_segment_type fmp4
          -master_pl_name master.m3u8 -var_stream_map "v:0,a:0 v:1,a:1 …"
   ```

   A film without sound gets qualities without sound.
3. **Publish** (7E): upload every quality's chunks and playlists, then `master.m3u8`, then the original to Infrequent Access. Check each object's size in R2. Mark the original `ready`, record its qualities, start removing any original it replaces, and delete the local files.

An original that fails is retried twice, then marked `failed`, with its files kept for the owner to look at.

**Time:** converting is the slow part. On this PC it is measured at 7D. The Oracle server's 4 ARM cores may take a few hours per film, which is fine one film at a time for a pilot. Milestone 10 measures it there.

## 5. R2

- One private bucket per environment: **`veloraug-dev`** now, and `veloraug-prod` in Milestone 10. No public access and no `r2.dev` address.
- Qualities use **Standard** storage. Originals use **Infrequent Access**, set per upload.
- The worker uses an R2 API token limited to that one bucket, with read and write. Its keys live in `services/worker/.env`, never in the app or Git.
- Tests use a fake S3 store, so R2 is needed only for 7E's real run.

## Owner setup

### At 7E: R2

1. Create a Cloudflare account, or use the one for Cloudflare Pages later. R2 may ask for a payment method even within the free allowance.
2. Create the bucket `veloraug-dev`, location hint **Eastern Europe (EEUR)**, to sit near Neon and Oracle in Frankfurt.
3. Create an R2 API token, **Object Read & Write**, for that bucket only. Put its access key ID, secret and the account's S3 endpoint into `services/worker/.env`. Never in a message or a commit.

Nothing is needed from the owner for 7C and 7D.

## Gates

### Gate U1: resume

At 7C, a generated 2 GB file is uploaded, the connection is cut halfway, and the same command resumes from where it stopped. The received file's SHA-256 matches the original. **If tusd can't resume through the hooks setup,** the upload design is revisited before 7D.

### Gate U2: conversion

At 7D, generated clips at 360, 720, 1080 and 2160 lines, in H.264, HEVC and VP9, with AAC, AC-3 and no sound, are converted. Each gets exactly the qualities at or below its height, every chunk of every quality starts on a keyframe at the same moment, and each quality plays in FFmpeg from start to end. A clip under 360 lines, or with no video, is refused with a clear reason.

## Acceptance criteria

### 7B database and keys

- Migration `0003` runs on a local Postgres set up as Neon is, then on the Neon development branch.
- Database checks: `veloraug_app` can't read keys, originals or qualities; `veloraug_media` can't create keys, publish movies or read other tables; a used, expired or revoked key can't be used again.
- `grant-upload`, `revoke-upload` and `uploads` work against a local database. No key is stored or printed except once, at creation.

### 7C uploads

- tusd, the hooks and the database work together in Compose.
- A good key uploads; a missing, wrong, used, expired or revoked key is refused before any data arrives; a second upload with the same key is refused.
- tusd refuses downloads and deletion, and the hooks service has no port outside Docker.
- Gate U1 passes. No key appears in any log.

### 7D conversion

- Gate U2 passes.
- The time to convert is measured and recorded, per minute of film, on this PC.
- 360p and 1080p frames from a test clip are looked at, and the bitrates kept or changed.

### 7E R2

- With the owner's bucket, an original's qualities, playlists and the original itself reach R2, sizes match, the original is `ready`, and its local files are gone.
- The original is in Infrequent Access, and the qualities in Standard.
- The bucket isn't readable without credentials.
- `remove-original` deletes an original's objects. A replacement takes over only once all its qualities are ready.

### 7F end to end

- The owner grants a key and uploads a generated 1080p clip, sees it `ready` with four qualities, then replaces it with a 720p clip and sees three.
- A refused file, an expired key and a revoked key behave as described.
- The report records R2 use and the real sizes of the test files.

## Cost

During development, nothing: tusd, FFmpeg and the worker run on this PC, and test clips are small. R2's free allowance is 10 GB a month of **Standard** storage, 1 million writes and 10 million reads. It doesn't cover Infrequent Access.

**Storage, at 100 two-hour films:**

| What | Size | Price | A month |
| --- | --- | --- | --- |
| Qualities, all four | about 940 GB | $0.015 per GB, Standard | about **$14** |
| Originals, if they average 6 GB | about 600 GB | $0.01 per GB, Infrequent Access | about **$6** |
| **Total** | | | about **$20** |

**That is the whole $20 pilot target, for storage alone,** before the server, the Worker and traffic. It grows with the number of films. With fewer films, or originals kept only in Telegram, it is less. Films that are shorter, or whose originals are below 1080p, cost less too. The owner should choose the catalogue size for the pilot with this in mind. Reading data out of R2 costs nothing, except $0.01 per GB to read an original back from Infrequent Access.

Each chunk a viewer loads is one request to the Worker and one read from R2. A 2-hour film in 6-second chunks is about 1,200 of each per viewing. Milestone 8 checks this against the Worker's request allowance.

## Risks

| Risk | What happens |
| --- | --- |
| **Storage cost** | About $20 a month at 100 films. See [cost](#cost) |
| Conversion is slow on 4 ARM cores | New films take hours to become ready. Measured at 7D and in Milestone 10 |
| Re-encoding loses some quality | Hard to see on a phone. 1080p frames are looked at during 7D, and bitrates raised if needed |
| Trusted uploaders can't reach a server on this PC | Real outside uploads wait for Milestone 10 |
| A leaked key | One upload of one file, to one movie, which stays unpublished until the owner checks it |

## Telegram, later

The owner may later fetch originals from a private Telegram channel instead of uploading them. With a self-hosted Telegram Bot API server, a bot can **download files without a size limit**. Without one, Telegram's cloud Bot API limits downloads to **20 MB**. A later step can feed files from the channel into the same `received` → conversion → R2 path as uploads, so nothing in this plan blocks it. The original is still kept in R2. Telegram's terms are on the [pre-launch check](roadmap.md#check-before-launch).

## Still unconfirmed

- Whether R2 asks for a payment method for the free allowance.
- How long tusd keeps an unfinished upload. Unfinished uploads are cleaned up by the worker after the key expires, if tusd doesn't.
- How long conversion takes, here and on Oracle.

## Sources

Read on 12 November 2026:

- [tusd hooks](https://tus.github.io/tusd/advanced-topics/hooks/): blocking pre-create, `RejectUpload`, `ChangeFileInfo.ID`, HTTP hooks and forwarded headers
- [tusd releases](https://github.com/tus/tusd/releases): v2.10.1, 16 September 2026. The `tusproject/tusd` image lists `linux/amd64` and `linux/arm64`
- [Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/): Standard, $0.015 per GB-month with 10 GB, 1 million Class A and 10 million Class B operations free; Infrequent Access, $0.01 per GB-month, $0.01 per GB to read back, 30 days minimum, no free allowance; free egress
- [Telegram Bot API](https://core.telegram.org/bots/api): a local Bot API server downloads without a size limit; the cloud Bot API's maximum download is 20 MB
