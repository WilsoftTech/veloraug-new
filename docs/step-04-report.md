# Step 4 report: FastAPI backend foundation

Date: 3 November 2026. This is the first part of Milestone 4 in the [roadmap](roadmap.md). Milestone 4 is **not complete**.

Tools: Python 3.13.14 (Microsoft Store install), pip 26.1.2, FastAPI 0.162.0, Uvicorn 0.54.0, Windows 11.

## How this step maps to the roadmap

The step and milestone numbers match, but the scope differs. Milestone 4 also lists running the API in Docker and connecting the Flutter app, and both were outside this step. They stay open in the roadmap, and no milestones were renumbered.

## What was built

- A FastAPI service in `services/api/`, with an application factory, typed settings and its own `.venv`.
- `GET /health`, which returns HTTP 200 and `{"status":"ok"}`. It reports only that the process can answer, and checks no database or external service.
- `GET /api/v1`, which returns `{"service":"veloraug-api","api_version":"v1","environment":"development"}`.
- FastAPI's generated `/docs` and `/openapi.json`.
- CORS that allows only `http://localhost:8765`, only `GET`, with credentials off. The settings reject wildcards and malformed origins, so the app will not start with `*`.
- Exact version pins for all 26 packages, using pip with `requirements.txt` and `requirements-dev.txt`.

The API's [README](../services/api/README.md) has the setup, test and startup commands and explains the concepts.

### Decisions

- **No `.env` file support and no `.env.example`.** The defaults work without one, and an example file would suggest a mechanism that does not exist. A test confirms a `.env` file is ignored.
- **Pip, not a separate tool.** It is already installed, so no global tool was added.
- **`httpx2`, not `httpx`, for the test client.** The first run used `httpx` and Starlette warned that it is deprecated for this use. Starlette's documentation names `httpx2`, and its source repository is under the `pydantic` organisation. The warning is gone since the switch.

## Verification results

All results are for the final code. The environment was deleted and rebuilt from the pin files first.

| Check | Command | Result |
| --- | --- | --- |
| Clean install | `.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt` | Passed |
| Installed versions match pins | `pip freeze` compared with both files | Identical, 26 packages |
| Dependency consistency | `pip check` | No broken requirements |
| Runtime pins without dev tools | Install `requirements.txt` in a separate environment, then import the app and Uvicorn | Passed |
| Formatting | `ruff format --check .` | Passed, 9 files |
| Lint | `ruff check .` | Passed |
| Tests | `pytest` | Passed, 26 of 26, no warnings |

The tests cover endpoint responses, generated documentation, allowed and refused preflights, a `GET` from a refused origin, credentials, settings from environment variables, rejected origins and `.env` being ignored.

To check that the tests can fail, six faults were put into a scratch copy, one at a time. Each one made tests fail:

| Fault | Tests failed |
| --- | --- |
| Wildcard origins | 9 |
| Origin validation turned off | 6 |
| Credentials on | 1 |
| All methods allowed | 1 |
| Wrong health response | 1 |
| `.env` file loaded | 1 |

### Live server

Started with `.\.venv\Scripts\python.exe -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000`, and bound to `127.0.0.1:8000`.

| Request | Result |
| --- | --- |
| `GET /health` | 200, `{"status":"ok"}` |
| `GET /api/v1` | 200, `{"service":"veloraug-api","api_version":"v1","environment":"development"}` |
| `GET /docs` | 200, HTML containing Swagger UI |
| `GET /openapi.json` | 200, lists `/health` and `/api/v1` |
| `OPTIONS /health` from `http://localhost:8765`, using `curl` | 200, `access-control-allow-origin: http://localhost:8765`, no credentials header |
| `OPTIONS /health` from `https://evil.example`, using `curl` | 400, `Disallowed CORS origin`, no `access-control-allow-origin` |
| `/docs` in headless Chrome | Rendered, showing both endpoints |

Afterwards only the server process that was started for this check (PID 47444) was stopped. Port 8000 was free and no Uvicorn process remained.

## Not tested

- **A real browser page calling the API across origins.** CORS was checked through its headers, using `curl` and tests that send the same headers. The Flutter app does not call the API yet.
- **Docker.** No image was built and no container was run.
- **Linux.** The pins were generated and tested on Windows only. They need checking when the Docker image is built.
- **Android device execution remains NOT TESTED,** as in the [Step 3 report](step-03-report.md). This step did not change it.

## Known limitations

- `VELORAUG_ENVIRONMENT=production` changes only the text `/api/v1` reports. `/docs` stays public, and nothing here is ready for production.
- The pins are exact versions, not hashes, so they do not verify that a package's contents are unchanged.
- `/docs` loads its scripts from a public CDN, so it needs an internet connection. The API itself does not.

## Correction to the Step 3 report

The Step 3 report says the repository has no remote. That is no longer true: `origin` points to `https://github.com/WilsoftTech/veloraug-new.git`, and `origin/main` was at `ef9fe50` when this step began. The Step 3 report was left as written. This step did not create a remote or push.
