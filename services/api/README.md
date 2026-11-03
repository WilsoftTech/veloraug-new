# API

The FastAPI backend, written in Python. It will become the trusted part of the system: the app asks it to do things, and it checks whether each request is allowed.

**Today it is only a foundation.** It has two endpoints and no database, sign-in, TMDB, uploads or payments. The Flutter app does not call it yet.

Later it will verify Supabase users, fetch movie details from TMDB, handle Pesapal payments and issue playback access. See the [roadmap](../../docs/roadmap.md).

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

## How the code is laid out

| File | Job |
| --- | --- |
| `app/main.py` | `create_app()`, the application factory: builds the app, applies the settings and adds CORS |
| `app/routes.py` | The two endpoints and the shape of their responses |
| `app/config.py` | The typed settings |
| `tests/` | Tests for the endpoints, CORS and settings |
| `requirements.txt` | Exact versions of the packages needed to run the API |
| `requirements-dev.txt` | The above, plus the test and lint tools |
| `pyproject.toml` | Settings for pytest and Ruff |

An **application factory** is a function that builds the app when called. It lets each test build an app with its own settings. That is why the start command has `--factory`.

## Settings

Both settings are optional and neither is secret. The defaults suit local development.

| Environment variable | Default | Meaning |
| --- | --- | --- |
| `VELORAUG_ENVIRONMENT` | `development` | `development` or `production`. Today it only changes what `/api/v1` reports |
| `VELORAUG_ALLOWED_ORIGINS` | `["http://localhost:8765"]` | Browser origins allowed to read responses, written as a JSON list |

To change one, set it in the terminal before starting the server. It lasts until you close that terminal:

```powershell
$env:VELORAUG_ALLOWED_ORIGINS = '["http://localhost:8765","http://localhost:9000"]'
```

The app refuses to start if a setting is invalid, such as an unknown environment, the wildcard `*`, or an origin with a trailing slash.

**`.env` files are not loaded.** A `.env` file does nothing by itself: a program has to be written to read it, and this one isn't. Creating `services/api/.env` would have no effect, and a test confirms that. There is no `.env.example` for the same reason, as it would suggest a file that does nothing. Add both when the API first needs a secret.

## The concepts, using this service as the example

**Virtual environment.** The `.venv` folder is a private copy of Python's package space for this service only. Installing FastAPI there does not touch the rest of your computer or any other project. It is not in Git. If it ever breaks, delete the folder and repeat [Setup](#setup).

**FastAPI** is the Python framework this service is written with. In `app/routes.py`, `@router.get("/health")` tells it which function answers that address. It also reads the function's type hints to check the response and to generate the `/docs` page.

**Uvicorn** is the server program. FastAPI defines how to answer a request, but something has to listen on the network and pass requests in. That is Uvicorn, and in the start command, `app.main:create_app` tells it to call `create_app` in `app/main.py`.

`--host 127.0.0.1` means only this computer can connect, and `--port 8000` is the door number on it. Together they make the address `127.0.0.1:8000`.

**Endpoint.** An address plus an HTTP method that the service answers. This service has two of its own, both `GET`, which means "read this":

- `GET /health` says that this server process is running and can answer. **It does not check a database or any other service**, because none is connected. An `ok` means only that the process responded.
- `GET /api/v1` says which service this is and which API version it serves. Future endpoints will go under `/api/v1`, so a later `v2` can exist alongside them without breaking older apps.

FastAPI adds `/docs` and `/openapi.json` by itself.

**JSON** is the text format the two endpoints reply in. `{"status":"ok"}` is an object with one field, `status`, whose value is the text `ok`. Python, Dart and most other languages can read it, which is how the Flutter app will understand these replies.

**CORS (Cross-Origin Resource Sharing).** An origin is a scheme, host and port together. A web page at `http://localhost:8765` and this API at `http://127.0.0.1:8000` have different origins, so by default the browser won't let that page read the API's replies. The API can give permission with an `Access-Control-Allow-Origin` header:

- For `http://localhost:8765`, the API sends that header, so the browser lets the page read the reply.
- For `https://evil.example`, the API leaves the header out, so the browser hides the reply from that page.
- Before some requests, the browser asks first with an `OPTIONS` request called a **preflight**. An allowed origin gets `200`, and any other gets `400`.

Here, permission covers one exact origin and only `GET`. The wildcard `*` is refused because it would let every website read the replies. Credentials are off because nothing uses cookies or sign-in yet.

Three details are easy to trip over:

- **CORS is not security for the API itself.** Browsers enforce it. A script or `curl` can still call the API from anywhere, and the server still answers a disallowed `GET`. Access rules will need real sign-in checks.
- **`http://127.0.0.1:8765` is a different origin from `http://localhost:8765`,** even though they reach the same computer, so it is refused.
- **Flutter picks a random web port by default.** When the app is connected in a later step, run it with `flutter run -d chrome --web-port 8765`, or the browser will block it. An Android app is not a browser, so CORS does not apply to it.

## Change a dependency

The pinned files list every package at an exact version, so each install gets the same code. To change them, start from a clean environment:

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
Remove-Item -Recurse -Force .venv
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install fastapi pydantic-settings uvicorn
.\.venv\Scripts\python.exe -m pip freeze
```

Paste that output into `requirements.txt`, under the comments. Then install the tools and freeze again:

```powershell
.\.venv\Scripts\python.exe -m pip install httpx2 pytest ruff
.\.venv\Scripts\python.exe -m pip freeze
```

Put only the lines that are new into `requirements-dev.txt`, under `-r requirements.txt`. Copy and paste instead of using `>`, which can change the file's encoding in Windows PowerShell. Finally, delete `.venv`, repeat [Setup](#setup) and [run the checks](#run-the-checks).
