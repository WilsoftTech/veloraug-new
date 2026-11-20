# Infrastructure

Docker configuration for running the services. [`compose.local.yaml`](compose.local.yaml) is for development on this PC: the API, and, behind the `uploads` profile, tusd, the upload hooks and the media worker. [`compose.prod.yaml`](compose.prod.yaml) is for the Oracle server, Milestone 11: see [Production](#production) and the [pilot deployment plan](../docs/step-11a-pilot-deployment-plan.md).

## Run the API in Docker

Docker Desktop must be running. Run every command from the repository root, in PowerShell:

```powershell
cd C:\Users\Wilsoft\veloraug
```

| Task | Command |
| --- | --- |
| Check the Compose file | `docker compose -f infra/compose.local.yaml config` |
| Build the image | `docker compose -f infra/compose.local.yaml build` |
| Start the API in the background | `docker compose -f infra/compose.local.yaml up -d` |
| Rebuild and start, after changing code or pins | `docker compose -f infra/compose.local.yaml up --build -d` |
| See status and health | `docker compose -f infra/compose.local.yaml ps` |
| Read the logs | `docker compose -f infra/compose.local.yaml logs api` |
| Follow the logs live (`Ctrl+C` stops following, not the API) | `docker compose -f infra/compose.local.yaml logs -f api` |
| Stop and remove this project's container | `docker compose -f infra/compose.local.yaml down` |

After starting, wait until `ps` shows `(healthy)`. It takes about 10 seconds. Then open:

- <http://127.0.0.1:8000/health>
- <http://127.0.0.1:8000/api/v1>
- <http://127.0.0.1:8000/docs>
- <http://127.0.0.1:8000/openapi.json>

Good to know:

- The log line `Uvicorn running on http://0.0.0.0:8000` describes the inside of the container. From Windows, use `127.0.0.1:8000`.
- Port 8000 can only serve one program. Stop the API running from `.venv` before starting the container, and the other way round.
- `down` keeps the image, so the next start is quick. To remove it as well, run `docker image rm veloraug-api:local`.
- Code changes need a rebuild. There is no live reload, because the code is copied into the image.

### Settings

The Compose file passes the settings in `services/api/.env` to the container, if that file exists. That is how the API gets its sign-in settings. Without the file, the app's defaults apply: `development`, with `http://localhost:8765` as the allowed origin and no sign-in, so `/api/v1/me` answers `503`. If `VELORAUG_DATABASE_URL` in that file uses any role other than `veloraug_app`, the container refuses to start: run the [role script](../services/api/README.md#2-create-the-apis-role) to replace it. Variables set in your terminal do **not** reach the container. The app itself never reads `.env`, and the image never contains it. The settings are listed in the [API README](../services/api/README.md#settings).

## The concepts, using this service as the example

**Image.** A packaged, read-only snapshot containing everything needed to run the API: Linux files, Python, the pinned packages and the code in `app/`. `veloraug-api:local` is ours. Think of it as an installer that never changes.

**Container.** A running copy of an image, isolated from the rest of your computer. It has its own files and processes, so it does not use your `.venv` or your installed Python. Removing a container does not remove the image it came from.

**Dockerfile.** The recipe for building an image. [`services/api/Dockerfile`](../services/api/Dockerfile) starts from Python 3.13, installs `requirements.txt`, copies `app/`, switches to a user without administrator rights, and states the command that starts Uvicorn.

**`.dockerignore`.** Decides which files Docker may see at all while building. [Ours](../services/api/.dockerignore) excludes everything except `requirements.txt` and the Python files in `app/`, so `.venv`, secrets and media can't end up in the image by accident.

**Compose.** A file describing how to run containers, so you don't have to remember long commands. [`compose.local.yaml`](compose.local.yaml) says which image to build, which port to publish and how to check health. It has only one service today, and more can be added later.

**Port mapping.** A container has its own private network, so Windows can't reach it until a port is published. The line `127.0.0.1:8000:8000` has three parts:

```text
127.0.0.1 : 8000 : 8000
    |        |      |
    |        |      port inside the container, where Uvicorn listens
    |        port on Windows
    only this computer may connect
```

This is why Uvicorn binds to `0.0.0.0` inside the container: traffic arrives from outside the container's own network, so binding to `127.0.0.1` in there would refuse it. The `127.0.0.1` in the Compose file is what keeps the API private to this computer.

**Health check.** Every 10 seconds, Docker runs a short Python command inside the container that requests `/health`. An HTTP error or no response counts as a failure, and `ps` shows `(unhealthy)` after 3 failures in a row. As with `/health` itself, `healthy` only means the process is answering.

## Production

One Oracle server, ARM64, Ubuntu 24.04, in Frankfurt, runs [`compose.prod.yaml`](compose.prod.yaml): the API, the upload hooks, tusd, the media worker and a Cloudflare Tunnel. **No port is published.** The tunnel connects outwards to Cloudflare, which sends `api.veloraug.com` to `http://api:8000` and `upload.veloraug.com` to `http://tusd:8080`. Only SSH answers on the server's own address. Images are built on the server, so they are ARM64 without cross-building.

**Never use `compose.local.yaml` on the server, or `compose.prod.yaml` on this PC.**

### On the server

| Path | What |
| --- | --- |
| `/opt/veloraug/repo` | The Git checkout of `main`, cloned with a read-only deploy key |
| `/opt/veloraug/env/*.env` | The settings, mode 600, readable by `ubuntu` only. Never in Git. Keep a copy in your password manager |
| `/opt/veloraug/uploads` | tusd's files, owned by 1000:1000, the IDs tusd and the media worker run as |
| `/opt/veloraug/output` | Converting |
| `/opt/veloraug/deployed-commit` | The commit last deployed, written by `deploy.sh` |

[`server-setup.sh`](server-setup.sh) makes all of these once. It's safe to run again: it never overwrites a settings file.

### The settings files

Each container gets only the files it needs. Every value is production's own: never copy development's keys, which are separate on purpose.

| File | Read by | What goes in it |
| --- | --- | --- |
| `api.env` | `api` | As [`services/api/.env.example`](../services/api/.env.example), with production values: `VELORAUG_ALLOWED_ORIGINS=["https://app.veloraug.com"]`, the default branch's Neon Auth URL and client IDs, `veloraug_app`'s and `veloraug_editor`'s pooled connections to the default branch, the production signing key, `VELORAUG_MEDIA_GATEWAY_URL=https://media.veloraug.com`, `VELORAUG_PUBLIC_API_URL=https://api.veloraug.com`, `VELORAUG_PASSES_REQUIRED=false`. `VELORAUG_ENVIRONMENT=production` is set by the Compose file |
| `media.env` | `media-hooks`, `media-worker` | `VELORAUG_MEDIA_DATABASE_URL`: `veloraug_media`'s pooled connection to the default branch |
| `r2.env` | `media-worker` | `VELORAUG_R2_ENDPOINT`, `VELORAUG_R2_BUCKET=veloraug`, and a key pair that can write that bucket only |
| `tunnel.env` | `cloudflared` | `TUNNEL_TOKEN=`, from the tunnel's page in the Cloudflare dashboard |

To edit one: `nano /opt/veloraug/env/api.env`, then deploy again. Paste values in the editor on the server, never in a chat or a message.

### Deploy

Over SSH, from this PC:

```powershell
ssh -i $HOME\.ssh\veloraug_server.key ubuntu@130.61.208.54
bash /opt/veloraug/repo/infra/deploy.sh
```

[`deploy.sh`](deploy.sh) checks the settings files, pulls `main`, builds, restarts what changed, waits for the API to be healthy and checks `https://api.veloraug.com/health` through the tunnel. It never runs migrations. If the pull brings a new migration, it stops before restarting anything: run the migration on production from your own terminal, as for development, then run `deploy.sh --migrated`. `--no-pull` rebuilds what is already checked out.

| Task | Command, on the server, in `/opt/veloraug/repo` |
| --- | --- |
| Status and health | `docker compose -f infra/compose.prod.yaml ps` |
| An API's logs | `docker compose -f infra/compose.prod.yaml logs --tail 100 api` |
| Follow the worker | `docker compose -f infra/compose.prod.yaml logs -f media-worker` |
| Restart one service | `docker compose -f infra/compose.prod.yaml restart api` |
| Disk space | `df -h /` |

Logs are rotated by Docker: five files of 20 MB per service. Every service restarts by itself, after a crash or a reboot.

### Copy films to production

[`copy_to_production.py`](../services/api/scripts/copy_to_production.py), Step 11F, copies each published, non-test edition from development to production: its rows with the same IDs, and its files inside R2 from `veloraug-dev` to `veloraug`, without downloading them. It is run on this PC, from `services/api`, with both **owner** connections (direct, not pooled) set in the terminal only:

```powershell
$env:VELORAUG_COPY_FROM_DATABASE_URL = Read-Host "Development owner connection"
$env:VELORAUG_COPY_TO_DATABASE_URL = Read-Host "Production owner connection"
.\.venv\Scripts\python.exe scripts\copy_to_production.py           # lists only
.\.venv\Scripts\python.exe scripts\copy_to_production.py --apply   # copies
```

The R2 keys in `services/api/.env.r2` must be able to read `veloraug-dev` and write `veloraug` for the copy. It refuses the same database twice, and databases at different migrations. Each film's files are checked by size before its rows are added, and a film already on production is skipped, so it can be run again safely.

## Oracle images must support ARM64

The server is ARM64; this PC's Docker builds `linux/amd64`. The Dockerfiles and Compose files name no processor type, so each machine builds for itself. Don't add `platform: linux/amd64` to shared configuration. tusd `v2.10.1` and cloudflared `2026.11.1` have ARM64 images, checked on the server on 20 November 2026. Whether our own images build and pass the tests there is gate P2.
