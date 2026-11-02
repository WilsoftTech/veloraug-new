# Roadmap

Last updated: 2 November 2026.

Milestones 1 and 2 match the setup steps already carried out. Milestones 3 onward are a proposed order and may change.

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

## Still unverified

These have **not** been shown to work on this machine:

| Item | Current state | Checked in |
| --- | --- | --- |
| Android device testing | No device was connected at the last check. An earlier emulator session stayed offline | Milestone 3 |
| Android build | No Android app has been built | Milestone 3 |
| Docker container run | The engine responds, but no container has been run | Milestone 4 |

## Planned

### Milestone 3: Flutter app shell
- [ ] Create the app in `apps/client/`
- [ ] Run it in Chrome
- [ ] Build it for Android and run it on a phone or emulator

### Milestone 4: FastAPI skeleton
- [ ] Create the service in `services/api/` with its own virtual environment
- [ ] Add a health-check endpoint
- [ ] Run it in a local Docker container
- [ ] Connect the Flutter app to it

### Milestone 5: Accounts and database
- [ ] Set up Supabase sign-in and PostgreSQL
- [ ] Add database access rules
- [ ] Have the API verify signed-in users

### Milestone 6: Movie catalogue
- [ ] Fetch TMDB details through the API
- [ ] Add browse, search and detail screens

### Milestone 7: Uploads and processing
- [ ] Add resumable uploads with tusd
- [ ] Inspect files with FFprobe and convert them to HLS with FFmpeg
- [ ] Publish to private R2, with optional Telegram archive

### Milestone 8: Protected playback
- [ ] Deliver video through the Cloudflare Worker
- [ ] Test playback on web and Android
- [ ] Confirm that direct access without permission fails

### Milestone 9: Payments
- [ ] Integrate Pesapal in its test environment
- [ ] Unlock access only after the backend confirms payment

### Milestone 10: Pilot deployment
- [ ] Build and run ARM64 images on Oracle with Docker Compose
- [ ] Publish the web app on Cloudflare Pages
- [ ] Measure real costs against the $20/month pilot target

## Check before launch

- Rights to distribute each movie
- TMDB's attribution and commercial-use terms
- Telegram's terms, if the optional archive is used
