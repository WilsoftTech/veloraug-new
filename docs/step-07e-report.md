# Step 7E report: publishing to R2

Date: 12 November 2026. Branch: `feature/step-07-uploads`. This follows the [uploads plan](step-07a-uploads-plan.md#5-r2).

**Step 7E is written and tested with an in-memory stand-in for the bucket.** It closes after [the owner's run](#the-owners-run): creating the `veloraug-dev` bucket and its token, checking them, and publishing the 1080p test clip. That run also closes Step 7D.

## What changed

| Item | Where |
| --- | --- |
| The publisher: uploads chunks, then playlists, then the master, then the original to Infrequent Access; checks every size in R2; records the qualities; marks the original `ready`, with any previous original `removing`; deletes the local copies. Also removes an original's files | [`services/api/app/media_publisher.py`](../services/api/app/media_publisher.py) |
| The worker publishes right after converting, publishes anything left in `publishing`, and removes anything `removing`. Failures wait 1, then 2 minutes; publishing that fails 3 times is `failed` | [`services/api/app/media_worker.py`](../services/api/app/media_worker.py) |
| `remove-original`: the owner marks an original for removal, after typing `remove` | [`scripts/catalogue.py`](../services/api/scripts/catalogue.py), [`scripts/upload_keys.py`](../services/api/scripts/upload_keys.py) |
| `check_r2.py`: 6 checks of the bucket and its token, leaving nothing behind | [`scripts/check_r2.py`](../services/api/scripts/check_r2.py) |
| boto3 1.44.1 and the 6 packages it needs, pinned, for the worker's image only | [`requirements-worker.txt`](../services/api/requirements-worker.txt) |
| R2's keys in their own file, `services/api/.env.r2`, which Git ignores and only the worker's container gets | [`infra/compose.local.yaml`](../infra/compose.local.yaml) |
| Docs, with the Cloudflare steps | [API README, Publish to R2](../services/api/README.md#publish-to-r2) |

**How the worker talks to R2:**
- It uses boto3 with R2's endpoint and region `auto`.
- Checksums are sent only where S3 requires them, so newer boto3 defaults can't send headers R2 refuses.
- It retries 5 times, and uploads files over 64 MB in 64 MB parts, 4 at a time. A 50 GB original is about 800 parts, well within S3's limit of 10,000.

**Settings:**
- The R2 settings must be all four or none. Without them, the worker converts and leaves originals in `publishing`, as in Step 7D.
- The endpoint must be `https://….r2.cloudflarestorage.com`, without a path.
- Errors never quote the secret.

**Changes from the plan:**

- **Removal is done by the worker.** The owner's `remove-original` only marks an original `removing`, so the owner's script never needs R2's keys. That needed the `removing` state added in Step 7B.
- **R2's keys aren't in `.env.media`.** The hooks' container would then hold them too.

## Problem found and fixed

**The API README had lost two sections, "The concepts" and "Change a dependency".** My README edit in Step 7C rebuilt the file from pieces and dropped everything after the Uploads section. I noticed it while looking for the dependency procedure here, restored both sections word for word from the version before, and committed that separately.

## Tested

| Check | Result |
| --- | --- |
| `ruff format --check`, `ruff check` | Clean |
| `pytest` with a throwaway local Postgres | **367 passed**, including 13 new. They cover reading the master playlist; R2 settings being all or none, only an R2 endpoint, and the secret never shown; and the R2 client setting type, cache time and Infrequent Access. Against a real database with the stand-in bucket: publishing everything in order, with the right types and classes, then `ready`, qualities recorded and local files gone; a wrong size stopping it before `ready`; failures waiting longer each time, then `failed`; a new original taking over and the old one removed; the owner's removal; and waiting without R2 |
| The worker's image, rebuilt | boto3 1.44.1 inside. The worker starts without `.env.r2`, and says converted originals wait |

## The owner's run

**1. Set up R2,** as in [the README's steps](../services/api/README.md#publish-to-r2): an R2 subscription if Cloudflare asks, the bucket `veloraug-dev` in Eastern Europe, an **Object Read & Write** token for that bucket only, and the four lines in `services/api/.env.r2`. Never paste the keys into a message.

**2. Check the bucket and restart the worker:**

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\check_r2.py
cd C:\Users\Wilsoft\veloraug\infra
docker compose -f compose.local.yaml --profile uploads up -d media-hooks tusd
docker compose -f compose.local.yaml --profile uploads up -d --force-recreate media-worker
```

`check_r2.py` should print **6 passed, 0 failed**.

**3. Upload the test clip,** to *The Matrix*, 603, which is hidden in the app:

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\catalogue.py grant-upload 603 --for "7E check" --days 1
python C:\Users\Wilsoft\veloraug\tools\veloraug_upload.py "C:\Users\Wilsoft\veloraug\local-media\VeloraUG test 1080p.mp4"
```

Paste the key only into the upload script.

**4. After about two minutes:**

```powershell
.\.venv\Scripts\python.exe scripts\catalogue.py uploads 603
```

It should show the original as `ready`, 1920×1080 H264/AAC, with qualities 360p, 480p, 720p and 1080p. In the Cloudflare dashboard, `veloraug-dev` should hold `movies/…` and `originals/…`. `services\worker\transcoding\` should be empty again.

## Acceptance criteria

| Criterion | State |
| --- | --- |
| An original's qualities, playlists and the original itself reach R2, sizes match, it is `ready`, and its local files are gone | **Met** with the stand-in bucket. The real bucket at the owner's run |
| The original is in Infrequent Access, and the qualities in Standard | **Met** with the stand-in bucket. `check_r2.py` checks a real Infrequent Access upload in parts |
| The bucket isn't readable without credentials | `check_r2.py` checks it at the owner's run |
| `remove-original` deletes an original's objects. A replacement takes over only once all its qualities are ready | **Met** with the stand-in bucket |
