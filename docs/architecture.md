# Architecture

This is the approved plan. **Only the Flutter app shell and a minimal FastAPI service are built so far.** The service has health and identification endpoints only, and the app calls them only from a development-only connection check. Everything else here is still planned.

## The parts

| Part | Technology | Job |
| --- | --- | --- |
| App | Flutter/Dart | One app for web and Android |
| Web hosting | Cloudflare Pages | Serves the Flutter web build |
| Backend | Python/FastAPI | Trusted server: access rules, payments, TMDB requests |
| Accounts | Neon Auth (Managed Better Auth) | Hosted sign-in. Flutter uses it through OAuth with PKCE |
| Sign-in pages | Vite and React with `@neon/auth`, on Cloudflare Pages | Login, sign-up, reset and consent pages, because Neon has no Flutter SDK and provides no default pages |
| Database | Neon PostgreSQL, in `aws-eu-central-1` (Frankfurt) | Stores app data. Only the backend connects to it, from the Oracle server, which is also in Frankfurt |
| Movie details | TMDB | Titles, posters and descriptions |
| Uploads | tusd | Uploads that can resume after a dropped connection |
| Media processing | FFmpeg/FFprobe | Inspects movies and converts them to HLS |
| Video storage | Cloudflare R2 | Private storage for published HLS files |
| Video delivery | Cloudflare Worker, in `services/media_gateway/` | Checks access, then serves video from R2 |
| Backend hosting | Docker Compose on Oracle ARM64 | Runs the API, media worker and tusd |
| Payments | Pesapal | Initial payment provider |
| Source archive | Telegram | Optional archive of original files |

**HLS** splits a movie into many small chunks plus a playlist, so a player can start quickly and pick a quality that suits the connection.

## How it fits together

```text
Signing in
  Flutter app --> Neon Auth --> sign-in pages: the user signs in and consents
  Neon Auth --> Flutter app: access token and refresh token

Watching
  Flutter app --> FastAPI, with the access token: "may I watch this?"
  FastAPI verifies the token, checks their payment in Neon PostgreSQL, then grants access
  Flutter app --> Cloudflare Worker: checks the access --> private R2

Publishing
  Upload --> tusd --> media worker (FFprobe, FFmpeg) --> private R2
                                                     --> Telegram (optional)

Paying
  Flutter app --> FastAPI --> Pesapal
  Pesapal --> FastAPI: confirms the payment --> Neon PostgreSQL records it
```

Three rules follow from this design:

- The app is never trusted to decide who has paid. The backend decides.
- R2 stays private. Viewers only reach video through the Worker.
- The app never connects to the database. It has no database address or credentials, and Neon's Data API stays off.

Accounts and database are planned in the [Neon plan](step-05a-neon-plan.md), and its first step tests the sign-in route against a real project before other work depends on it.

## Open design tasks

These are undecided, and neither feature exists yet:

- **Upload authorization:** who may upload a movie, and how tusd checks that before accepting a file. To settle before Milestone 7.
- **Playback authorization:** what FastAPI gives the app when it grants access, how the Worker checks it on every video chunk, and when it expires. To settle before Milestone 8.

## Where configuration and secrets will live

Nothing here exists yet, and no values are needed now. The API has two optional settings that are not secret, and it does not load `.env` files yet. See [its README](../services/api/README.md#settings). The Flutter app has one public setting, `API_BASE_URL`, passed with `--dart-define`. See [its README](../apps/client/README.md#the-api_base_url-setting).

**Public configuration** is safe for anyone to see, because anything built into a web or Android app can be extracted by its users.

| Value | Later location |
| --- | --- |
| API address, Worker address | Flutter build settings (`--dart-define-from-file`), using an ignored `dart_defines*.json` file locally and Cloudflare Pages build settings for the web build |
| Neon Auth URL, OAuth client IDs, API resource identifier, sign-in pages address | Same. Public OAuth clients have no client secret. The sign-in pages use the Neon Auth URL only, from an ignored `.env.local` file and Cloudflare Pages settings |

**Secrets** must never reach the Flutter app or Git.

| Value | Later location |
| --- | --- |
| API database connection string, TMDB key, Pesapal credentials, R2 keys, Telegram token | Local: an ignored `.env` file beside the service that uses it. Production: an `.env` file on the Oracle server, outside Git, readable only by the deployment account |
| Migration connection string (database owner) | The owner's terminal, for the length of a migration only. Never in the API's environment |
| Email provider (SMTP) credentials, later | Neon Console only |
| Cloudflare Worker secrets | Cloudflare's encrypted Worker secrets. Local: an ignored `.dev.vars` file |
| Android signing key | Outside the repository, with a backup. `key.properties` and key files are ignored |

Each service can commit a `.env.example` file containing variable names and fake values, so others can see what is needed. Create these only when the variables first exist.

## Oracle production images must support ARM64

The Oracle server has an ARM64 processor, while this development machine's Docker engine is `linux/amd64`. An image must match the server's processor type, so every production image needs an ARM64 build. The local API container runs on `linux/amd64` only, and no ARM64 image has been built or run yet. See [infra/README.md](../infra/README.md).

## Cost target

The infrastructure target is **$20/month for a limited pilot**. It is a target, not a guaranteed total project cost, and has not been measured. Video storage, processing load and traffic could change it.
