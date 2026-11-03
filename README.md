# VeloraUG

A movie platform with one Flutter app for web and Android, and a Python backend.

**Status: early development.** Only the Flutter app shell and a minimal API exist, joined by a development-only connection check. There are no movies, accounts or payments yet. The check has passed in a browser, but not yet inside the app on an Android phone. See [docs/roadmap.md](docs/roadmap.md) for what is done and what is planned.

## How the repository is organised

| Folder | What will live there | Status |
| --- | --- | --- |
| `apps/client/` | The Flutter app people use, on web and Android | App shell |
| `services/api/` | The FastAPI backend: the app's trusted server, which handles accounts, payments and access checks | Minimal service: health and identification endpoints only |
| `services/worker/` | Background media processing: turns uploaded movies into streamable video | Placeholder |
| `services/media_gateway/` | The Cloudflare Worker: checks access, then delivers video to viewers | Placeholder |
| `infra/` | Docker and cloud configuration | Local Docker setup for the API only |
| `docs/` | Architecture, roadmap, Windows setup and step reports | Written |

Why separate the API and the worker? Converting a movie can take a long time and uses a lot of CPU. Keeping that work apart means the API stays responsive while a movie is processing.

## Read next

- [docs/architecture.md](docs/architecture.md): how the parts fit together, and where configuration and secrets go
- [docs/roadmap.md](docs/roadmap.md): milestones, and what is still unverified
- [docs/setup-windows.md](docs/setup-windows.md): preparing a Windows development machine
- [infra/README.md](infra/README.md): running the API in Docker

## Secrets

Never commit real keys or passwords. No environment variables or third-party accounts are needed yet. See [where configuration lives](docs/architecture.md#where-configuration-and-secrets-will-live).
