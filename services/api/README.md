# API

The FastAPI backend, written in Python. It will become the trusted part of the system: the app asks it to do things, and it checks whether each request is allowed.

**Today it handles sign-in, profiles and the movie catalogue.** `/api/v1/me` checks Neon Auth access tokens and reads or changes the signed-in user's profile in Neon PostgreSQL. `/api/v1/movies` lists the published movies, with details from TMDB, and needs no sign-in. It has no uploads or payments yet. The Flutter app calls it only from a [development-only connection check](../../apps/client/README.md#connect-to-the-local-api).

Later it will fetch movie details from TMDB, handle Pesapal payments and issue playback access. See the [roadmap](../../docs/roadmap.md).

This page runs the API directly with Python. To run it in a container instead, see [infra/README.md](../../infra/README.md).

## Setup

You need Python 3.13. Check with `python --version`. Run these once in PowerShell:

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
```

Every command here calls `.\.venv\Scripts\python.exe` directly, so you don't need to activate the virtual environment or change PowerShell's execution policy.

## Start the API

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000 --env-file .env
```

`--env-file .env` passes your settings, such as the database address and the TMDB token, to the API. The API never reads `.env` itself. Without the option it still starts, but movies fail with "The database isn't set up on this server", and the app says "VeloraUG is busy right now".

Leave that terminal open, then open these in a browser:

| Address | What you should see |
| --- | --- |
| <http://127.0.0.1:8000/health> | `{"status":"ok"}` |
| <http://127.0.0.1:8000/api/v1> | `{"service":"veloraug-api","api_version":"v1","environment":"development"}` |
| <http://127.0.0.1:8000/api/v1/me> | `{"detail":"Not signed in."}`, because a browser address sends no token. Without the [settings](#settings) it says sign-in or the database isn't set up |
| <http://127.0.0.1:8000/api/v1/movies> | The published movies, as `{"movies": [...], "next_offset": null}`. Without the database it answers `503` |
| <http://127.0.0.1:8000/docs> | Interactive documentation. The page loads its scripts from the internet, so it needs a connection |
| <http://127.0.0.1:8000/openapi.json> | The same documentation as raw data |

Press `Ctrl+C` in the terminal to stop the server.

## Run the checks

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe -m ruff format --check .
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m pytest
```

`ruff format --check` reports code that needs reformatting, and `ruff format .` fixes it. `ruff check` looks for likely mistakes. `pytest` runs the tests in `tests/`.

**The database tests are skipped** unless a throwaway local Postgres is running. They never touch Neon. To run them too, start one in Docker, run `pytest` with its address set, then remove it:

```powershell
docker run -d --name veloraug-test-db -e POSTGRES_PASSWORD=local-test-admin -p 127.0.0.1:15432:5432 postgres:17
$env:VELORAUG_TEST_ADMIN_URL = 'postgresql://postgres:local-test-admin@127.0.0.1:15432/postgres'
.\.venv\Scripts\python.exe -m pytest
Remove-Item Env:VELORAUG_TEST_ADMIN_URL
docker rm -f veloraug-test-db
```

The password is for that container only, which only this computer can reach. Port `15432` avoids the ranges Windows reserves, such as `55368` to `55467`. The tests create a database called `veloraug_test` there, set up the way Neon is, and run the migration on it.

## How the code is laid out

| File | Job |
| --- | --- |
| `app/main.py` | `create_app()`, the application factory: builds the app, applies the settings and adds CORS |
| `app/routes.py` | The endpoints and the shape of their responses |
| `app/auth.py` | Checks access tokens, and gives signed-in routes the user's ID |
| `app/db.py` | The database connection pool. Each request runs in one transaction that acts for one user |
| `app/profiles.py` | Profile reads and writes |
| `app/catalogue.py` | Catalogue reads, the age rules for TMDB's details, and the background refresher |
| `app/tmdb.py` | Fetches a movie's details from TMDB, with the read access token |
| `app/config.py` | The typed settings |
| `app/media_hooks.py` | A separate app: the upload hooks tusd calls, as `veloraug_media`. See [uploads](#uploads) |
| `app/upload_keys.py` | How upload keys are made and hashed |
| `app/media_worker.py` | A separate program: checks uploads and converts them to HLS. See [convert uploads](#convert-uploads) |
| `migrations/` | Alembic and the hand-written SQL migrations. Not in the image |
| `alembic.ini` | Alembic's settings. It holds no connection string |
| `scripts/` | The owner's scripts: [create the API's role](#2-create-the-apis-role), [check the database](#4-check-it) [manage the catalogue](#catalogue) and [upload keys](#upload-keys), and check the media role. Not in the image |
| `tests/` | Tests for the endpoints, token checks, database rules, migrations, the catalogue, TMDB, CORS, settings, upload keys, the upload hooks and the upload script. `tests/db_support.py` sets up the local test database |
| `requirements.txt` | Exact versions of the packages needed to run the API |
| `requirements-migrate.txt` | The above, plus the migration tools |
| `requirements-dev.txt` | All of the above, plus the test and lint tools |
| `pyproject.toml` | Settings for pytest and Ruff |
| `Dockerfile`, `.dockerignore` | How to build the container image, and which files it may contain |
| `Dockerfile.worker` | The media worker's image: the same code, plus FFmpeg |

An **application factory** is a function that builds the app when called. It lets each test build an app with its own settings. That is why the start command has `--factory`.

## Settings

Only `VELORAUG_DATABASE_URL` and `VELORAUG_TMDB_READ_ACCESS_TOKEN` are secret. The defaults suit local development, without sign-in or a database.

| Environment variable | Default | Meaning |
| --- | --- | --- |
| `VELORAUG_ENVIRONMENT` | `development` | `development` or `production`. Production refuses to start without the sign-in settings and the database |
| `VELORAUG_ALLOWED_ORIGINS` | `["http://localhost:8765"]` | Browser origins allowed to read responses, written as a JSON list |
| `VELORAUG_NEON_AUTH_URL` | None | The exact Auth URL of the Neon branch. Tokens must name it as issuer, and the public keys are fetched from it |
| `VELORAUG_API_RESOURCE` | None | The audience a token must contain, such as `https://api-dev.veloraug.invalid` |
| `VELORAUG_NEON_AUTH_CLIENT_IDS` | None | The web and Android client IDs allowed to call the API, as a JSON list |
| `VELORAUG_DATABASE_URL` | None | **Secret.** The pooled connection as `veloraug_app`. [The role script](#2-create-the-apis-role) writes it. Any other role is refused |
| `VELORAUG_TMDB_READ_ACCESS_TOKEN` | None | **Secret.** TMDB's API Read Access Token. Used from Step 6B by [the catalogue script](#catalogue), and by the API from Step 6C |

The three sign-in settings go together: set all three or none. Without them, or without the database, `/api/v1/me` answers `503`. Their values for the development branch are in your Git-ignored `services/api/.env`, which Docker Compose passes to the container.

To change one, set it in the terminal before starting the server. It lasts until you close that terminal:

```powershell
$env:VELORAUG_ALLOWED_ORIGINS = '["http://localhost:8765","http://localhost:9000"]'
```

To run directly with Python, with sign-in and the database, load the settings from `.env` into that terminal first. This prints nothing:

```powershell
Get-Content .env | Where-Object { $_ -match '^VELORAUG_(NEON_AUTH_URL|API_RESOURCE|NEON_AUTH_CLIENT_IDS|DATABASE_URL)=' } | ForEach-Object { $name, $value = $_ -split '=', 2; Set-Item "env:$name" $value.Trim('"') }
```

The app refuses to start if a setting is invalid, such as an unknown environment, the wildcard `*`, an origin with a trailing slash, or a database URL for another role. Its error messages never quote a value.

**The app doesn't load `.env` files.** A `.env` file does nothing by itself: a program has to read it, and this app doesn't, which a test confirms. Docker Compose reads `services/api/.env` and passes its values in, and the command above does the same for a terminal. `.env.example` is the template, with fake values.

## Database

The API reads and writes Neon PostgreSQL as its own role, `veloraug_app`, through Neon's connection pooler. That role can read profiles and change only display names, and row-level security limits it to the signed-in user's row. Only migrations change the schema, and the owner runs them with the owner role over a direct connection.

**The owner runs these steps.** They need the owner's database password, which stays in your terminal and never goes into a chat or a file. Each step that needs it asks for the connection string with the input hidden.

### 1. Copy the owner connection string

In the [Neon Console](https://console.neon.tech), open the **`development`** branch, the one with Auth, and choose **Connect**. Pick the `neondb_owner` role and the `neondb` database, and **turn connection pooling off**. Copy the string, but don't paste it anywhere yet. It doesn't matter if it comes wrapped in `psql '…'`.

Use the **Frankfurt** project (`eu-central-1`), not the old `us-east-2` one. The host must be `VELORAUG_NEON_AUTH_URL`'s host without `.neonauth`, such as `ep-floral-salad-b98b3l94.c-7.eu-central-1.aws.neon.tech`.

The scripts refuse a pooled address and `veloraug_app`. They also connect first, and refuse any other host, or a database without Neon Auth's `neon_auth` schema, before changing anything. Each prints `Branch: matches sign-in` before it continues.

### 2. Create the API's role

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\create_app_role.py
```

Paste the owner string when asked: nothing shows as you paste. Check the host it prints, then type `yes`. The script:

- generates a long password for `veloraug_app`, and sends the database only a hash of it,
- checks the role can't bypass row-level security and belongs to no other role, and
- writes the role's pooled connection string to `.env` as `VELORAUG_DATABASE_URL`, replacing the old line.

It never shows the password. Running it again gives the role a new password and updates `.env`, so a lost password is fixed the same way.

### 3. Run the migration

```powershell
.\.venv\Scripts\python.exe -m alembic upgrade head --sql
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m alembic current
```

`upgrade head --sql` needs no connection: it prints the SQL so you can read it first. The other two each ask for the owner string. The upgrade runs in one transaction, so a failure changes nothing. `current` should then show `0003 (head)`: `0001` adds profiles, `0002` adds the catalogue, and `0003` adds upload keys, originals, their qualities and the `veloraug_media` role, without a login yet.

### 4. Check it

```powershell
.\.venv\Scripts\python.exe scripts\check_database.py
```

This connects as `veloraug_app`, using `.env`, and asks for nothing. It checks the role's rights, the grants and row-level security, that one user can't see or change another's row, that the user setting doesn't leak between transactions through the pooler, and that prepared statements work. For the catalogue, it checks that hidden movies can't be seen, and that the API can't add, publish, hide or remove movies, or delete their details. For uploads, it checks that the API can't read or change upload keys, originals or qualities. The tests that write use random user IDs inside a transaction that is rolled back, so they leave nothing behind. Every line should say `PASS`.

**Rules for migrations:**

- Don't change the schema in the Neon Console, because that bypasses migration history.
- Don't edit a migration that has been applied, and don't `downgrade` on Neon. Fix mistakes with a new migration.
- Never touch `neon_auth`. It belongs to Neon.
- New migrations are hand-written SQL in `migrations/versions/`, started with `python -m alembic revision -m "what it does"`.

## Catalogue

The catalogue lists only VeloraUG's own movies. The owner adds each one by its TMDB ID, the number in its themoviedb.org address, such as `550` in `themoviedb.org/movie/550-fight-club`. A new movie is hidden until it is published. See the [catalogue plan](../../docs/step-06a-catalogue-plan.md).

The script needs `VELORAUG_TMDB_READ_ACCESS_TOKEN` in `.env`. It asks for the owner string like the migration does, because the API's role can't change the catalogue, and checks the branch the same way. It never prints the token or the string.

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\catalogue.py add 550 27205
.\.venv\Scripts\python.exe scripts\catalogue.py publish 550
.\.venv\Scripts\python.exe scripts\catalogue.py list
```

Type one command at a time. If several are pasted together, the hidden prompt can read the next line, rather than the string.

| Command | What it does |
| --- | --- |
| `add` and TMDB IDs | Fetches every movie from TMDB first and shows its title and year. Then it asks for the owner string, and for `yes`, and adds them all, hidden. If one is already added, nothing changes |
| `publish`, `unpublish` and movies | Shows or hides them in the app. A movie is its TMDB ID, or the VeloraUG ID from `list`. If one isn't found, nothing changes |
| `list` | Every movie, published first, with how old its TMDB details are |
| `refresh` | Fetches details older than 7 days again. Details that can't be fetched are deleted at 180 days |
| `purge-tmdb` | Deletes every copy of TMDB's details and hides every movie, after you type `purge`. For when the TMDB licence ends |

**TMDB's terms forbid keeping its data for more than 6 months.** The API refreshes details older than 7 days itself, after answering, as long as `VELORAUG_TMDB_READ_ACCESS_TOKEN` is set. It never shows details older than 150 days. If the API isn't running for a long time, run `refresh` at least once a month.

## Uploads

### Upload keys

The owner and trusted uploaders upload movie files with one-time **upload keys**. A key lets whoever holds it upload one file for one movie. It expires after 7 days unless `--days` says otherwise, from 1 to 30. Only its SHA-256 is stored, so it is shown once, when it is made. See the [uploads plan](../../docs/step-07a-uploads-plan.md).

```powershell
.\.venv\Scripts\python.exe scripts\catalogue.py grant-upload 550 --for "Kampala Films"
.\.venv\Scripts\python.exe scripts\catalogue.py uploads
```

| Command | What it does |
| --- | --- |
| `grant-upload` movie `--for` who `[--days 7]` | Makes a key for one upload to the movie, which needn't be published, and prints it once. Send it privately |
| `revoke-upload` key ID | Stops a key working. A key already used stays used |
| `uploads [movie]` | Every key, newest first, with who it was for, whether it is unused, used, expired or revoked, and its original's state, size, resolution, format, the qualities made from it and any reason it was refused. Never the key itself |

### Start the upload services

Uploads go to **tusd**, which resumes an upload after a dropped connection. Before accepting one, tusd asks the **upload hooks**, a separate small app in this folder, [`app/media_hooks.py`](app/media_hooks.py), which checks the key as `veloraug_media`. Both run in Docker, from the [local Compose file](../../infra/compose.local.yaml), with the `uploads` profile.

Once, as the owner, give `veloraug_media` a login. Like the API's role script, it asks for the owner string and for `yes`, and saves the role's connection string in `services/api/.env.media`, never in `.env`, so the API's container never holds it:

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\create_app_role.py --role media
.\.venv\Scripts\python.exe scripts\check_media_role.py
```

`check_media_role.py` asks for nothing, changes nothing, and should print **14 PASS**: the role has no special rights, and can't make, revoke or read the label of keys, delete keys or originals, read movies, TMDB details or profiles, publish movies or change the schema.

Then, with Docker Desktop running:

```powershell
cd C:\Users\Wilsoft\veloraug
docker compose -f infra/compose.local.yaml --profile uploads up -d --build media-hooks tusd
docker compose -f infra/compose.local.yaml --profile uploads ps
docker compose -f infra/compose.local.yaml --profile uploads logs media-hooks
docker compose -f infra/compose.local.yaml --profile uploads stop media-hooks tusd
```

- tusd listens on `http://127.0.0.1:1080/files/`, this computer only. The hooks have no port at all.
- Received files land in `services/worker/uploads/`, which Git ignores. Each is named by its original's ID, beside a `.info` file.
- tusd refuses downloads and deletion. A file over 50 GB, without a declared size, or without a working key is refused before any data arrives.
- The hooks log each upload accepted, received or refused, never a key.

### Upload a file

Anyone with a key, the owner included, uploads with [`tools/veloraug_upload.py`](../../tools/veloraug_upload.py). It needs only Python 3.10 or newer, with no packages, so a trusted uploader needs just that one file:

```powershell
python C:\Users\Wilsoft\veloraug\tools\veloraug_upload.py "C:\Movies\My Film.mp4"
```

It asks for the key, hidden, then shows progress. If the connection drops, it tries again by itself. If it is stopped, or the computer restarts, **run the same command again**: it carries on from where it stopped, without asking for the key, using a small `.veloraug-upload` file beside the movie. That file is deleted at the end. Until then, keep it private: it holds the unfinished upload's address. `--server` points it at another upload address, such as the Oracle server's from Milestone 10.

After the upload, `catalogue.py uploads` shows its original as `received`, then as the worker below takes it.

### Convert uploads

The **media worker**, [`app/media_worker.py`](app/media_worker.py), takes one `received` original at a time:

1. **Checks it with FFprobe.** A file without a video track, one FFprobe can't read, or one smaller than 360 lines and 640 pixels across is `refused`, with a plain reason, and deleted.
2. **Converts it with FFmpeg,** in one run, to every quality from 360p to 1080p that the original can fill, never larger: H.264 video, stereo AAC sound, 6-second chunks, and a keyframe every 2 seconds in every quality, so a player can switch cleanly. A wide film, 1920×800, gets all four. A failed conversion is tried 3 times, then marked `failed` with FFmpeg's last line.
3. **Waits in `publishing`,** with its HLS files in `services/worker/transcoding/<original ID>/`, until Step 7E publishes them to R2.

If the worker is stopped mid-way, it puts the original back in the queue when it starts again. It also receives any finished upload whose `post-finish` hook was missed.

It runs in its own image, `veloraug-media-worker:local`, which is this folder's code plus FFmpeg from Debian, built from [`Dockerfile.worker`](Dockerfile.worker). It uses the same `.env.media` as the hooks, and has no ports. **Build it from the `infra` folder:** run from the repository root, Docker Compose 5.6 asks for an extra permission to read a Dockerfile with another name.

```powershell
cd C:\Users\Wilsoft\veloraug\infra
docker compose -f compose.local.yaml --profile uploads build media-worker
docker compose -f compose.local.yaml --profile uploads up -d media-hooks tusd media-worker
docker compose -f compose.local.yaml --profile uploads logs -f media-worker
```

The worker logs each original it refuses or converts, the qualities made, and how long converting took per second of film.

To check conversion itself with the real FFmpeg, on clips FFmpeg makes, run [`scripts/check_conversion.py`](scripts/check_conversion.py) in the worker's image. Its first lines show how. It should end with `GATE U2: PASSED`.


