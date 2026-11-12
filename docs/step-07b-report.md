# Step 7B report: upload keys, originals and qualities

Date: 12 November 2026. Branch: `feature/step-07-uploads`, from `main`. This follows the [uploads plan](step-07a-uploads-plan.md#1-database).

**Step 7B is complete.** On 12 November 2026 the owner ran migration `0003` on the Neon development branch, and every database check passed. See [the owner's run](#the-owners-run).

The migration was first written for keeping each upload's quality without conversion. The same day, the owner chose to convert every movie to 360p, 480p, 720p and 1080p and keep the original. Because `0003` hadn't run anywhere but a throwaway test database, it was rewritten rather than followed by a fix.

## What changed

| Item | Where |
| --- | --- |
| Migration `0003`: the `upload_keys`, `media_originals` and `media_renditions` tables, with forced row-level security, and the `veloraug_media` role, without a login | [`migrations/versions/0003_uploads.py`](../services/api/migrations/versions/0003_uploads.py) |
| Upload keys: made, hashed, revoked and listed with their originals and qualities | [`scripts/upload_keys.py`](../services/api/scripts/upload_keys.py) |
| The owner's commands `grant-upload`, `revoke-upload` and `uploads` | [`scripts/catalogue.py`](../services/api/scripts/catalogue.py) |
| Two new database checks, so the checker has **27** | [`scripts/check_database.py`](../services/api/scripts/check_database.py) |
| Docs | [API README, Upload keys](../services/api/README.md#upload-keys) |

## The rules in the database

| Role | Upload keys | Originals | Qualities |
| --- | --- | --- | --- |
| The owner, through the script | Makes, revokes and lists them | Lists them | Lists them |
| `veloraug_media`, for the upload hooks and the worker from Step 7C | Finds a key by its hash, and marks it used **once**, only while it is unused, unrevoked and unexpired. Can't read who it was for, make, revoke or delete keys | Adds one **only for a used key, and only for that key's movie**. Moves it through its states. Can't delete it | Adds them **only while their original is publishing**, and deletes them **only while it is being removed**. 360p, 480p, 720p or 1080p only |
| `veloraug_app`, the API | Nothing | Nothing | Nothing |

- **One original per movie is `ready`** at a time, so a replacement can't show alongside the old one.
- The media role can't read movies, their details or profiles.
- `veloraug_media` has no login yet, so nothing can connect as it. Step 7C gives it a password, the way `veloraug_app` got one.
- `remove-original` comes in Step 7E, where removing deletes files from R2. The owner marks an original `removing`, and the worker deletes its files, so the owner's script never needs R2 credentials.

## Tested

| Check | Result |
| --- | --- |
| `ruff format --check`, `ruff check` | Clean |
| `pytest` with a throwaway local Postgres set up as Neon is | **287 passed**, including 40 new. They cover keys being random and recognisable and stored only as a hash, lasting 1 to 30 days, and being used once. Wrong, expired and revoked keys don't work. An original needs a used key for the same movie. Qualities are added only while publishing and deleted only while removing. A movie has one ready original. The tests also cover 12 things the media role can't do, 5 things the API can't do, the new database checks, and the owner's commands from start to end |
| `0003` down to `0002` and up again | Tables and role removed, then back at `0003` |

The test Postgres was removed afterwards.

## Run it on Neon

In PowerShell, one command at a time. Each asks for the owner connection string, as before:

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m alembic current
.\.venv\Scripts\python.exe scripts\check_database.py
.\.venv\Scripts\python.exe scripts\catalogue.py grant-upload 550 --for Owner --days 1
.\.venv\Scripts\python.exe scripts\catalogue.py uploads
```

- `current` should say `0003 (head)`.
- `check_database.py` asks for nothing, and should print **27 PASS**.
- `grant-upload` prints a key once. Nothing can use it until Step 7C, and it expires in a day. Don't paste it anywhere.
- `uploads` should show the key for Owner as unused, without the key itself.

## The owner's run

On 12 November 2026, on the development branch, `ep-floral-salad-b98b3l94`:

| Command | Result |
| --- | --- |
| `alembic upgrade head` | `0002 -> 0003` ran |
| `alembic current` | `0003 (head)` |
| `check_database.py` | **27 passed, 0 failed**, including both new upload checks |
| `grant-upload 550 --for Owner --days 1` | A key for *Fight Club*, until 13 November 12:33 UTC |
| `uploads` | The key for Owner, unused, without the key's text |

The owner's pasted output included the key's text, so it was seen in the chat. It can't be used before Step 7C exists, and it expires after a day. The owner was asked to revoke it, and to leave the key line out of pasted output from now on.

## Acceptance criteria

| Criterion | State |
| --- | --- |
| `0003` runs on a local Postgres set up as Neon is | **Met** |
| `0003` runs on the Neon development branch | **Met**, owner's run |
| Database checks: the API can't read keys, originals or qualities; the media role can't make keys, publish movies or read other tables; a used, expired or revoked key can't be used again | **Met** locally. The API's checks run on Neon with `check_database.py`. The media role's run on Neon in Step 7C, once it can log in |
| `grant-upload`, `revoke-upload` and `uploads` work against a local database, and no key is stored or printed except once, at creation | **Met** |
