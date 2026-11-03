# Roadmap

Last updated: 3 November 2026.

Milestones 1 and 2 match the setup steps already carried out. Milestone 3 is in progress: see the [Step 3 report](step-03-report.md). Step 4 covers the first part of Milestone 4, Step 4B adds the local Docker run and Step 4C connects the Flutter app, but Milestone 4 stays in progress: see the [Step 4](step-04-report.md), [Step 4B](step-04b-report.md) and [Step 4C](step-04c-report.md) reports. Milestones 5 onward are a proposed order and may change.

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

## In progress

### Milestone 3: Flutter app shell

- [x] Create the app in `apps/client/`
- [x] Run it in Chrome
- [x] Build a debug APK for Android
- [ ] Click through every screen by hand in a browser
- [ ] Run it on a phone or emulator (**partly tested**: it started on one phone and the Account screen rendered, but the screens have not been clicked through)

### Milestone 4: FastAPI skeleton

- [x] Create the service in `services/api/` with its own virtual environment
- [x] Add a health-check endpoint
- [x] Add a service-identification endpoint at `/api/v1`
- [x] Run it in a local Docker container (Linux AMD64 only)
- [x] Connect the Flutter app to it in a real browser, with a development-only check
- [ ] See that check succeed inside the app on an Android phone (**not verified**: `adb reverse` works from the phone, but the app's own check has not been seen to succeed)

## Still unverified

These have **not** been shown to work on this machine:

| Item | Current state | Checked in |
| --- | --- | --- |
| Android device testing | A debug build has started on one phone, and the Account screen rendered. The screens have not been clicked through | Milestone 3 |
| API connection from the app on a phone | `adb reverse` works from the phone, but the only press of the app's check that was observed failed, likely because the mapping was missing | Milestone 4 |
| ARM64 image | The base image and pinned packages are available for ARM64, but no ARM64 image has been built or run. The local container is Linux AMD64 | Milestone 10 |

## Planned

### Milestone 5: Accounts and database
- [ ] Set up Supabase sign-in and PostgreSQL
- [ ] Add database access rules
- [ ] Have the API verify signed-in users

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
- [ ] Measure real costs against the $20/month pilot target

## Check before launch

- Rights to distribute each movie
- TMDB's attribution and commercial-use terms
- Telegram's terms, if the optional archive is used
