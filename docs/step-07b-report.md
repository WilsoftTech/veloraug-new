# Step 7B report: upload keys and media versions

Date: 12 November 2026. Branch: `main`. This follows the [uploads plan](step-07a-uploads-plan.md#1-database).

**Step 7B is written and passes every local check. It closes when the owner runs migration `0003` on the Neon development branch,** as in [run it on Neon](#run-it-on-neon). Nothing has changed on Neon yet.

## What changed

| Item | Where |
| --- | --- |
| Migration `0003`: the `upload_keys` and `media_versions` tables, with forced row-level security, and the `veloraug_media` role, without a login | [`migrations/versions/0003_uploads.py`](../services/api/migrations/versions/0003_uploads.py) |
| Upload keys: made, hashed, revoked and listed | [`scripts/upload_keys.py`](../services/api/scripts/upload_keys.py) |
| The owner's commands `grant-upload`, `revoke-upload` and `uploads` | [`scripts/catalogue.py`](../services/api/scripts/catalogue.py) |
| Two new database checks, so the checker has **27** | [`scripts/check_database.py`](../services/api/scripts/check_database.py) |
| Docs | [API README, Upload keys](../services/api/README.md#upload-keys) |

## The rules in the database

| Role | Upload keys | Media versions |
| --- | --- | --- |
| The owner, through the script | Makes, revokes and lists them | Lists them |
| `veloraug_media`, for the upload hooks and the worker from Step 7C | Finds a key by its hash, and marks it used **once**, only while it is unused, unrevoked and unexpired. Can't read who it was for, make, revoke or delete keys | Adds a version **only for a used key, and only for that key's movie**. Moves versions through their states. Can't delete them. Can't read movies, their details or profiles |
| `veloraug_app`, the API | Nothing | Nothing |

`veloraug_media` has no login yet, so nothing can connect as it. Step 7C gives it a password, the way `veloraug_app` got one.

**Two changes from the plan:**

- A version can also be `removing`. The owner marks a version for removal, and the worker deletes its files from R2 in Step 7E. So the owner's script never needs R2 credentials.
- `remove-version` moves to Step 7E, where removal does something.

## Tested

| Check | Result |
| --- | --- |
| `ruff format --check`, `ruff check` | Clean |
| `pytest` with a throwaway local Postgres set up as Neon is | **281 passed**, including 34 new: keys are random and recognisable, only the hash is stored, a key lasts 1 to 30 days, a key is used once, wrong, expired and revoked keys don't work, a version needs a used key for the same movie, 11 things the media role can't do, 4 things the API can't do, the new database checks, and the owner's commands from start to end |
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

## Acceptance criteria

| Criterion | State |
| --- | --- |
| `0003` runs on a local Postgres set up as Neon is | **Met** |
| `0003` runs on the Neon development branch | Waiting for the owner |
| Database checks: the API can't read keys or versions; the media role can't make keys, publish movies or read other tables; a used, expired or revoked key can't be used again | **Met** locally. The two API checks run on Neon with `check_database.py`. The media role's checks run on Neon in Step 7C, once it can log in |
| `grant-upload`, `revoke-upload` and `uploads` work against a local database, and no key is stored or printed except once, at creation | **Met** |
