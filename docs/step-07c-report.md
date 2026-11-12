# Step 7C report: resumable uploads

Date: 12 November 2026. Branch: `feature/step-07-uploads`. This follows the [uploads plan](step-07a-uploads-plan.md#3-uploads).

**Step 7C is complete.** Gate U1 passed on this PC against a throwaway database, and on 12 November 2026 a file uploaded through tusd and the hooks against the Neon development branch. See [the owner's run](#the-owners-run).

## What changed

| Item | Where |
| --- | --- |
| The upload hooks: a separate app that tusd asks before each upload. It checks the size and the key, uses the key once, records the original, and marks it `received` when the upload finishes | [`services/api/app/media_hooks.py`](../services/api/app/media_hooks.py) |
| Upload keys' hashing, shared by the hooks and the owner's script | [`services/api/app/upload_keys.py`](../services/api/app/upload_keys.py) |
| The uploaders' script: standard-library Python, resumes after a drop or a restart, never prints or saves the key | [`tools/veloraug_upload.py`](../tools/veloraug_upload.py) |
| tusd v2.10.1 and the hooks in the local Compose file, behind the `uploads` profile | [`infra/compose.local.yaml`](../infra/compose.local.yaml) |
| `create_app_role.py --role media`: gives `veloraug_media` a login, saved in `services/api/.env.media` | [`scripts/create_app_role.py`](../services/api/scripts/create_app_role.py) |
| `check_media_role.py`: 14 checks of the media role, all rolled back | [`scripts/check_media_role.py`](../services/api/scripts/check_media_role.py) |
| Docs | [API README, Uploads](../services/api/README.md#uploads), [infra README](../infra/README.md), [worker README](../services/worker/README.md) |

**How tusd is set up:**
- It listens on `127.0.0.1:1080` only.
- Downloads, deletion, the greeting page and the metrics page are all off, and uploads are limited to 50 GB.
- Hooks are called for `pre-create` and `post-finish` only.
- `-hooks-http-retry=0`: a repeated pre-create call could find its own key already used, and refuse the upload it had just accepted.

**The hooks:**
- They run from the API's image as a separate app, with no published port, on their own Docker network with tusd.
- tusd treats any status but 200 from the hooks as a failure, so a refusal is a 200 whose JSON tells tusd to refuse with 400, 403, 413 or 503 and one plain sentence.

**Two changes from the plan:**

- **The hooks live in `services/api`, not `services/worker`.** They need the same database pool, test setup and migrations as the API, so sharing that code avoids a second copy. They still run as their own container, with only the media role's credentials. The worker README points there.
- **The media role's password goes in its own file**, `services/api/.env.media`, which Git ignores. The API's container gets `.env` only, so it never holds the media role's password.

## Gate U1: resume

**Passed** on 12 November 2026, with tusd and the hooks in Docker, against a throwaway local Postgres set up as Neon is:

| Step | Result |
| --- | --- |
| A random 2 GB file (2,147,483,648 bytes) started uploading with a key | Accepted |
| The uploader was killed | At 1,076,983,048 bytes, after 42 seconds |
| The progress file beside the movie | Kept, without the key |
| The same command, run again with no key given | "Carrying on with the upload started earlier", then finished |
| The received file | 2,147,483,648 bytes, **same SHA-256** as the original |
| The progress file | Deleted |
| The database | The original `received`, its size and filename recorded, its key used |

## Other checks, on the same setup

| Check | Result |
| --- | --- |
| No key, a wrong key, an expired key | `403`, with "This upload key doesn't work. It may be mistyped, already used, expired or revoked. Ask VeloraUG's owner for a new one." |
| The used key again | `403` |
| No declared size | `400`, "Say the file's size when starting the upload." |
| Over 50 GB | `413` |
| Downloading or deleting an upload through tusd | `405` |
| tusd's greeting page and metrics | `404` |
| The hooks from Windows | No port: `docker compose ps` shows `8000/tcp` with no host address |
| Logs of tusd and the hooks, after both the 2 GB and a small upload | No key, no `vu_`, no `Upload-Key` header. The hooks logged each upload accepted, received and refused |

The first run showed the hooks' accepted and received lines weren't printed, because Python drops INFO messages unless logging is set up. The hooks now set up their own log lines, and the second upload showed them.

Afterwards the containers, the throwaway database, the gate's `.env.media`, the test files and the received uploads were all removed.

## Tested

| Check | Result |
| --- | --- |
| `ruff format --check`, `ruff check`, over `services/api` and `tools` | Clean |
| `pytest` with a throwaway local Postgres | **323 passed**, including 36 new: refusals before the database, the same sentence for every bad key, headers in any case, tidied filenames, settings that refuse any role but `veloraug_media` without quoting the password, no documentation pages, `503` when the database is unreachable, a key used once, a wrong key changing nothing, a finished upload received once, the app over HTTP, the media role's env file, and every media role check. The upload script is tested against a fake tus server for pieces, two dropped connections, a restart without the key, a refused key, a forgotten upload, another file's progress, an unreachable server, empty and missing files, and using only the standard library |

## The owner's run

With Docker Desktop running, in PowerShell, one command at a time. The first asks for the owner connection string and for `yes`:

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\create_app_role.py --role media
.\.venv\Scripts\python.exe scripts\check_media_role.py
cd C:\Users\Wilsoft\veloraug
docker compose -f infra/compose.local.yaml --profile uploads up -d --build media-hooks tusd
docker compose -f infra/compose.local.yaml --profile uploads ps
```

- `check_media_role.py` should print **14 passed, 0 failed**.
- `ps` should show `media-hooks` as `healthy` and `tusd` as up on `127.0.0.1:1080`.

Then upload a small file, any video or other file of a few MB, with a new key:

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\catalogue.py grant-upload 550 --for Owner --days 1
python C:\Users\Wilsoft\veloraug\tools\veloraug_upload.py "C:\path\to\a small file.mp4"
.\.venv\Scripts\python.exe scripts\catalogue.py uploads
```

- Paste the key when the upload script asks. Don't paste the key, or the `vu_` line, into a message.
- `uploads` should show the key as used, and its original as `received`, with the file's size and name.
- To stop the services afterwards: `docker compose -f infra/compose.local.yaml --profile uploads stop media-hooks tusd`.

### Results, 12 November 2026

| Step | Result |
| --- | --- |
| `create_app_role.py --role media`, by the owner | `veloraug_media` got a login; its connection string was saved in `.env.media` |
| `check_media_role.py`, by the owner | **14 passed, 0 failed** |
| Compose `up` with the `uploads` profile, by the owner | `media-hooks` healthy, with no host port; `tusd` up on `127.0.0.1:1080` |
| `grant-upload 550 --for Owner --days 1`, by the owner | A key for *Fight Club* |
| The upload script, run by Claude with that key, on an 8 MB file of random bytes | Uploaded. tusd holds all 8,388,608 bytes |
| Neon, read as the owner | The original `received`, 8,388,608 bytes, `VeloraUG 7C check.mp4`, its key used |
| The hooks' log | Accepted, then received. No key in any log line |

The owner's first try at the upload ran the instructions' placeholder path, so Claude ran it with a test file instead. The owner's paste included the key's text again. Using it for this upload used it up.

The test file is random bytes, not a video. Step 7D's worker should refuse it, with "No video track found", which makes it a ready-made test of a refusal.

## Acceptance criteria

| Criterion | State |
| --- | --- |
| tusd, the hooks and the database work together in Compose | **Met**, locally and with Neon |
| A good key uploads; a missing, wrong, used, expired or revoked key is refused before any data arrives; a second upload with the same key is refused | **Met**. Revoked keys are refused by the same rule as used and expired ones, tested in Step 7B |
| tusd refuses downloads and deletion, and the hooks have no port outside Docker | **Met** |
| Gate U1 passes, and no key appears in any log | **Met** |
