# Step 4B report: API container

Date: 3 November 2026. This completes the Docker item in Milestone 4 of the [roadmap](roadmap.md), for local Linux AMD64 only. Milestone 4 stays **open**, because the Flutter app is not connected yet.

Tools: Docker engine 29.9.2 (`linux/amd64`), Docker Compose v5.6.1, Windows 11. Base image: `python:3.13-slim-trixie`, which was Python 3.13.18 at the time.

## Status at a glance

| Item | Status |
| --- | --- |
| Linux AMD64 build and run | **Passed** |
| ARM64 base image and package availability | **Confirmed available** |
| ARM64 build or run | **NOT EXECUTED** |
| Flutter integration | Pending |
| Android device execution | **NOT TESTED**, unchanged by this step |
| Production readiness | **Not production-ready** |

## What was built

- `services/api/Dockerfile`: installs only `requirements.txt`, runs as the non-root user `veloraug`, and starts Uvicorn through the existing application factory on `0.0.0.0:8000`, with no reload mode. It sets no platform.
- `services/api/.dockerignore`: excludes everything, then allows only `requirements.txt` and `.py` files under `app/`.
- `infra/compose.local.yaml`: one service, `api`, published on `127.0.0.1:8000`, with a health check using Python's standard library. It has no volumes, no platform and no settings, so the app's own defaults apply.

The commands and concepts are explained in [infra/README.md](../infra/README.md).

### Decisions

- **`3.13-slim-trixie`, not `3.13-slim`.** Both pointed to the same image (`sha256:ae14d4ce…85d1`) when checked. Naming the Debian release stops a future Debian version from arriving unnoticed. The tag still receives Python and security updates, so the base image is not locked to one exact build.
- **An allowlist in `.dockerignore`.** The first version listed what to exclude, and testing showed that `app/clip.MKV` got through, because the patterns are case-sensitive and listed lowercase extensions only. An allowlist has no such gap and also covers anything added later.

## Verification results

All results are for the final Dockerfile, ignore file and Compose file.

| Check | Command | Result |
| --- | --- | --- |
| API formatting | `ruff format --check .` | Passed, 9 files |
| API lint | `ruff check .` | Passed |
| API tests | `pytest` | Passed, 26 of 26 |
| Compose file | `docker compose -f infra/compose.local.yaml config` | Valid, exit 0 |
| Build context | Build of a scratch copy with 32 decoy files, exported to a folder | All decoys excluded. Docker received 4 files from `app/` and `requirements.txt` |
| Build | `docker compose -f infra/compose.local.yaml build` | Passed, image `veloraug-api:local`, `linux/amd64`, 202 MB |
| Linux dependency install | During the build | Passed, no fix needed |
| Installed packages | `pip freeze` in the container compared with `requirements.txt` | Identical, 16 packages, no development tools |
| Package consistency | `pip check` in the container | No broken requirements |
| Start and health | `docker compose -f infra/compose.local.yaml up -d`, then `docker inspect` | `healthy` after about 7 seconds |
| Machine type | `uname -m` in the container | `x86_64` |
| Volumes | `docker inspect` | None, so the local `.venv` is not mounted |
| Non-root user | `id` and `/proc/1/status` in the container | `uid=999(veloraug)`, and the app is process 1 |
| App files protected | `touch /srv/api/app/x` as that user | Permission denied |
| Health check can fail | The same Python command against `/nope` | Exit 1, from HTTP 404 |
| Logs | `docker compose -f infra/compose.local.yaml logs api` | Clean startup. No lines matching error, traceback, exception or warning |
| Stability | `docker inspect` | 0 restarts, not killed for lack of memory |
| Shutdown | `docker compose -f infra/compose.local.yaml stop` | Clean, exit code 0, 2.8 seconds |
| Documented commands | `up --build -d`, `ps`, `logs`, `down` | All worked as written |

### HTTP against the container

| Request | Result |
| --- | --- |
| `GET /health` | 200, `{"status":"ok"}` |
| `GET /api/v1` | 200, `{"service":"veloraug-api","api_version":"v1","environment":"development"}` |
| `GET /docs` | 200, HTML containing Swagger UI |
| `GET /openapi.json` | 200, lists `/health` and `/api/v1` |
| `OPTIONS /health` from `http://localhost:8765` | 200, `access-control-allow-origin: http://localhost:8765` |
| `OPTIONS /health` from `https://evil.example` | 400, `Disallowed CORS origin` |
| `GET /health` through this computer's network address, `192.168.1.100` | Connection refused, `curl` exit 7 |

The `/docs` page was checked over HTTP only in this step. It was not opened in a browser.

### After verification

`docker compose down` removed only this project's container and its network, `veloraug-local_default`. Afterwards there were no containers or volumes, the networks were Docker's own three, and port 8000 was free. Docker held no containers, images or volumes before this step. The image `veloraug-api:local` was kept so the next start is quick. No prune was run, and no Docker Desktop setting was changed.

## ARM64: checked, not run

The Oracle server's processor type has not been used for anything yet. These are availability checks only:

| Check | Result |
| --- | --- |
| Base image | `docker buildx imagetools inspect python:3.13-slim` lists `linux/arm64/v8`. This is the same image as `3.13-slim-trixie` |
| Python packages | `pip download` for Linux `aarch64` and Python 3.13 found all 16 pinned versions as ready-made wheels. Nothing was installed or run |
| Compiled packages | Only `pydantic_core` is compiled. It has a `manylinux_2_17_aarch64` wheel |
| Shared configuration | The Dockerfile and Compose file set no platform |

The image built here is AMD64 and will not run natively on the Oracle server. An ARM64 image still has to be built and run, on an ARM64 machine or through emulation, before ARM64 can be called working.

## Not tested

- **Any ARM64 build or run.**
- **A real browser page calling the container across origins.** CORS was checked through its headers with `curl`.
- **The Oracle server, or any deployment.**

## Known limitations

- This setup is not production-ready. See [what is missing](../infra/README.md#this-is-not-a-production-setup).
- The app files in the image show as executable (`-rwxr-xr-x`). Windows has no such file permission, so Docker applies this to files copied from a Windows build. They are still owned by root, and the `veloraug` user cannot change them.
- Running `pip` by hand in the container prints a warning about `/home/veloraug/.cache/pip`, because that user has no home folder. It does not affect the app and does not appear in its logs.
- The build ran with only about 0.3 GB of RAM free before it started. It passed, but Docker alongside the Android emulator or Android Studio may struggle on this machine, as noted in the [Windows setup](setup-windows.md#memory).

## Updates to earlier reports

The Step 4 report lists Docker and Linux as not tested. This report supersedes both of those for AMD64, and the Step 4 report was left as written.
