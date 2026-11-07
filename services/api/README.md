# API

The FastAPI backend, written in Python. It will become the trusted part of the system: the app asks it to do things, and it checks whether each request is allowed.

**Today it handles sign-in and profiles.** It has two public endpoints, and `/api/v1/me`, which checks Neon Auth access tokens and reads or changes the signed-in user's profile in Neon PostgreSQL. It has no TMDB, uploads or payments yet. The Flutter app calls it only from a [development-only connection check](../../apps/client/README.md#connect-to-the-local-api).

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
.\.venv\Scripts\python.exe -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000
```

Leave that terminal open, then open these in a browser:

| Address | What you should see |
| --- | --- |
| <http://127.0.0.1:8000/health> | `{"status":"ok"}` |
| <http://127.0.0.1:8000/api/v1> | `{"service":"veloraug-api","api_version":"v1","environment":"development"}` |
| <http://127.0.0.1:8000/api/v1/me> | `{"detail":"Not signed in."}`, because a browser address sends no token. Without the [settings](#settings) it says sign-in or the database isn't set up |
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
| `app/config.py` | The typed settings |
| `migrations/` | Alembic and the hand-written SQL migrations. Not in the image |
| `alembic.ini` | Alembic's settings. It holds no connection string |
| `scripts/` | The owner's database scripts: [create the API's role](#2-create-the-apis-role) and [check the database](#4-check-it). Not in the image |
| `tests/` | Tests for the endpoints, token checks, database rules, migrations, CORS and settings |
| `requirements.txt` | Exact versions of the packages needed to run the API |
| `requirements-migrate.txt` | The above, plus the migration tools |
| `requirements-dev.txt` | All of the above, plus the test and lint tools |
| `pyproject.toml` | Settings for pytest and Ruff |
| `Dockerfile`, `.dockerignore` | How to build the container image, and which files it may contain |

An **application factory** is a function that builds the app when called. It lets each test build an app with its own settings. That is why the start command has `--factory`.

## Settings

Only `VELORAUG_DATABASE_URL` is secret. The defaults suit local development, without sign-in or a database.

| Environment variable | Default | Meaning |
| --- | --- | --- |
| `VELORAUG_ENVIRONMENT` | `development` | `development` or `production`. Production refuses to start without the sign-in settings and the database |
| `VELORAUG_ALLOWED_ORIGINS` | `["http://localhost:8765"]` | Browser origins allowed to read responses, written as a JSON list |
| `VELORAUG_NEON_AUTH_URL` | None | The exact Auth URL of the Neon branch. Tokens must name it as issuer, and the public keys are fetched from it |
| `VELORAUG_API_RESOURCE` | None | The audience a token must contain, such as `https://api-dev.veloraug.invalid` |
| `VELORAUG_NEON_AUTH_CLIENT_IDS` | None | The web and Android client IDs allowed to call the API, as a JSON list |
| `VELORAUG_DATABASE_URL` | None | **Secret.** The pooled connection as `veloraug_app`. [The role script](#2-create-the-apis-role) writes it. Any other role is refused |

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

`upgrade head --sql` needs no connection: it prints the SQL so you can read it first. The other two each ask for the owner string. The upgrade runs in one transaction, so a failure changes nothing. `current` should then show `0001 (head)`.

### 4. Check it

```powershell
.\.venv\Scripts\python.exe scripts\check_database.py
```

This connects as `veloraug_app`, using `.env`, and asks for nothing. It checks the role's rights, the grants and row-level security, that one user can't see or change another's row, that the user setting doesn't leak between transactions through the pooler, and that prepared statements work. The tests that write use random user IDs inside a transaction that is rolled back, so they leave nothing behind. Every line should say `PASS`.

**Rules for migrations:**

- Don't change the schema in the Neon Console, because that bypasses migration history.
- Don't edit a migration that has been applied, and don't `downgrade` on Neon. Fix mistakes with a new migration.
- Never touch `neon_auth`. It belongs to Neon.
- New migrations are hand-written SQL in `migrations/versions/`, started with `python -m alembic revision -m "what it does"`.

## The concepts, using this service as the example

**Virtual environment.** The `.venv` folder is a private copy of Python's package space for this service only. Installing FastAPI there does not touch the rest of your computer or any other project. It is not in Git. If it ever breaks, delete the folder and repeat [Setup](#setup).

**FastAPI** is the Python framework this service is written with. In `app/routes.py`, `@router.get("/health")` tells it which function answers that address. It also reads the function's type hints to check the response and to generate the `/docs` page.

**Uvicorn** is the server program. FastAPI defines how to answer a request, but something has to listen on the network and pass requests in. That is Uvicorn, and in the start command, `app.main:create_app` tells it to call `create_app` in `app/main.py`.

`--host 127.0.0.1` means only this computer can connect, and `--port 8000` is the door number on it. Together they make the address `127.0.0.1:8000`.

**Endpoint.** An address plus an HTTP method that the service answers. This service has three addresses of its own, all answering `GET`, which means "read this":

- `GET /health` says that this server process is running and can answer. **It does not check the database or any other service.** An `ok` means only that the process responded.
- `GET /api/v1` says which service this is and which API version it serves. Future endpoints will go under `/api/v1`, so a later `v2` can exist alongside them without breaking older apps.
- `GET /api/v1/me` returns the signed-in user's ID, from a verified [access token](#the-concepts-using-this-service-as-the-example), and their display name. The profile is created on first use. `PATCH /api/v1/me` with `{"display_name": "…"}` changes the name, from 1 to 80 characters, and `null` clears it. These are the only endpoints that need a token.

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
.\.venv\Scripts\python.exe -m pip install fastapi "psycopg[binary,pool]" pydantic-settings "PyJWT[crypto]" uvicorn
.\.venv\Scripts\python.exe -m pip freeze
```

Paste that output into `requirements.txt`, under the comments. Then install the migration tools and freeze again:

```powershell
.\.venv\Scripts\python.exe -m pip install alembic sqlalchemy
.\.venv\Scripts\python.exe -m pip freeze
```

Put only the lines that are new into `requirements-migrate.txt`, under `-r requirements.txt`. Then install the test tools and freeze again:

```powershell
.\.venv\Scripts\python.exe -m pip install httpx2 pytest ruff
.\.venv\Scripts\python.exe -m pip freeze
```

Put only the lines that are new into `requirements-dev.txt`, under `-r requirements-migrate.txt`. Copy and paste instead of using `>`, which can change the file's encoding in Windows PowerShell. Finally, delete `.venv`, repeat [Setup](#setup) and [run the checks](#run-the-checks).
