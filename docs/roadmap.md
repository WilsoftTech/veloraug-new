# Roadmap

Last updated: 17 November 2026.

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

Prepaid **daily, weekly and monthly catalogue passes**, through Pesapal. Prices are still open. Pay per title and automatic renewal come later. A playback grant will expire no later than the viewer's pass: see [the plan's look ahead](step-09a-vj-catalogue-plan.md#7-looking-ahead-to-milestone-10-passes).

- [ ] Plan passes, payment confirmation and expiry
- [ ] One pass in Pesapal's sandbox: payment confirmed by the backend, playback allowed, then refused when the pass expires
- [ ] Grants capped at the pass's end, and the player showing "Your pass has ended"

### Milestone 11: Pilot deployment
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
