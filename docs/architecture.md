# Architecture

This is the approved plan. **None of it is built yet.**

## The parts

| Part | Technology | Job |
| --- | --- | --- |
| App | Flutter/Dart | One app for web and Android |
| Web hosting | Cloudflare Pages | Serves the Flutter web build |
| Backend | Python/FastAPI | Trusted server: access rules, payments, TMDB requests |
| Accounts and database | Supabase | Hosted sign-in and PostgreSQL |
| Movie details | TMDB | Titles, posters and descriptions |
| Uploads | tusd | Uploads that can resume after a dropped connection |
| Media processing | FFmpeg/FFprobe | Inspects movies and converts them to HLS |
| Video storage | Cloudflare R2 | Private storage for published HLS files |
| Video delivery | Cloudflare Worker | Checks access, then serves video from R2 |
| Backend hosting | Docker Compose on Oracle ARM64 | Runs the API, media worker and tusd |
| Payments | Pesapal | Initial payment provider |
| Source archive | Telegram | Optional archive of original files |

**HLS** splits a movie into many small chunks plus a playlist, so a player can start quickly and pick a quality that suits the connection.

## How it fits together

```text
Watching
  Flutter app --> FastAPI: "may I watch this?"
  FastAPI checks the Supabase user and their payment, then grants access
  Flutter app --> Cloudflare Worker: checks the access --> private R2

Publishing
  Upload --> tusd --> media worker (FFprobe, FFmpeg) --> private R2
                                                     --> Telegram (optional)

Paying
  Flutter app --> FastAPI --> Pesapal
  Pesapal --> FastAPI: confirms the payment --> Supabase records it
```

Two rules follow from this design:

- The app is never trusted to decide who has paid. The backend decides.
- R2 stays private. Viewers only reach video through the Worker.

## Where configuration and secrets will live

Nothing here exists yet, and no values are needed now.

**Public configuration** is safe for anyone to see, because anything built into a web or Android app can be extracted by its users.

| Value | Later location |
| --- | --- |
| API address, Worker address | Flutter build settings (`--dart-define-from-file`), using an ignored `dart_defines*.json` file locally and Cloudflare Pages build settings for the web build |
| Supabase project URL and public client key | Same. The public key is only safe once database access rules (Row Level Security) are in place |

**Secrets** must never reach the Flutter app or Git.

| Value | Later location |
| --- | --- |
| Supabase server key, TMDB key, Pesapal credentials, R2 keys, Telegram token | Local: an ignored `.env` file beside the service that uses it. Production: an `.env` file on the Oracle server, outside Git, readable only by the deployment account |
| Cloudflare Worker secrets | Cloudflare's encrypted Worker secrets. Local: an ignored `.dev.vars` file |
| Android signing key | Outside the repository, with a backup. `key.properties` and key files are ignored |

Each service can commit a `.env.example` file containing variable names and fake values, so others can see what is needed. Create these only when the variables first exist.

## Oracle production images must support ARM64

The Oracle server has an ARM64 processor, while this development machine's Docker engine is `linux/amd64`. An image must match the server's processor type, so every production image needs an ARM64 build. See [infra/README.md](../infra/README.md).

## Cost target

The infrastructure target is **$20/month for a limited pilot**. It is a target, not a guaranteed total project cost, and has not been measured. Video storage, processing load and traffic could change it.
