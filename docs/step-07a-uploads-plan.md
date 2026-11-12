# Step 7A plan: uploads and processing

Date: 12 November 2026. This plans Milestone 7 in the [roadmap](roadmap.md). **Milestone 7 is not complete, and nothing here is implemented.** No migration, service, bucket or dependency exists yet. All SQL, commands and code below are drafts that have never run.

Facts about tusd, R2 and Telegram come from the [pages listed at the end](#sources), as read on this date.

## Summary

- **The owner and trusted uploaders can upload.** The owner's choice, 12 November 2026. A trusted uploader needs no VeloraUG account. The owner gives them a **one-time upload key** for one movie, and they upload one file with it. Keys expire, can be revoked, and are stored only as a hash.
- **Uploads come from a script, not the app.** The owner's choice. The owner issues keys with the catalogue script they already use. Anyone holding a key, the owner included, uploads with a small separate script that needs only Python and never touches the database. Uploads resume after a dropped connection, with [tusd](#sources).
- **Movies keep their original quality. Nothing is re-encoded.** The owner's choice. A movie can be 360p up to 4K. FFmpeg only cuts it into HLS chunks, with `-c copy`, so every frame and sound sample stays as uploaded. To offer several qualities of one movie, upload one file per quality.
- **Files the app can't play are refused, not converted.** Video must be H.264 or HEVC (H.265), and audio AAC or MP3. Anything else gets a clear reason, and the uploader sends a different file.
- **Finished movies go to private Cloudflare R2.** Viewers reach them only through the Worker, in Milestone 8. Nothing in Milestone 7 lets anyone watch.
- **Telegram isn't in Milestone 7.** The owner plans to fetch movies **from** a private Telegram channel later, rather than archive copies **to** it. That is a later milestone. See [Telegram, later](#telegram-later).
- **Everything runs on this PC in Docker for now.** tusd, the upload hooks and the media worker join the API in the local Compose file. Trusted uploaders outside this PC can't reach it until the Oracle server in Milestone 10.

## Implementation sequence

| Step | Scope | Finished when |
| --- | --- | --- |
| **7A**, this step | This plan | The owner approves it |
| **7B** | Migration `0003`: upload keys, media files and the media role. The owner's `grant-upload`, `revoke-upload` and `uploads` commands | [7B criteria](#7b-database-and-keys) pass |
| **7C** | tusd in Compose, the upload hooks, and the upload script | [7C criteria](#7c-uploads) pass, including [gate U1](#gate-u1-resume) |
| **7D** | The media worker: FFprobe checks and HLS packaging without re-encoding | [7D criteria](#7d-packaging) pass, including [gate U2](#gate-u2-no-re-encoding) |
| **7E** | Publishing to a private R2 bucket, then removing the local copies | [7E criteria](#7e-r2) pass |
| **7F** | End-to-end checks, the report, and closing the milestone | [7F criteria](#7f-end-to-end) pass |

Not in Milestone 7: playback, the Worker and the player (Milestone 8); an upload screen in the app; uploader accounts; re-encoding or extra qualities made from one file; subtitles; more than one audio track; Telegram; deployment (Milestone 10).

## Decisions

| # | Decision | Why |
| --- | --- | --- |
| 1 | Uploads are authorized by one-time **upload keys** the owner issues, each for **one file for one movie** | The owner wants trusted uploaders. Keys need no accounts, roles or app screens, and limit the damage of a leaked key to one file |
| 2 | A key is 32 random bytes, shown once, stored as a SHA-256 hash. It expires after **7 days** by default, and can be revoked | A database leak doesn't reveal usable keys. A key that is never used stops working by itself |
| 3 | The owner issues keys with `scripts/catalogue.py`, as the database owner | The same tool and the same trust as adding and publishing movies |
| 4 | Uploaders use `tools/veloraug_upload.py`, which needs only Python 3, no packages | Trusted uploaders can run it without the repository's setup. It speaks the tus protocol itself, which is three kinds of request |
| 5 | tusd checks each new upload with a **pre-create hook** to a separate, internal **media hooks** service. The hooks service is never published outside Docker's network | tusd's blocking pre-create hook can refuse an upload before any data arrives. Keeping the hooks off the public API means no one outside can call them |
| 6 | tusd runs with downloads and deletion turned off. A resumed upload is reached only by its upload address, a random ID only the uploader receives | Nobody can read or delete an upload through tusd. The pre-create hook runs once, so the address itself is the permission to resume |
| 7 | The hooks and the media worker use a new database role, **`veloraug_media`**, with row-level security | The API's role, `veloraug_app`, still can't change the catalogue or uploads. The media role can't publish movies |
| 8 | **No re-encoding.** FFmpeg runs with `-c copy`, into HLS with fMP4 chunks of about 6 seconds | The owner's rule. `-c copy` cuts at the source's own keyframes and leaves every frame unchanged. fMP4 carries HEVC as well as H.264 |
| 9 | Accepted: video **H.264 or HEVC**, at most **2160 lines** (4K); audio **AAC or MP3**; any container FFprobe reads. The first video track and the first audio track are kept | These are what HLS players on the web and Android can decode. Converting anything else would break decision 8 |
| 10 | Each uploaded file becomes one **version** of a movie, labelled by its height, such as 720p. A movie's master playlist lists every ready version | Several qualities of one movie come from several uploads. The player can choose between them in Milestone 8 |
| 11 | Uploads are at most **50 GB** each | A long 4K film fits. A runaway or mistaken upload is stopped |
| 12 | The local original is deleted once its HLS copy is safely in R2 | `-c copy` keeps the picture and the kept sound exactly. Originals will live in the owner's Telegram channel |
| 13 | Paths in R2: `movies/<movie id>/<version id>/…`, and `movies/<movie id>/master.m3u8` | VeloraUG's IDs only, never TMDB's or a filename, so nothing personal or guessable is in a path |
| 14 | Development runs everything on this PC in Docker. Test videos are **made by FFmpeg**, not downloaded | Milestone 10 deploys to Oracle. Generated clips need no rights or downloads, and can be any size, codec and resolution |

### Routes ruled out

| Route | Why not |
| --- | --- |
| An upload screen in the app | The owner chose the script. It would need admin roles, an upload UI and a Dart tus client. It can come later, using the same keys |
| Uploader accounts with roles | More than one-time keys need now. Keys can be tied to accounts later |
| Re-encoding into fixed qualities | The owner's rule: movies keep their quality |
| Uploading straight to R2 from the uploader | No resume across days, no check before data arrives, and the uploader would need R2 credentials |
| tusd storing in R2 directly | The worker needs the file on disk for FFprobe and FFmpeg anyway, and tusd's path control works only with its file store |
| Hooks on the public API | Anyone could call them, so they'd need their own secret. A service with no public port needs none |

## 1. Database

Migration `0003_uploads`, in `services/api/migrations/`, beside `0001` and `0002`. Draft:

```sql
create role veloraug_media login;   -- password set by a script, as for veloraug_app

create table public.upload_keys (
  id uuid primary key default gen_random_uuid(),
  movie_id uuid not null references public.movies (id),
  key_hash bytea not null unique,          -- sha256 of the key
  label text not null,                      -- who it's for, e.g. 'Owner' or 'Kampala Films'
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz
);

create table public.media_versions (
  id uuid primary key,                      -- also tusd's upload ID
  movie_id uuid not null references public.movies (id),
  upload_key_id uuid not null unique references public.upload_keys (id),
  state text not null check (state in
    ('uploading', 'received', 'checking', 'refused', 'packaging',
     'publishing', 'ready', 'failed', 'removed')),
  size_bytes bigint not null,
  filename text,                            -- as the uploader named it, shown to the owner only
  width int, height int, duration_seconds numeric,
  video_codec text, audio_codec text, bit_rate bigint,
  reason text,                              -- why it was refused or failed, never a path or secret
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  ready_at timestamptz
);
```

Rules, enforced by grants and forced row-level security:

- **`veloraug_media`** reads keys and marks one used. It creates versions and moves them through their states. It can't create or revoke keys, or touch `movies` beyond reading IDs.
- **`veloraug_app`**, the API, can't read keys at all. It gets no access to versions in Milestone 7. Milestone 8 adds what playback needs.
- **The owner** does everything through the script.

Database checks join `check_database.py`, as in 6B.

## 2. The owner's commands

New commands in `scripts/catalogue.py`:

| Command | What it does |
| --- | --- |
| `grant-upload 550 --for "Kampala Films" [--days 7]` | Prints a new key once, with the upload command to send. The movie must be in the catalogue. It doesn't need to be published |
| `revoke-upload <key id>` | Stops an unused key working. An upload already started stops at its next request |
| `uploads [550]` | Every key and version: who it was for, its state, size, resolution, codecs, and any reason it was refused |
| `remove-version <version id>` | Deletes a version from R2 and marks it removed. Asks first |

The key reaches a trusted uploader through a channel the owner chooses. It is never put in a URL or a commit.

## 3. Uploads

```text
uploader --tus, with Upload-Key header--> tusd --pre-create hook--> media hooks --> Neon
                                          tusd --post-finish hook--> media hooks --> Neon: state 'received'
media worker --picks 'received' versions--> FFprobe, FFmpeg -c copy --> R2 --> Neon: state 'ready'
```

- **tusd** v2.10.1, the official image, which has ARM64 builds. Flags: `-hooks-http` to the hooks service, `-hooks-enabled-events pre-create,post-finish,post-terminate`, `-disable-download`, `-disable-termination`, `-max-size 53687091200`, and a Docker volume for its files. Locally on `127.0.0.1:1080` only.
- **Pre-create** checks, in one transaction: the key exists, is unused, unexpired and unrevoked; its movie exists; the size is declared and within limit. It marks the key used, creates the version in `uploading`, and tells tusd to use the version's ID as the upload ID. Any failure refuses the upload with `403` and one plain sentence, the same for every bad key.
- **Post-finish** moves the version to `received`.
- **The upload script:** `python veloraug_upload.py <file>`, asking for the key hidden, or reading it from `VELORAUG_UPLOAD_KEY`. It saves the upload address beside the file, so running the same command again resumes. It sends 50 MB at a time and shows progress. It never prints the key.

## 4. Packaging

The media worker, in `services/worker/`, is a Python service in an image with FFmpeg from Debian. It picks one `received` version at a time with `for update skip locked`.

1. **Check**, with FFprobe: one video track that is H.264 or HEVC, at most 2160 lines high; audio AAC or MP3; a duration. Anything else is `refused`, with the reason, such as "Audio is AC-3. VeloraUG accepts AAC or MP3 audio, and doesn't convert files."
2. **Package**, with FFmpeg, roughly:

   ```text
   ffmpeg -i <upload> -map 0:v:0 -map 0:a:0? -c copy [-tag:v hvc1 for HEVC]
          -f hls -hls_time 6 -hls_playlist_type vod -hls_segment_type fmp4
          -hls_segment_filename seg_%05d.m4s index.m3u8
   ```

   Copying can only cut at the source's keyframes, so chunks can be longer than 6 seconds when the source has few keyframes. That is accepted.
3. **Publish** (7E): upload the chunks, then `index.m3u8`, then rewrite the movie's `master.m3u8` from its ready versions. Check each object's size in R2, mark the version `ready`, and delete the local files.

A version that fails is retried twice, then marked `failed`, with its files kept for the owner to look at.

## 5. R2

- One private bucket per environment: **`veloraug-dev`** now, and `veloraug-prod` in Milestone 10. No public access and no `r2.dev` address.
- The worker uses an R2 API token limited to that one bucket, with read and write. Its keys live in `services/worker/.env`, never in the app or Git.
- Tests use a fake S3 store, so R2 is needed only for 7E's real run.

## Owner setup

### At 7E: R2

1. Create a Cloudflare account, or use the one for Cloudflare Pages later. R2 may ask for a payment method even within the free allowance.
2. Create the bucket `veloraug-dev`, location hint **Eastern Europe (EEUR)** to sit near Neon and Oracle in Frankfurt.
3. Create an R2 API token, **Object Read & Write**, for that bucket only. Put its access key ID, secret and the account's S3 endpoint into `services/worker/.env`. Never in a message or a commit.

Nothing is needed from the owner for 7B to 7D.

## Gates

### Gate U1: resume

At 7C, a generated 2 GB file is uploaded, the connection is cut halfway, and the same command resumes from where it stopped. The received file's SHA-256 matches the original. **If tusd can't resume through the hooks setup,** the upload design is revisited before 7D.

### Gate U2: no re-encoding

At 7D, generated clips in H.264 and HEVC at 360p, 720p, 1080p and 2160p are packaged. FFmpeg's per-stream hashes of the video and audio packets are the same before and after. **That is the proof nothing was converted.**

## Acceptance criteria

### 7B database and keys

- Migration `0003` runs on a local Postgres set up as Neon is, then on the Neon development branch.
- Database checks: `veloraug_app` can't read keys or versions; `veloraug_media` can't create keys, publish movies or read other tables; a used, expired or revoked key can't be used again.
- `grant-upload`, `revoke-upload` and `uploads` work against a local database. No key is stored or printed except once, at creation.

### 7C uploads

- tusd, the hooks and the database work together in Compose.
- A good key uploads; a missing, wrong, used, expired or revoked key is refused before any data arrives; a second upload with the same key is refused.
- tusd refuses downloads and deletion, and the hooks service has no port outside Docker.
- Gate U1 passes. No key appears in any log.

### 7D packaging

- Gate U2 passes.
- A file with AC-3 audio, a VP9 or AV1 video, a 4320-line video, or no video is refused with a clear reason.
- The HLS output passes `ffprobe` and plays in FFmpeg from start to end.

### 7E R2

- With the owner's bucket, a version's chunks and playlists reach R2, sizes match, the version is `ready`, and its local files are gone.
- The bucket isn't readable without credentials.
- `remove-version` deletes a version's objects and rewrites the master playlist.

### 7F end to end

- The owner grants a key, uploads a generated 1080p clip and a second, 720p, version of the same movie, and sees both `ready` in `uploads`.
- A refused file, an expired key and a revoked key behave as described.
- The report records R2 use and the real sizes of the test versions.

## Cost

During development, nothing: tusd, FFmpeg and the worker run on this PC, and test clips are small. R2's free allowance is 10 GB a month of storage, 1 million writes and 10 million reads.

**Keeping original quality is the largest cost risk.** Rough sizes for a 2-hour film, depending on how it was encoded: 1080p H.264 about 2 to 8 GB; 4K HEVC about 10 to 25 GB. At R2's **$0.015 per GB-month**, 100 movies averaging 8 GB cost about **$12 a month**, and each extra version of a movie adds its own size. That is most of the $20 pilot target before the server, Worker and traffic. Reading from R2 costs nothing for data sent out.

Each chunk a viewer loads is one request to the Worker and one read from R2. A 2-hour film in 6-second chunks is about 1,200 of each per viewing. Milestone 8 checks this against the Worker's request allowance.

## Risks

| Risk | What happens |
| --- | --- |
| **HEVC and 4K don't play in every browser.** Chrome and Edge decode HEVC only with hardware support, and Firefox doesn't decode it at all. H.264 plays everywhere | A movie uploaded only in HEVC may not play for some web viewers. Milestone 8 tests it. Uploading an H.264 version as well avoids it, without any conversion |
| Sources with few keyframes make long chunks | Starts and seeks are slower. The reason is visible in `uploads` |
| Separately encoded versions of one movie don't line up exactly | Switching quality mid-film may stutter. Milestone 8 tests it |
| Trusted uploaders can't reach a server on this PC | Real outside uploads wait for Milestone 10 |
| A leaked key | One upload of one file, to one movie, which stays unpublished until the owner checks it |

## Telegram, later

The owner plans to fetch movies from a private Telegram channel instead of uploading them. With a self-hosted Telegram Bot API server, a bot can **download files without a size limit** and upload up to **2000 MB**. Without one, Telegram's cloud Bot API limits downloads to 20 MB. A later step can feed files from the channel into the same `received` → packaging → R2 path as uploads, so nothing in this plan blocks it. Telegram's terms are already on the [pre-launch check](roadmap.md#check-before-launch).

## Still unconfirmed

- Whether R2 asks for a payment method for the free allowance.
- How long tusd keeps an unfinished upload. Unfinished uploads are cleaned up by the worker after the key expires, if tusd doesn't.
- The browser and Android support for HEVC and 4K that VeloraUG's viewers actually have. Milestone 8.

## Sources

Read on 12 November 2026:

- [tusd hooks](https://tus.github.io/tusd/advanced-topics/hooks/): blocking pre-create, `RejectUpload`, `ChangeFileInfo.ID`, HTTP hooks and forwarded headers
- [tusd releases](https://github.com/tus/tusd/releases): v2.10.1, 16 September 2026. The `tusproject/tusd` image lists `linux/amd64` and `linux/arm64`
- [Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/): 10 GB-month, 1 million Class A and 10 million Class B operations free; $0.015 per GB-month; free egress
- [Telegram Bot API](https://core.telegram.org/bots/api#using-a-local-bot-api-server): a local Bot API server downloads without a size limit and uploads up to 2000 MB
