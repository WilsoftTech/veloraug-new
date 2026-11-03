# Roadmap

Last updated: 3 November 2026.

Milestones 1 and 2 match the setup steps already carried out. Milestone 3 is in progress: see the [Step 3 report](step-03-report.md). Step 4 covers the first part of Milestone 4, and Step 4B adds the local Docker run, so Milestone 4 is also in progress: see the [Step 4](step-04-report.md) and [Step 4B](step-04b-report.md) reports. Milestones 5 onward are a proposed order and may change.

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
- [ ] Run it on a phone or emulator (**not tested**: no device was online)

### Milestone 4: FastAPI skeleton

- [x] Create the service in `services/api/` with its own virtual environment
- [x] Add a health-check endpoint
- [x] Add a service-identification endpoint at `/api/v1`
- [x] Run it in a local Docker container (Linux AMD64 only)
- [ ] Connect the Flutter app to it

## Still unverified

These have **not** been shown to work on this machine:

| Item | Current state | Checked in |
| --- | --- | --- |
| Android device testing | No device was connected at the last check. An earlier emulator session stayed offline. A debug APK builds, but it has never been run | Milestone 3 |
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
