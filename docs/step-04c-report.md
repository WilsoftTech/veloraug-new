# Step 4C report: connect the Flutter app to the local API

Date: 3 November 2026. This covers the Flutter connection item in Milestone 4 of the [roadmap](roadmap.md). Milestone 4 stays **open**, because a successful connection from the app on a phone has not been seen.

Tools: Flutter 3.47.9, Dart 3.13.7, `http` 1.6.0, Chrome 156, Docker Compose v5.6.1, Windows 11. Phone: Samsung SM-G981U1, Android 13, `arm64-v8a`.

## Status at a glance

| Item | Status |
| --- | --- |
| Browser integration, real cross-origin request | **Passed** |
| Browser failure and retry, with the real API stopped and restarted | **Passed** |
| App built, installed and started on a real Android phone | **Passed** |
| `adb reverse` from the phone to the API | **Passed**, using `curl` on the phone |
| Connection check succeeding inside the app on the phone | **NOT VERIFIED** |
| Full click-through of the app on a phone (Step 3) | **Not done** |
| ARM64 Docker image | **NOT EXECUTED**. The phone is ARM64, but it runs the app, not the API image |

## What was built

- `lib/api/api_config.dart`: reads `API_BASE_URL` at build time, with the default `http://127.0.0.1:8000`, and validates it. Plain HTTP is accepted only for `127.0.0.1` and `localhost`.
- `lib/api/api_client.dart`: a typed client for `GET /health` and `GET /api/v1`, using the `http` package. It has a 5-second timeout per request and checks the status code, the JSON and the expected fields.
- `lib/widgets/dev_connection_check.dart`: the check on the Account screen, labelled "Development only", with idle, loading, success, failure and retry states. It sends nothing until pressed.
- A debug-only Android network rule that allows plain HTTP to `127.0.0.1` and `localhost` only. The main manifest was not changed.

`API_BASE_URL` is public configuration, never a secret. Anyone can read it from a built app.

### Decisions

- **A narrow Android rule, not `usesCleartextTraffic`.** The app-wide switch would allow plain HTTP to any address in debug builds.
- **The check only runs when pressed.** The navigation shell builds every screen when the app opens, so an automatic check would call the API on every start.
- **`/api/v1` must identify `veloraug-api` v1.** Otherwise, another program on port 8000 could look like a success.

### One existing test changed

The test `account offers no sign-in or payment controls` asserted that the Account screen has no buttons at all, and the debug-only check adds one. It now asserts that no button exists outside the check. Its checks for text fields and payment wording are unchanged.

## Verification results

| Check | Command | Result |
| --- | --- | --- |
| Formatting | `dart format --set-exit-if-changed lib test` | Passed, 0 files changed |
| Analysis | `flutter analyze` | No issues |
| Tests | `flutter test` | Passed, 72 of 72, including the existing navigation and layout tests |
| Web build | `flutter build web` | Passed |
| Debug APK | `flutter build apk --debug` | Passed, 158 MB |

The new tests use mocked HTTP. They cover address validation, parsing, wrong or malformed responses, HTTP errors, timeouts, unavailable servers, every UI state, duplicate taps, replies after the widget is removed, large text and accessibility guidelines.

### What release builds contain

| Check | Result |
| --- | --- |
| Release `main.dart.js`: `Development only`, `API connection check`, `adb reverse`, `127.0.0.1:8000`, `API_BASE_URL`, `veloraug-api`, `The API answered` | 0 matches each |
| Same file, as a control: `You're signed out`, `No movies yet` | 1 match each |
| Debug APK manifest | Has `networkSecurityConfig`, pointing to `debug_network_security_config` |
| Merged release Android manifest | No `networkSecurityConfig`, no `usesCleartextTraffic` |

The web result is a scan of a real release build. No release APK was built or run.

### Real browser

The app ran with `flutter run -d chrome --web-hostname localhost --web-port 8765 "--dart-define=API_BASE_URL=http://127.0.0.1:8000"` against the Docker API. Chrome was driven through its DevTools Protocol, using real pointer events and recording network activity.

| Scenario | Result |
| --- | --- |
| Press **Check connection** | `/health` and `/api/v1` each returned 200 with `access-control-allow-origin: http://localhost:8765`. The screen showed the service details and the scope note |
| API stopped with `docker compose stop api`, then press **Check again** | `net::ERR_CONNECTION_REFUSED`, and the screen showed "The check failed" |
| API restarted, then press **Try again** | Both requests returned 200, and the screen showed success |
| API log during a check | One request to each endpoint |

To confirm that CORS is what permits this, a plain `fetch` to `/health` ran in the same real Chrome from two origins:

| Page origin | Result |
| --- | --- |
| `http://[::1]:8765`, not allowed | Blocked by Chrome: `MissingAllowOriginHeader` |
| `http://localhost:8765`, allowed | Read `{"status":"ok"}` |

This was a browser-level check. The debug app does not start from `[::1]`, so the app's own screen was not tested on the disallowed origin.

**A false alarm that was investigated.** Clicks sent in the first seconds after a page reload were lost, and the app stayed on Home, so navigation was affected too. The same clicks worked once the page had settled. The machine had 0.1 to 0.3 GB of RAM free. Chrome also stopped responding to scripted clicks while the test window was in the background. Neither is specific to the connection check. The cause of the lost clicks was inferred from this behaviour, not measured.

### Real Android phone

| Check | Result |
| --- | --- |
| `flutter run -d <device id> "--dart-define=API_BASE_URL=http://127.0.0.1:8000"` | Built, installed and started in debug mode |
| Account screen on the phone | Rendered, with the check labelled and the address shown |
| Phone `curl` to `http://127.0.0.1:8000/health` before `adb reverse` | Failed, exit 7 |
| Same `curl` after `adb reverse tcp:8000 tcp:8000` | `{"status":"ok"}`, HTTP 200 |
| API binding throughout | `127.0.0.1:8000` only |

**The in-app connection check on the phone is NOT VERIFIED.** The check was pressed on the phone and showed "Could not reach /health", at a time when the `adb reverse` mapping was missing because the USB connection had dropped and reconnected. That explanation is likely but unproven, because a retry could not be run. The phone was then in use with another app focused, and the test tooling refuses to tap or take screenshots unless VeloraUG has focus.

So it is not yet shown that the debug network rule lets the app itself reach the API.

**To finish this check,** follow [the phone steps](../apps/client/README.md#run-on-an-android-phone-over-usb), then press **Check connection** on the Account screen.

## Environment notes

- `adb` is not on PATH on this machine. The commands use its full path.
- `adb reverse` mappings are lost when the USB connection drops, so set the mapping again after reconnecting.
- Run outside Flutter, Gradle picks up a Java 8 on this machine and fails with `Gradle requires JVM 17 or later`. Setting `JAVA_HOME` to Android Studio's `jbr` for one terminal fixes that. `flutter` commands are not affected.
- Kaspersky injects a script into pages opened in Chrome here. It did not interfere with these checks.

## After verification

Only what these checks started was stopped: this project's API container and its network, the `adb reverse` mapping, the test Flutter processes and their Chrome windows, and the Gradle daemon. The debug app **remains installed on the phone**, as `com.example.veloraug`.

Left alone, because this step did not start them:

- A container named `upbeat_kare`, running `veloraug-api:local` with no published port. It appeared during this work, and it is not managed by the Compose file.
- Other Chrome windows launched by earlier Flutter runs.

No firewall, Docker Desktop or global tool setting was changed, and no prune was run.

## Known limitations

- The main Android manifest has no `INTERNET` permission, because only debug and profile builds have needed it. A release build that calls a server must add it.
- A phone can only use `127.0.0.1` while connected by USB with the mapping in place. Wi-Fi testing is not set up, on purpose.
- The timeout does not cancel the underlying request. A late reply is ignored.
- The Android check depends on the API already running on the computer. Nothing here is production-ready.
