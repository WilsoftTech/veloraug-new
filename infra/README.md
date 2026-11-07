# Infrastructure

Docker configuration for running the services. Today it holds one thing: a **local development** setup for the API. Nothing has been deployed.

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

The Compose file passes the settings in `services/api/.env` to the container, if that file exists. That is how the API gets its sign-in settings. Without the file, the app's defaults apply: `development`, with `http://localhost:8765` as the allowed origin and no sign-in, so `/api/v1/me` answers `503`. Variables set in your terminal do **not** reach the container. The app itself never reads `.env`, and the image never contains it. The settings are listed in the [API README](../services/api/README.md#settings).

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

## This is not a production setup

The address `127.0.0.1` is for local development only. **Do not use `compose.local.yaml` on the Oracle server:** it would keep the API unreachable from outside that server, and the deployment needs decisions this file doesn't make.

Still missing before any deployment, among other things:

- An ARM64 image that has been built and run
- HTTPS, and a decision on how traffic reaches the API
- Production settings, including allowed origins and whether `/docs` stays public
- Secret handling, logging, restart behaviour and resource limits

## Oracle images must support ARM64

The production server uses an ARM64 processor. This Windows machine's Docker engine reports `linux/amd64`, so an image built here is **not** the right type for production.

The Dockerfile and Compose file deliberately name no processor type, so Docker builds for whichever machine runs them. Don't add `platform: linux/amd64` to shared configuration.

Every production image must have an ARM64 build, including base images and our own. For the API, the base image and all pinned Python packages are available for ARM64, but **no ARM64 image has been built or run**. See the [Step 4B report](../docs/step-04b-report.md#arm64-checked-not-run). FFmpeg and tusd need checking too.

## Planned

| Planned item | Purpose |
| --- | --- |
| Oracle Docker Compose file | Runs the API, media worker and tusd on the Oracle server |
| Dockerfiles or build notes | Build the images for the other services |
| Cloudflare Worker deployment notes | Protected media delivery. The code and its configuration will live in [`services/media_gateway/`](../services/media_gateway/README.md) |
| Cloudflare Pages notes | Hosting for the Flutter web build |
| `.env.example` | Variable names with fake values, created when a service first reads a `.env` file |
