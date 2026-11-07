# Roadmap

Last updated: 7 November 2026.

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
| ARM64 image | The base image and pinned packages are available for ARM64, but no ARM64 image has been built or run. The local container is Linux AMD64 | Milestone 10 |

## Open issues

| Issue | Current state | Next action |
| --- | --- | --- |
| `flutter_web_auth_2` applies the Kotlin Gradle Plugin | Open upstream. Stable 5.1.0 still applies it, so every Android build warns, and a future Flutter version will reject it. See [Android build warnings](../apps/client/README.md#android-build-warnings) | Upgrade when 6.0.0 is stable, or sooner if a Flutter upgrade requires it |

## Planned

### Milestone 5: Accounts and database

Planned in the [Neon plan](step-05a-neon-plan.md), which replaces the superseded [Supabase plan](step-05a-plan.md). The Neon project moved to Frankfurt, next to the Oracle server. Step 5B's gates passed there on one phone and in Chrome and Edge, with some results user-reported: see the [Step 5B report](step-05b-report.md).

- [x] 5B: Set up a Neon development branch and minimal sign-in pages, and test the sign-in route on web and one phone
- [x] 5C: Finish the sign-in pages on Cloudflare Pages (flows user-reported on one phone: see the [Step 5C report](step-05c-report.md))
- [x] 5D: Add sign-in to the Flutter app on web and Android (device and browser tests user-reported on one phone and in Chrome: see the [Step 5D report](step-05d-report.md))
- [ ] 5E: Have the API verify signed-in users
- [ ] 5F: Add migrations, the API's database role and database access rules
- [ ] 5G: Check everything end to end

### Milestone 6: Movie catalogue
- [ ] Fetch TMDB details through the API
- [ ] Add browse, search and detail screens

### Milestone 7: Uploads and processing
- [ ] Design upload authorization: who may upload, and how tusd checks it
- [ ] Add resumable uploads with tusd
- [ ] Inspect files with FFprobe and convert them to HLS with FFmpeg
- [ ] Publish to private R2, with optional Telegram archive

### Milestone 8: Protected playback
- [ ] Design playback authorization: what the API grants, and how the Worker checks it
- [ ] Deliver video through the Cloudflare Worker in `services/media_gateway/`
- [ ] Test playback on web and Android
- [ ] Confirm that direct access without permission fails

### Milestone 9: Payments
- [ ] Integrate Pesapal in its test environment
- [ ] Unlock access only after the backend confirms payment

### Milestone 10: Pilot deployment
- [ ] Build and run ARM64 images on Oracle with Docker Compose, using a separate Compose file from the local one
- [ ] Publish the web app on Cloudflare Pages
- [ ] Set up production Neon Auth, sign-in pages, custom email and the production Android link
- [ ] Measure real costs against the $20/month pilot target

## Check before launch

- Rights to distribute each movie
- TMDB's attribution and commercial-use terms
- Telegram's terms, if the optional archive is used
