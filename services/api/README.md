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
| `app/editions.py` | Drafts, publishing, episode approval and deleting the test films, shared by the owner's script and the admin routes |
| `app/admin.py` | The admin routes, `/api/v1/admin/...`. See [admin](#admin) |
| `app/admin_catalogue.py` | What the admin routes read and write, as `veloraug_editor` |
| `app/matching.py` | Cleaning submitted titles, deciding when TMDB's answer is clear, and suggesting VJ credits |
| `app/viewer.py`, `app/viewer_routes.py` | The viewers' catalogue from Step 9D: VJs, editions, episodes and playback by item |
| `app/images.py` | Image addresses: TMDB's, or the media gateway's for uploaded posters and VJ photos |
| `app/tmdb.py` | Fetches a movie's details from TMDB, with the read access token |
| `app/config.py` | The typed settings |
| `app/media_hooks.py` | A separate app: the upload hooks tusd calls, as `veloraug_media`. See [uploads](#uploads) |
| `app/upload_keys.py` | How upload keys are made and hashed |
| `app/media_worker.py` | A separate program: checks uploads and converts them to HLS. See [convert uploads](#convert-uploads) |
| `app/media_publisher.py` | Publishes converted originals to R2, and removes them. See [publish to R2](#publish-to-r2) |
| `app/playback.py` | Signs playback grants for the media gateway. See [playback](#playback) |
| `migrations/` | Alembic and the hand-written SQL migrations. Not in the image |
| `alembic.ini` | Alembic's settings. It holds no connection string |
| `scripts/` | The owner's scripts: [create the API's role](#2-create-the-apis-role), [check the database](#4-check-it) [manage the catalogue](#catalogue) and [upload keys](#upload-keys), and check the media role. Not in the image |
| `tests/` | Tests for the endpoints, token checks, database rules, migrations, the catalogue, TMDB, CORS, settings, upload keys, the upload hooks, the upload script and playback grants. `tests/db_support.py` sets up the local test database |
| `requirements.txt` | Exact versions of the packages needed to run the API |
| `requirements-migrate.txt` | The above, plus the migration tools |
| `requirements-worker.txt` | `requirements.txt` plus boto3, for the media worker's image only |
| `requirements-dev.txt` | All of the above, plus the test and lint tools |
| `pyproject.toml` | Settings for pytest and Ruff |
| `Dockerfile`, `.dockerignore` | How to build the container image, and which files it may contain |
| `Dockerfile.worker` | The media worker's image: the same code, plus FFmpeg |

An **application factory** is a function that builds the app when called. It lets each test build an app with its own settings. That is why the start command has `--factory`.

## Settings

Only `VELORAUG_DATABASE_URL`, `VELORAUG_EDITOR_DATABASE_URL`, `VELORAUG_TMDB_READ_ACCESS_TOKEN` and `VELORAUG_PLAYBACK_SIGNING_KEY` are secret. The defaults suit local development, without sign-in or a database.

| Environment variable | Default | Meaning |
| --- | --- | --- |
| `VELORAUG_ENVIRONMENT` | `development` | `development` or `production`. Production refuses to start without the sign-in settings, the database and playback |
| `VELORAUG_ALLOWED_ORIGINS` | `["http://localhost:8765"]` | Browser origins allowed to read responses, written as a JSON list |
| `VELORAUG_NEON_AUTH_URL` | None | The exact Auth URL of the Neon branch. Tokens must name it as issuer, and the public keys are fetched from it |
| `VELORAUG_API_RESOURCE` | None | The audience a token must contain, such as `https://api-dev.veloraug.invalid` |
| `VELORAUG_NEON_AUTH_CLIENT_IDS` | None | The web and Android client IDs allowed to call the API, as a JSON list |
| `VELORAUG_DATABASE_URL` | None | **Secret.** The pooled connection as `veloraug_app`. [The role script](#2-create-the-apis-role) writes it. Any other role is refused |
| `VELORAUG_EDITOR_DATABASE_URL` | None | **Secret.** The pooled connection as `veloraug_editor`, for the [admin routes](#admin). `create_app_role.py --role editor` writes it. Without it, the admin routes answer `503` |
| `VELORAUG_TMDB_READ_ACCESS_TOKEN` | None | **Secret.** TMDB's API Read Access Token. Used from Step 6B by [the catalogue script](#catalogue), by the API from Step 6C, and by the admin routes' TMDB searches from Step 9C |
| `VELORAUG_PLAYBACK_SIGNING_KEY` | None | **Secret.** Signs playback grants. The media gateway's `PLAYBACK_SIGNING_KEY` must be the same. At least 32 characters. See [playback](#playback) |
| `VELORAUG_MEDIA_GATEWAY_URL` | None | The media gateway's address, such as `http://127.0.0.1:8787` locally. `https`, except for `127.0.0.1` and `localhost` |

The three sign-in settings go together: set all three or none. Without them, or without the database, `/api/v1/me` answers `503`. The two playback settings go together too, and without them granting playback answers `503`. Their values for the development branch are in your Git-ignored `services/api/.env`, which Docker Compose passes to the container.

To change one, set it in the terminal before starting the server. It lasts until you close that terminal:

```powershell
$env:VELORAUG_ALLOWED_ORIGINS = '["http://localhost:8765","http://localhost:9000"]'
```

To run directly with Python, with sign-in and the database, load the settings from `.env` into that terminal first. This prints nothing:

```powershell
Get-Content .env | Where-Object { $_ -match '^VELORAUG_(NEON_AUTH_URL|API_RESOURCE|NEON_AUTH_CLIENT_IDS|DATABASE_URL|EDITOR_DATABASE_URL|TMDB_READ_ACCESS_TOKEN|PLAYBACK_SIGNING_KEY|MEDIA_GATEWAY_URL)=' } | ForEach-Object { $name, $value = $_ -split '=', 2; Set-Item "env:$name" $value.Trim('"') }
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

`upgrade head --sql` needs no connection: it prints the SQL so you can read it first. The other two each ask for the owner string. The upgrade runs in one transaction, so a failure changes nothing. `current` should then show `0005 (head)`:

- `0001` adds profiles.
- `0002` adds the first catalogue, of TMDB films.
- `0003` adds upload keys, originals, their qualities and the `veloraug_media` role, without a login yet.
- `0004` lets the API see which published movies have a ready original.
- `0005` replaces the catalogue with the VJ catalogue: languages, VJs, source titles, editions, playable items, TMDB candidates and admins, and the `veloraug_editor` role, without a login yet. Today's films move across as test editions **with the same IDs**, so their videos in R2, their grants and their unused keys keep working. See the [VJ catalogue plan](../../docs/step-09a-vj-catalogue-plan.md#1-database).

### 4. Check it

```powershell
.\.venv\Scripts\python.exe scripts\check_database.py
```

This connects as `veloraug_app`, using `.env`, and asks for nothing. It checks the role's rights, the grants and row-level security, that one user can't see or change another's row, that the user setting doesn't leak between transactions through the pooler, and that prepared statements work. For the catalogue, it checks that drafts, hidden editions and what only they use can't be seen, and that the API can't add, publish, hide or remove editions or episodes, or add or delete sources, VJs, languages or admins. For uploads, it checks that the API can't read or change upload keys or qualities, and that of originals it reads only the ID, item and state of ready ones of published, approved items, and changes none. The tests that write use random user IDs inside a transaction that is rolled back, so they leave nothing behind. Every line should say `PASS`.

**Rules for migrations:**

- Don't change the schema in the Neon Console, because that bypasses migration history.
- Don't edit a migration that has been applied, and don't `downgrade` on Neon. Fix mistakes with a new migration.
- Never touch `neon_auth`. It belongs to Neon.
- New migrations are hand-written SQL in `migrations/versions/`, started with `python -m alembic revision -m "what it does"`.

## Catalogue

VeloraUG streams **Luganda-translated movies and series by Ugandan VJs**. A **source title**, usually from TMDB, can have several **VJ editions**. A movie edition has one **playable item**; a series edition has one per episode. Upload keys and videos belong to items. An edition starts as a **draft**, before its video is uploaded, and is published once it has a ready video, details, a chosen poster and a confirmed VJ credit. See the [VJ catalogue plan](../../docs/step-09a-vj-catalogue-plan.md).

From Step 9C, admins do this in the app. The owner's script does it too, and some things only the owner can: adding the first admin, and deleting the test films. It asks for the owner string like the migration does, and checks the branch the same way. It never prints the TMDB token or the string.

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\catalogue.py list
.\.venv\Scripts\python.exe scripts\catalogue.py draft movie "Fast X" --year 2023
.\.venv\Scripts\python.exe scripts\catalogue.py admin add <user id>
```

Type one command at a time. If several are pasted together, the hidden prompt can read the next line, rather than the string.

| Command | What it does |
| --- | --- |
| `list` | Every edition, published first: its kind, state, VJ, language, where its details came from and whether its video is ready |
| `draft movie` title `[--year]` | Starts a movie edition's draft and prints its item's ID, for `grant-upload` |
| `draft series` title `--season` n `--episode` n | Starts a series edition with its first episode |
| `draft episode --series` edition `--season` n `--episode` n | Adds an episode to a series edition |
| `publish`, `unpublish` and edition IDs | Shows or hides them in the app. Publishing says what is missing, if anything, and shows a series' ready episodes. If one fails, nothing changes |
| `refresh` | Fetches TMDB details older than 7 days again. Details that can't be fetched are cleared at 180 days, and what shows them is hidden |
| `purge-tmdb` | Clears every copy of TMDB's details and hides what shows them, after you type `purge`. Typed-in details stay. For when the TMDB licence ends |
| `admin add`, `admin remove` user ID, `admin list` | Names who may use the admin screens. The last admin can't be removed. The user ID is Neon Auth's, in the Neon Console under **Auth**, **Users** |
| `delete-test-films` | Deletes the films from before Milestone 9, after you type `delete`. The first run hides them and has the media worker remove their videos from R2; run it again once `uploads` shows them removed |

**TMDB's terms forbid keeping its data for more than 6 months.** The API refreshes details older than 7 days itself, after answering, as long as `VELORAUG_TMDB_READ_ACCESS_TOKEN` is set. It never shows details older than 150 days. If the API isn't running for a long time, run `refresh` at least once a month.

## Admin

From Step 9C, admins run the catalogue from the app: drafts and upload keys, TMDB, posters, VJ credits and publishing. See the [VJ catalogue plan](../../docs/step-09a-vj-catalogue-plan.md#5-api). Every route under `/api/v1/admin/` needs a signed-in user listed in `public.admins`, checked on every request, and answers `403` to anyone else. The routes connect as their own role, `veloraug_editor`, which can change the catalogue and the admin list, but not profiles, Neon Auth or the schema.

**To set it up, once:** give the editor role a login, then name yourself the first admin. Your user ID is in the Neon Console under **Auth**, **Users**.

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\create_app_role.py --role editor
.\.venv\Scripts\python.exe scripts\catalogue.py admin add <your user id>
```

The first writes `VELORAUG_EDITOR_DATABASE_URL` to `.env`. Restart the API afterwards.

| Route | Does |
| --- | --- |
| `GET /api/v1/admin/me` | `200` for an admin, `403` otherwise. The app shows its Admin menu on `200` |
| `GET`, `POST /api/v1/admin/drafts` | Lists what needs an admin, with what each still needs; starts a draft and answers its upload key, once. Listing also looks up on TMDB, after answering, any draft whose video has become ready |
| `GET`, `PATCH /api/v1/admin/editions/{id}` | One edition, with its episodes, videos, keys and TMDB candidates; changes the title viewers see |
| `POST .../tmdb/search` | Searches TMDB again, with an optional corrected title or year |
| `PUT .../source` | Chooses a TMDB title by ID, or typed-in details |
| `GET .../posters`, `PUT .../poster` | The eligible TMDB posters; chooses one, or an uploaded one |
| `GET`, `PUT .../credit` | Suggested VJs, from the files' names and tags; credits one, or a new one by name |
| `POST .../publish`, `.../hide` | Publishes, or answers `409` with what is missing; hides |
| `POST /api/v1/admin/items/{id}/preview` | A playback address for the item's ready video, published or not |
| `POST /api/v1/admin/items/{id}/approve` | Shows a new episode of a published series |
| `POST /api/v1/admin/items/{id}/keys`, `POST /api/v1/admin/keys/{id}/revoke` | Another upload key, such as for a better copy; stops one |
| `GET`, `POST`, `PATCH /api/v1/admin/vjs` | VJs, with their other spellings, photo and bio |
| `GET`, `POST /api/v1/admin/languages` | Languages editions can be in |
| `GET`, `POST`, `DELETE /api/v1/admin/admins` | Admins. One is added by email: they must have signed in once and confirmed it. The last can't be removed |
| `POST /api/v1/admin/images` | Where to send a poster or VJ photo: see below |

**TMDB.** The submitted title is cleaned of VJ names, "Luganda", quality tags and a year, then searched. A **clear match**, exactly one title the same as the cleaned one and from the year if one is known, fills the details in, with its official trailer, and its poster if it has just one. Otherwise the candidates wait for the admin. If TMDB finds nothing or doesn't answer, the draft waits for a retry, a TMDB ID or typed-in details.

**VJ credit** is only ever suggested: from `VJ` and the words after it in the file's name, its tags (kept by the worker as credit hints) and the submitted title, matched to known VJs and their other spellings. An admin confirms it after previewing the video.

**Adding an admin by email** uses one database function, `verified_user_id`, which reads Neon Auth's user table and answers only the ID of a user with that confirmed email. Only the editor role may call it.

**Uploaded images.** Posters for typed-in details and VJ photos are JPEG, PNG or WebP, up to 2 MB. `POST /api/v1/admin/images` answers a path and an address on the media gateway that accepts that one image for 10 minutes. The browser sends the image there with `PUT`, the gateway checks it and stores it in R2, and the admin then chooses the path as the poster or the photo. The API never holds R2's keys. Images are served publicly by the gateway at `/i/<path>`.

## Uploads

### Upload keys

The owner and trusted uploaders upload video files with one-time **upload keys**. A key lets whoever holds it upload one file for one item: a movie edition, or one episode. It expires after 7 days unless `--days` says otherwise, from 1 to 30. Only its SHA-256 is stored, so it is shown once, when it is made. See the [uploads plan](../../docs/step-07a-uploads-plan.md).

```powershell
.\.venv\Scripts\python.exe scripts\catalogue.py grant-upload <item id> --for "Kampala Films"
.\.venv\Scripts\python.exe scripts\catalogue.py uploads
```

| Command | What it does |
| --- | --- |
| `grant-upload` item `--for` who `[--days 7]` | Makes a key for one upload to the item, which needn't be published, and prints it once. Send it privately. A movie edition's ID works too |
| `revoke-upload` key ID | Stops a key working. A key already used stays used |
| `remove-original` original ID | Deletes an original and its qualities from R2, after you type `remove`. See [publish to R2](#publish-to-r2) |
| `uploads [edition or item]` | Every key, newest first, with who it was for, whether it is unused, used, expired or revoked, and its original's state, size, resolution, format, the qualities made from it and any reason it was refused. Never the key itself |

### Start the upload services

Uploads go to **tusd**, which resumes an upload after a dropped connection. Before accepting one, tusd asks the **upload hooks**, a separate small app in this folder, [`app/media_hooks.py`](app/media_hooks.py), which checks the key as `veloraug_media`. Both run in Docker, from the [local Compose file](../../infra/compose.local.yaml), with the `uploads` profile.

Once, as the owner, give `veloraug_media` a login. Like the API's role script, it asks for the owner string and for `yes`, and saves the role's connection string in `services/api/.env.media`, never in `.env`, so the API's container never holds it:

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\create_app_role.py --role media
.\.venv\Scripts\python.exe scripts\check_media_role.py
```

`check_media_role.py` asks for nothing, changes nothing, and should print **15 PASS**: the role has no special rights, and can't make, revoke or read the label of keys, delete keys or originals, read editions, source details, admins or profiles, publish editions or change the schema.

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

It asks for the key, hidden, then shows progress. If the connection drops, it tries again by itself. If it is stopped, or the computer restarts, **run the same command again**: it carries on from where it stopped, without asking for the key, using a small `.veloraug-upload` file beside the movie. That file is deleted at the end. Until then, keep it private: it holds the unfinished upload's address. `--server` points it at another upload address, such as the Oracle server's from Milestone 11.

After the upload, `catalogue.py uploads` shows its original as `received`, then as the worker below takes it.

### Convert uploads

The **media worker**, [`app/media_worker.py`](app/media_worker.py), takes one `received` original at a time:

1. **Checks it with FFprobe.** A file without a video track, one FFprobe can't read, or one smaller than 360 lines and 640 pixels across is `refused`, with a plain reason, and deleted. The file's own `title`, `artist`, `album_artist`, `comment` and `description` tags are kept as **credit hints**, up to 500 characters, so the admin screens can suggest the VJ.
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

### Publish to R2

With R2 set up, the worker publishes each converted original to a private Cloudflare R2 bucket, [`app/media_publisher.py`](app/media_publisher.py):

1. Uploads every chunk, then each quality's playlist, then the master playlist, so no playlist names a file that isn't there yet. All have a one-year cache time: a path includes the original's ID, so it never changes.
2. Uploads the original to **Infrequent Access**, in 64 MB parts.
3. Checks every object's size in R2.
4. Records the qualities, and marks the original `ready`. If the film already had a ready original, that one is marked `removing` in the same step, and the worker then deletes its files.
5. Deletes the local copies.

A publish that fails is tried again after 1, then 2 minutes, then marked `failed`, with its local files kept. Paths in R2 hold VeloraUG's IDs only: `movies/<movie ID>/<original ID>/…` and `originals/<original ID>`.

**Set up R2, once,** in the Cloudflare dashboard:

1. Sign in, or create an account, at <https://dash.cloudflare.com>. Open **R2 object storage**. Cloudflare asks for an R2 subscription first, through a checkout page. The free allowance still applies.
2. **Create bucket**: name `veloraug-dev`, location hint **Eastern Europe (EEUR)**, default storage class **Standard**. Leave public access off, and don't connect a custom domain or turn on the `r2.dev` address.
3. Back on R2's **Overview**, next to **API Tokens**, choose **Manage**, then **Create Account API token**. Name it `veloraug-dev worker`. Permission **Object Read & Write**, applied to **specific buckets only**, `veloraug-dev`. No expiry needed for development.
4. The next page shows an **Access Key ID** and a **Secret Access Key**, the secret only this once, and the **S3 endpoint**, `https://<account ID>.r2.cloudflarestorage.com`. Copy them straight into a new file, `services/api/.env.r2`, which Git ignores. Never into a message or a commit:

   ```text
   VELORAUG_R2_ENDPOINT=https://<account ID>.r2.cloudflarestorage.com
   VELORAUG_R2_BUCKET=veloraug-dev
   VELORAUG_R2_ACCESS_KEY_ID=<Access Key ID>
   VELORAUG_R2_SECRET_ACCESS_KEY=<Secret Access Key>
   ```

   The dashboard shows the address with `/veloraug-dev` on the end. Either form works: the bucket's name on the end is dropped. Any other path is refused.

Then check it, and restart the worker so it reads the file:

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe scripts\check_r2.py
cd C:\Users\Wilsoft\veloraug\infra
docker compose -f compose.local.yaml --profile uploads up -d --force-recreate media-worker
docker compose -f compose.local.yaml --profile uploads logs media-worker
```

[`check_r2.py`](scripts/check_r2.py) asks for nothing and prints no key. It should print **6 PASS**: a small upload, its size, a 65 MB upload in parts, that it landed in Infrequent Access, that R2 refuses a request without keys, and deleting both. The worker's log should then say it is publishing to `veloraug-dev`.

Only the worker's container gets `.env.r2`. The API's and the hooks' never do.

**To remove an original,** and every quality made from it, from R2:

```powershell
.\.venv\Scripts\python.exe scripts\catalogue.py remove-original <original ID from uploads>
```

It asks you to type `remove`, then marks the original `removing`. The worker deletes its files and marks it `removed`. Infrequent Access still bills an original for 30 days after it was uploaded.

## Playback

Planned in the [playback plan](../../docs/step-08a-playback-plan.md). A signed-in viewer asks for a viewing of one movie:

```text
POST /api/v1/movies/{id}/playback      Authorization: Bearer <access token>

200 {"playlist_url": "<gateway>/v1/<grant>/master.m3u8", "expires_at": "..."}
401 not signed in   404 not published   409 nothing ready   503 busy, or not set up
```

`GET /api/v1/movies/{id}` says `"playable": true` when there is something to watch. Any signed-in viewer may watch, until payments in Milestone 10.

The **grant** names the movie, its ready original and an expiry, 6 hours on, signed with HMAC-SHA256 and `VELORAUG_PLAYBACK_SIGNING_KEY`. It is in the address's path, so every playlist and chunk the player fetches carries it. The media gateway, in [`services/media_gateway/`](../media_gateway/README.md), checks it and serves from private R2. Grants aren't stored, and the log names only the movie: never the viewer, the grant or the address. Anyone holding an address can watch until it expires.

**To set it up locally,** make a key, then put the same key in `.env` here and in `services/media_gateway/.dev.vars`:

```powershell
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

```text
VELORAUG_PLAYBACK_SIGNING_KEY=<the key>
VELORAUG_MEDIA_GATEWAY_URL=http://127.0.0.1:8787
```

**Changing the key** ends every grant at once. The app then asks for new ones by itself. Do this if the key may have leaked, in both places together.

`services/media_gateway/test/grant-vector.json` is one grant, with a test-only key, that both this service's tests and the gateway's check, so the two can't drift apart.

## The concepts, using this service as the example

**Virtual environment.** The `.venv` folder is a private copy of Python's package space for this service only. Installing FastAPI there does not touch the rest of your computer or any other project. It is not in Git. If it ever breaks, delete the folder and repeat [Setup](#setup).

**FastAPI** is the Python framework this service is written with. In `app/routes.py`, `@router.get("/health")` tells it which function answers that address. It also reads the function's type hints to check the response and to generate the `/docs` page.

**Uvicorn** is the server program. FastAPI defines how to answer a request, but something has to listen on the network and pass requests in. That is Uvicorn, and in the start command, `app.main:create_app` tells it to call `create_app` in `app/main.py`.

`--host 127.0.0.1` means only this computer can connect, and `--port 8000` is the door number on it. Together they make the address `127.0.0.1:8000`.

**Endpoint.** An address plus an HTTP method that the service answers. This service's addresses all answer `GET`, which means "read this", and `/api/v1/me` also answers `PATCH`:

- `GET /health` says that this server process is running and can answer. **It does not check the database or any other service.** An `ok` means only that the process responded.
- `GET /api/v1` says which service this is and which API version it serves. Future endpoints will go under `/api/v1`, so a later `v2` can exist alongside them without breaking older apps.
- `GET /api/v1/me` returns the signed-in user's ID, from a verified [access token](#the-concepts-using-this-service-as-the-example), and their display name. The profile is created on first use. `PATCH /api/v1/me` with `{"display_name": "…"}` changes the name, from 1 to 80 characters, and `null` clears it. These are the only endpoints that need a token.
- From Step 9D, the VJ catalogue, needing no sign-in:
  - `GET /api/v1/editions` lists published editions, newest first, as cards: `id`, `kind`, `title`, `year`, `poster_url`, `vj_name` (for the label on the poster), `vj_slug`, `language` and `label`, such as `Luganda · VJ Junior`. Filters: `?kind=movie|series`, `?vj=` a VJ's slug, `?language=`, `?genre=` and `?q=`, which searches titles and VJ names. Paged like `/movies`.
  - `GET /api/v1/editions/{id}` adds the source's title, `overview`, `runtime_minutes`, `genres`, `backdrop_url`, `trailer_url` (YouTube), the VJ's ID and photo, `playable`, and either `item_id`, a movie's video, or `seasons`, each with its approved episodes and their item IDs. `404` and `503` as for `/movies/{id}`.
  - `GET /api/v1/vjs` lists VJs with something published; `GET /api/v1/vjs/{slug}` is a VJ's page, with their bio, movies and series.
  - `GET /api/v1/languages` lists languages with published editions.
  - `POST /api/v1/items/{id}/playback` grants a viewing of one item, a movie's video or one episode, exactly as `/movies/{id}/playback` does. It needs a token.
- `GET /api/v1/movies` lists published movies, newest first: `id`, `title`, `year` and `poster_url`. `?q=` searches titles, 2 to 80 characters, with titles that start with it first. `?limit=` is 1 to 50, 24 by default, and `next_offset` gives the next page's `?offset=`, or `null` on the last.
- `GET /api/v1/movies/{id}` adds `overview`, `runtime_minutes`, `genres` and `backdrop_url`. A movie that doesn't exist and one that isn't published both answer `404`, with the same message. `503` with `Retry-After` means its details are being fetched.

The IDs are VeloraUG's own. TMDB's IDs and token never leave the API, and the image addresses point straight at TMDB's image server.

FastAPI adds `/docs` and `/openapi.json` by itself.

**Access token.** After sign-in, Neon gives the app a short-lived token, valid for an hour, which the app sends as `Authorization: Bearer <token>`. The token is signed by Neon. The API checks the signature with Neon's public keys, which it fetches once and keeps for five minutes, so it makes no request to Neon per call. It also checks who issued the token, which API and which app it is for, and that it hasn't expired. Only then does it trust the user ID inside. Any failure gets the same `401`, and if the keys can't be fetched the answer is `503`. A token stays valid until it expires, even after sign-out: see the [revocation limits](../../docs/step-05a-neon-plan.md#revocation-limits). The full rules are in the [Neon plan](../../docs/step-05a-neon-plan.md#4-token-verification-in-fastapi).

**JSON** is the text format the two endpoints reply in. `{"status":"ok"}` is an object with one field, `status`, whose value is the text `ok`. Python, Dart and most other languages can read it, which is how the Flutter app will understand these replies.

**CORS (Cross-Origin Resource Sharing).** An origin is a scheme, host and port together. A web page at `http://localhost:8765` and this API at `http://127.0.0.1:8000` have different origins, so by default the browser won't let that page read the API's replies. The API can give permission with an `Access-Control-Allow-Origin` header:

- For `http://localhost:8765`, the API sends that header, so the browser lets the page read the reply.
- For `https://evil.example`, the API leaves the header out, so the browser hides the reply from that page.
- Before some requests, the browser asks first with an `OPTIONS` request called a **preflight**. An allowed origin gets `200`, and any other gets `400`.

Here, permission covers one exact origin, the methods `GET` and `PATCH`, and the headers `Authorization` and `Content-Type`. The wildcard `*` is refused because it would let every website read the replies. Credentials are off because the API uses no cookies: the app sends its token in the `Authorization` header.

Three details are easy to trip over:

- **CORS is not security for the API itself.** Browsers enforce it. A script or `curl` can still call the API from anywhere, and the server still answers a disallowed `GET`. The token check is what protects signed-in routes.
- **`http://127.0.0.1:8765` is a different origin from `http://localhost:8765`,** even though they reach the same computer, so it is refused.
- **Flutter picks a random web port by default.** Use the [command in the client README](../../apps/client/README.md#in-chrome-two-terminals), or the browser will block it. An Android app is not a browser, so CORS does not apply to it.

## Change a dependency

The pinned files list every package at an exact version, so each install gets the same code. To change them, start from a clean environment:

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
Remove-Item -Recurse -Force .venv
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install fastapi httpx2 "psycopg[binary,pool]" pydantic-settings "PyJWT[crypto]" uvicorn
.\.venv\Scripts\python.exe -m pip freeze
```

Paste that output into `requirements.txt`, under the comments. Then install the migration tools and freeze again:

```powershell
.\.venv\Scripts\python.exe -m pip install alembic sqlalchemy
.\.venv\Scripts\python.exe -m pip freeze
```

Put only the lines that are new into `requirements-migrate.txt`, under `-r requirements.txt`. Then install the test tools and freeze again:

```powershell
.\.venv\Scripts\python.exe -m pip install pytest ruff
.\.venv\Scripts\python.exe -m pip freeze
```

Put only the lines that are new into `requirements-dev.txt`, under `-r requirements-migrate.txt` and `-r requirements-worker.txt`. Before that, install `boto3` and freeze in the same way, and put its new lines into `requirements-worker.txt`. Copy and paste instead of using `>`, which can change the file's encoding in Windows PowerShell. Finally, delete `.venv`, repeat [Setup](#setup) and [run the checks](#run-the-checks).
