# Roadmap

Last updated: 21 November 2026.

Milestones 1 and 2 match the setup steps already carried out. Milestone 3 is complete: see the [Step 3 report](step-03-report.md). Milestone 4 is complete, through Step 4, the local Docker run in Step 4B and the Flutter connection in Step 4C: see the [Step 4](step-04-report.md), [Step 4B](step-04b-report.md) and [Step 4C](step-04c-report.md) reports. Milestones 5 onward are a proposed order and may change.

## Completed

### Milestone 1: Check the development environment

- [x] Git, Flutter, Dart, Python, pip, Docker CLI and Docker Compose respond
- [x] Docker engine responds
- [x] A Python virtual environment was created, run and removed
- [x] `flutter doctor` reports Android licenses accepted
- [x] Chrome and Edge detected for web testing
- [x] Flutter added to the user PATH

### Milestone 2: Set up the repository and documentation

- [x] Git repository, ignore rules and line-ending rules
- [x] Placeholder folders and documentation

### Milestone 3: Flutter app shell

- [x] Create the app in `apps/client/`
- [x] Run it in Chrome
- [x] Build a debug APK for Android
- [x] Click through every screen by hand in a browser (manually verified and reported by the project owner: see the [Step 3 verification note](step-03-report.md#verification-note-3-november-2026))
- [x] Run it on a phone or emulator (navigation and rotation manually verified and reported by the project owner on a physical phone: see the same note)

### Step 3B: Design system

A first version of the visual design, added after Milestone 3 without renumbering anything. See the [design system](design-system.md) and the [Step 3B report](step-03b-report.md).

- [x] Implementation: shared tokens, Flutter theme and components, restyled screens and sign-in pages, and a development-only showcase
- [x] User visual approval (reported by the project owner on 5 November 2026)
- [x] Phone test (reported as passed by the project owner on 5 November 2026)

### Milestone 4: FastAPI skeleton

- [x] Create the service in `services/api/` with its own virtual environment
- [x] Add a health-check endpoint
- [x] Add a service-identification endpoint at `/api/v1`
- [x] Run it in a local Docker container (Linux AMD64 only)
- [x] Connect the Flutter app to it in a real browser, with a development-only check
- [x] See that check succeed inside the app on an Android phone (manually verified and reported by the project owner on one phone: see the [Step 4C verification note](step-04c-report.md#verification-note-3-november-2026))

## Still unverified

These have **not** been shown to work on this machine:

| Item | Current state | Checked in |
| --- | --- | --- |
| Keyboard use on a phone | Not tested. Tab and Enter controls have been checked in Chrome only | Not scheduled |
| Failure and retry on a phone | Not completed. The check showed a failure once on a phone, but no retry was run. The full cycle has passed in a browser only | Not scheduled |
| Other Android devices | Not tested. No second device has been reported | Not scheduled |
| Real screen reader | Not tested. Automated tests check the labels only | Not scheduled |
| ARM64 image | The base image and pinned packages are available for ARM64, but no ARM64 image has been built or run. The local container is Linux AMD64 | Milestone 11 |

## Open issues

| Issue | Current state | Next action |
| --- | --- | --- |
| `flutter_web_auth_2` applies the Kotlin Gradle Plugin | Open upstream. Stable 5.1.0 still applies it, so every Android build warns, and a future Flutter version will reject it. See [Android build warnings](../apps/client/README.md#android-build-warnings) | Upgrade when 6.0.0 is stable, or sooner if a Flutter upgrade requires it |
| TMDB's free licence doesn't allow commercial use | No agreement. No price is published. See [the licence risk](step-06a-catalogue-plan.md#the-licence-risk) | Describe the project truthfully when applying for the key at 6B. Get a quote from sales@themoviedb.org, and sign or switch to the fallback before charging anyone |

## Planned

### Milestone 5: Accounts and database

Planned in the [Neon plan](step-05a-neon-plan.md), which replaces the superseded [Supabase plan](step-05a-plan.md). The Neon project moved to Frankfurt, next to the Oracle server. Step 5B's gates passed there on one phone and in Chrome and Edge, with some results user-reported: see the [Step 5B report](step-05b-report.md).

- [x] 5B: Set up a Neon development branch and minimal sign-in pages, and test the sign-in route on web and one phone
- [x] 5C: Finish the sign-in pages on Cloudflare Pages (flows user-reported on one phone: see the [Step 5C report](step-05c-report.md))
- [x] 5D: Add sign-in to the Flutter app on web and Android (device and browser tests user-reported on one phone and in Chrome: see the [Step 5D report](step-05d-report.md))
- [x] 5E: Have the API verify signed-in users (automated, plus a container run with the real settings: see the [Step 5E report](step-05e-report.md))
- [x] 5F: Add migrations, the API's database role and database access rules (migration run and all 20 database checks passed on the development branch, user-reported: see the [Step 5F report](step-05f-report.md))
- [x] 5G: Check everything end to end (web, Android and release runs passed, user-reported: see the [Step 5G report](step-05g-report.md))

### Milestone 6: Movie catalogue

Planned in the [catalogue plan](step-06a-catalogue-plan.md). **Complete on 12 November 2026.** The catalogue lists only VeloraUG's own movies, with details from TMDB. TMDB's free licence doesn't cover a paid app: see [the licence risk](step-06a-catalogue-plan.md#the-licence-risk).

- [x] 6A: Plan the catalogue
- [x] 6B: Get a TMDB key, add the catalogue tables and the owner's catalogue script (migration, 25 database checks and four test movies on the development branch, partly user-reported: see the [Step 6B report](step-06b-report.md))
- [x] 6C: Add the API's catalogue routes, with TMDB details kept and refreshed (automated, plus a container run with the real settings: see the [Step 6C report](step-06c-report.md))
- [x] 6D: Add home, search and detail screens, and TMDB's credit (see the [Step 6D report](step-06d-report.md))
- [x] 6E: Check everything end to end (web and Android, signed in and out, unpublish and without the token, user-reported: see the [Step 6E report](step-06e-report.md))

### Milestone 7: Uploads and processing

Planned in the [uploads plan](step-07a-uploads-plan.md). **Complete on 12 November 2026.** The owner and trusted uploaders upload with one-time keys. Each movie is converted to 360p, 480p, 720p and 1080p, never above its original, and the original is kept in R2. Telegram may become a source of movies in a later milestone.

- [x] 7A: Plan uploads and processing, including upload authorization
- [x] 7B: Migration `0003`, the media role, and the owner's upload-key commands (on Neon, 27 database checks pass: see the [Step 7B report](step-07b-report.md))
- [x] 7C: Resumable uploads with tusd, the upload hooks and the upload script (gate U1 passed; a file uploaded against Neon: see the [Step 7C report](step-07c-report.md))
- [x] 7D: Check files with FFprobe and convert them to the four qualities as HLS (gate U2 passed; see the [Step 7D report](step-07d-report.md))
- [x] 7E: Publish to a private R2 bucket, keeping the original (a test clip published to `veloraug-dev`: see the [Step 7E report](step-07e-report.md))
- [x] 7F: Check everything end to end (upload, replacement, refusal, revoked key and removal on Neon and R2, user-run: see the [Step 7F report](step-07f-report.md))

### Milestone 8: Protected playback

Planned in the [playback plan](step-08a-playback-plan.md). Any signed-in viewer may watch a published, ready film, until payments in Milestone 10. 8B to 8D are built and checked on this PC: see the [Step 8B–8D report](step-08-report.md). 8E is mostly done on Neon and Cloudflare; only the bitrate test with a real film is left.

- [x] 8A: Design playback authorization: the API signs a 6-hour grant, and the Worker checks it in every address's path
- [x] 8B: Migration `0004`, the grant route and `playable` (automated, on a local Postgres set up as Neon is)
- [x] 8C: The Worker in `services/media_gateway/` (automated, plus a local `wrangler dev` run: every file served byte-identical, and every way in without a grant refused)
- [x] 8D: The player: hls.js on the web, ExoPlayer on Android (automated, both builds, and seeking checked in hls.js in Chrome against the local Worker)
- [ ] 8E: On Neon and Cloudflare: the migration, the deployed Worker, playback and seeking on web and one phone, a real film's bitrates, and direct access without permission refused
  - [x] Migration `0004` on the Neon development branch (`0004 (head)`, 17 November 2026, user-run)
  - [x] The Worker deployed as `veloraug-media-dev` on `workers.dev`, bound to `veloraug-dev`, with its signing key
  - [x] *The Matrix*'s test clip plays, and seeking works, in Chrome and other browsers and on one Android phone (Galaxy S20, user-reported)
  - [x] Direct access refused: the bucket without credentials and its `r2.dev` address off; a changed, expired or wrongly signed grant `403`; one film's grant for another film, the original file and `../` refused (11 of 11 checks)
  - [ ] A real film's bitrates, using an authorized **translated** film: each quality watched, and the bitrates kept or changed
    - Found with the first real film, 18 November 2026: the fixed bitrates stored a 2.0 Mbit/s film at 6.7 GB, its 1080p at about 4.8 Mbit/s. Every quality is now capped at the original's bitrate, about 4.2 GB for that film. Still to do: watch each quality

### Milestone 9: The VJ catalogue and admin publishing

VeloraUG streams **Luganda-translated movies and series by Ugandan VJs**, browsed by VJ. The catalogue from Milestone 6 is keyed by TMDB film and has no VJs or series, so it is replaced. The upload and playback pipeline is kept, and existing links keep working. Planned in the [VJ catalogue plan](step-09a-vj-catalogue-plan.md), approved on 17 November 2026.

- [x] 9A: Plan VJs, source titles, editions and episodes, upload drafts, TMDB matching, VJ credit and admin publishing
- [x] 9B: Migration `0005`, the editor role, today's films moved across with their IDs, and credit hints from FFprobe (automated, on a local Postgres set up as Neon is; not yet run on Neon)
- [x] 9C: The API's admin routes: drafts and keys, previews, TMDB, VJ credit, publishing, and uploaded posters and VJ photos through the media gateway (automated, on a local Postgres set up as Neon is, with TMDB faked; not yet on Neon or Cloudflare)
- [x] 9D: The API's viewer routes: VJs, editions, episodes, search, playback by item, and TMDB refreshes for series as well as movies (automated, on a local Postgres set up as Neon is)
- [x] 9E: The app: localization set-up, viewer screens with Next Episode, and admin screens on the web. The Milestone 6 `/api/v1/movies` routes removed (widget tests with the API faked; not yet against the real API)
- [ ] 9F: On Neon and Cloudflare: a real translated movie and a two-episode series published through the admin screens and watched on web and one phone
- [ ] 9G: Uploads from the browser: drag and drop many files, read from their names, two at a time with progress, pause, resume, retry and remove, carrying on after a lost connection, a closed tab or a power cut. Built and tested (automated, with tusd faked; tusd's browser settings and delete route checked locally): see the [Step 9G run sheet](step-09g-runbook.md). Not yet checked by hand

### Milestone 10: Payments

Prepaid catalogue passes through Pesapal: since 21 November 2026, **six tiers** with device limits, replacing the daily, weekly and monthly passes for sale. Planned in the [payments plan](step-10a-payments-plan.md), **not yet approved**: written and built on 19 November 2026 at the owner's request to implement Milestone 10. Prices are set by an admin in Settings. Pay per title and automatic renewal come later. Passes are switched on with `VELORAUG_PASSES_REQUIRED`, off by default.

- [x] 10A: Plan passes, payment confirmation and expiry (awaiting the owner's approval)
- [x] 10B: Migration `0006`, the Pesapal API 3.0 client, the pass routes, grants capped at the pass's end and 402 without one, and admin prices (automated tests, with Pesapal faked)
- [x] 10C: The app: Your pass on the Account tab, buying through Pesapal's page, the player's "You need a pass" and "Your pass has ended", and pass prices in admin Settings (widget tests, with the API faked)
- [x] 10D: The [Step 10E run sheet](step-10e-runbook.md) and the docs
- [ ] 10E: One pass in Pesapal's sandbox: payment confirmed by the backend, playback allowed, then refused when the pass expires. Needs the owner: migration `0006` on Neon, sandbox keys, and the run sheet
- [x] 10F (21 November 2026), code only, on branch `feature/milestone-10-subscriptions`, not merged or deployed: the owner-approved **six tiers** (Velora Start, Flex, Prime, Duo, Pro, Max: UGX 6,000 to 150,000, 7 to 365 days, 1 to 3 devices), with `day`, `week` and `month` kept as legacy and off sale. Migration `0007` (forward only, snapshots of what each payment bought, at most three devices and three streams per account enforced by the database), registered devices with server-made credentials, playback sessions with heartbeats, the media gateway checking each session with the API, queued passes by tier, reversals moving queued passes up, checkout retries, per-account rate limits, audit events, Admin → Subscriptions, and the app's plan cards, My membership, My devices and Payments. Automated tests: 592 API (local Postgres, Pesapal faked), 39 Worker, all Flutter widget and unit tests; the web release build compiles. See [Milestone 10 subscriptions](step-10a-payments-plan.md#milestone-10-subscriptions)
- [ ] 10G: Migration `0007` on Neon with the [preflight](step-10e-runbook.md#migration-0007), the Worker with `API_URL` deployed, an Android build on a phone, and the updated [10E run sheet](step-10e-runbook.md) in Pesapal's sandbox, steps 1 to 15
  - [x] On the development branch, 22 November 2026: migration `0007` (preflight 11/11, `check_database.py` 38/38), and one sandbox payment with Pesapal's test card, completed and confirmed by the API (Velora Flex, 14 days). A second, non-admin account bought a plan, played a film, and its browser registered itself as **This device** (user-reported). Admins skip devices, as designed
- [ ] 10H: One controlled live payment by the owner, with passes still off for viewers: [Step 10H run sheet](step-10h-live-runbook.md)

### Milestone 11: Pilot deployment

Planned in the [pilot deployment plan](step-11a-pilot-deployment-plan.md), **approved on 20 November 2026** with every recommendation accepted: `veloraug.com`, Oracle Pay As You Go, films copied from development, 10 to 30 invited viewers with passes off, app ID `com.veloraug.app`, a direct APK, and Brevo or Resend for email.

- [x] 11B (20 November 2026): `veloraug.com` bought; the Oracle server running in Frankfurt with 4 cores, 24 GB and a 200 GB disk (gate P1 passed), updated, with Docker, set up by `infra/server-setup.sh`, and `main` cloned with a read-only deploy key. Gate P2 passed: both images build natively for ARM64 in about a minute, and all 556 API tests pass on the server with FFmpeg 7.1. Gate P3, converting speed, waits for production's settings.
- [x] 11C (21 November 2026): [`infra/compose.prod.yaml`](../infra/compose.prod.yaml) and [`infra/deploy.sh`](../infra/deploy.sh) run on the server. `https://api.veloraug.com/health` answers 200 through the tunnel, with `"environment":"production"`; `/docs` and `/openapi.json` answer 404; CORS allows `https://app.veloraug.com` only; `upload.veloraug.com` refuses an upload without a key. From outside, only port 22 answers. After a reboot every service came back by itself, healthy within about 50 seconds. Left for when the web app is up: the 3 GB resumable upload through the tunnel.
- [x] 11E (21 November 2026): on the default branch `main`, Neon Auth provisioned through the Neon connector, with Allow Localhost off, `https://auth.veloraug.com` the only trusted domain, sign-in pages on `auth.`, the audience `https://api.veloraug.com`, and the public clients VeloraUG Web and VeloraUG Android. [`infra/production-database.sh`](../infra/production-database.sh), run by the owner on the server, created the three roles, migrated to `0006`, and `check_database.py` passed 33 of 33. On 21 November the owner signed up and signed in on `https://app.veloraug.com`, and was added as the first admin (`public.admins`, the same insert as `catalogue.py admin add`, through the Neon connector, because the script on the PC checks against development's sign-in). `veloraug.com` is verified at Resend. Resend's SMTP details are saved in the Neon Console, sending as `no-reply@veloraug.com`, and Neon's test email reached the owner.
- [x] 11D (20 to 22 November 2026): R2 bucket `veloraug` in Western Europe, private, no `r2.dev` address. Worker `veloraug-media` deployed with `wrangler deploy --env production` on `media.veloraug.com` only, bound to `veloraug`, allowing `https://app.veloraug.com`; a new production signing key made on the server, in `api.env` and the Worker secret, never displayed. `media.` refuses a forged grant with 403. The tunnel `veloraug` runs from Compose on the server only, with `api.` and `upload.` routed to `api:8000` and `tusd:8080`. The server's R2 keys write and delete in `veloraug` and are refused by `veloraug-dev`. On 21 November, `app.` and `auth.` were deployed with Wrangler as static-file Workers `veloraug-app` and `veloraug-auth` (see [Deploy the web app and sign-in pages](../infra/README.md#deploy-the-web-app-and-sign-in-pages)), built with production's settings. Checked from outside: both serve with their security headers, any app path falls back to the app, `/auth.html` is served as itself, `assetlinks.json` is `[]` until 11G, and a sign-in request from the web client goes to `https://auth.veloraug.com/login` while a wrong return address is refused. A sign-in in a browser is still to be tried, after custom SMTP. On 22 November, the rate-limiting rule **Pesapal checkout** (Free plan, the zone's one rule): `POST` to `/api/v1/passes/checkout` on `api.veloraug.com`, more than 5 requests in 10 seconds from one IP, blocked for 10 seconds. Checked from outside: unsigned requests got `401` from the API until Cloudflare answered `429` (on the 12th, as Cloudflare counts approximately and with a short delay). See [Rate limiting](../infra/README.md#rate-limiting).
- [ ] 11F, in part (21 November 2026): the copy command, [`copy_to_production.py`](../services/api/scripts/copy_to_production.py), run by the owner after development was migrated to `0006`. The list-only run found the 7 published films, 33.6 GB. Two fixes during the run: it copies 10 files at once and skips files already there whole, so a stopped run resumes (about 0.5 GB a minute, up from 0.1); and it reads development in autocommit, because Neon ends a connection idle in a transaction for 5 minutes, which stopped the run between films. The Purge 2, 3, 4 and 5 are on production and in its catalogue. Still to do: the other three films, then reset `neondb_owner`'s password on both branches, which was shown in a terminal.
- [ ] 11G, in part (21 November 2026): Android flavors in [`build.gradle.kts`](../apps/client/android/app/build.gradle.kts): `dev`, the default, keeps `com.example.veloraug` on `veloraug-auth-dev.pages.dev` with the debug key; `prod` is `com.veloraug.app` on `auth.veloraug.com`, signed only with the release key, and stops without it. The owner made the key with [`make-release-key.ps1`](../apps/client/android/make-release-key.ps1), kept outside the repository; its fingerprint `A9:7F:…:27:75` is in production's `assetlinks.json`, which Google's Digital Asset Links service confirms. `app-prod-release.apk` (54.5 MB) is built, and `apksigner` shows the same certificate. Still to do: gate P5 on a phone, and rebuilding the APK with the folded Credits. Also on 21 November: Account's TMDB credit is folded into a closed Credits row, still as TMDB's terms ask, deployed to `app.`.

- [ ] Build and run ARM64 images on Oracle with Docker Compose, using a separate Compose file from the local one
- [ ] Publish the web app on Cloudflare Pages
- [ ] Set up production Neon Auth, sign-in pages, custom email and the production Android link
- [ ] Measure real costs against the $20/month pilot target

## Check before launch

- Rights to distribute each movie
- For each VJ edition, both the rights to the source film and the VJ's permission
- TMDB's attribution and commercial-use terms: a signed TMDB agreement, or the [fallback](step-06a-catalogue-plan.md#the-licence-risk), before anyone is charged
- Telegram's terms, if movies are fetched from a Telegram channel
- R2 storage against the pilot budget: about $20 a month at 100 films. See the [uploads plan](step-07a-uploads-plan.md#cost)
