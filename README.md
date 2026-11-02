# VeloraUG

A movie platform with one Flutter app for web and Android, and a Python backend.

**Status: documentation only.** No application code exists yet. See [docs/roadmap.md](docs/roadmap.md) for what is done and what is planned.

## How the repository is organised

| Folder | What will live there | Status |
| --- | --- | --- |
| `apps/client/` | The Flutter app people use, on web and Android | Placeholder |
| `services/api/` | The FastAPI backend: the app's trusted server, which handles accounts, payments and access checks | Placeholder |
| `services/worker/` | Background media processing: turns uploaded movies into streamable video | Placeholder |
| `infra/` | Docker and cloud configuration | Placeholder |
| `docs/` | Architecture, roadmap and Windows setup | Written |

Why separate the API and the worker? Converting a movie can take a long time and uses a lot of CPU. Keeping that work apart means the API stays responsive while a movie is processing.

## Read next

- [docs/architecture.md](docs/architecture.md): how the parts fit together, and where configuration and secrets go
- [docs/roadmap.md](docs/roadmap.md): milestones, and what is still unverified
- [docs/setup-windows.md](docs/setup-windows.md): preparing a Windows development machine

## Secrets

Never commit real keys or passwords. No environment variables or third-party accounts are needed yet. See [where configuration lives](docs/architecture.md#where-configuration-and-secrets-will-live).
