# Step 5G report: end to end

Date: 7 November 2026. Branch: `feature/step-05g-end-to-end`, from `main`. This follows the [Neon plan](step-05a-neon-plan.md#5g-end-to-end), and closes Milestone 5 when the owner's results are in.

**Step 5G is complete, and so is Milestone 5.** The app's profile section and the debug-only token checks are written and pass every local check. On 10 November 2026 the owner ran every step in [test it](#test-it), on web, on one Android phone and with a release build, and reported that all of them passed. See [the owner's runs](#the-owners-runs). Nothing was deployed, and no Neon setting changed.

## What changed

| Item | Where |
| --- | --- |
| Profile client: `GET` and `PATCH /api/v1/me` with the access token, renewed first if needed. Typed failures, and wording that never quotes a token or the server | [`lib/api/profile_api.dart`](../apps/client/lib/api/profile_api.dart) |
| **Your profile** on Account, while signed in: shows the display name, and changes or clears it. Each new sign-in gets a fresh section | [`lib/widgets/profile_section.dart`](../apps/client/lib/widgets/profile_section.dart), [`account_screen.dart`](../apps/client/lib/screens/account_screen.dart) |
| **Development only: token checks**: sends no token, a changed token, or a token kept from earlier, and shows only the status. Debug builds only | [`lib/widgets/dev_token_checks.dart`](../apps/client/lib/widgets/dev_token_checks.dart) |
| Docs | [Client README, Profile](../apps/client/README.md#profile) |

The API, database and sign-in pages are unchanged.

**Why the token checks are in the app.** The plan's checks with a real token, one changed character, more than an hour old, or kept from before sign-out, would otherwise mean copying a token out of the app. The card keeps one token in memory and shows only status codes, so no token is ever copied, displayed or logged.

## Tested

| Check | Result |
| --- | --- |
| `dart format`, `flutter analyze` | Clean |
| `flutter test` | 271 passed, including 16 new tests: the profile client, the profile section, and the token checks with a controlled clock |
| `flutter build web` with the real settings | Built. No `postgresql://`, `npg_`, `neondb_owner`, `VELORAUG_` or `client_secret` |
| `flutter build apk --release` with the real settings | Built, 47.9 MB. The same search of the 76 unpacked files found nothing |
| Tracked files | No `.env`, `dart_defines.local.json` or other local settings file. No `npg_` password, private key or real client ID. Every database URL with a password is a fake test value or the local test container's |

## Acceptance criteria

| Criterion | State |
| --- | --- |
| Web: sign in, call `/api/v1/me`, update the display name, and see it persist, through real CORS | **Met**, user-reported: web steps 1 to 3 |
| Android: the same, over `adb reverse` | **Met**, user-reported: Android steps 1 to 3 |
| Two real users on both platforms see only their own profile | **Met**, user-reported: web step 6, Android step 4 |
| Signed out in the app, no token is sent, and `/api/v1/me` returns `401` | **Met**: in tests, and user-reported in web steps 4 and 5 |
| A real token more than an hour old is refused | **Met**, user-reported: the hour-old check |
| A real token with one changed character is refused | **Met**, user-reported: web step 4 |
| A token captured before sign-out is accepted until `exp`, recorded as the known limit | **Met**, user-reported: web step 5. The limit stands, as the plan records |
| A release build signs in on a phone over HTTPS. Its API calls wait for Milestone 10 | **Met**, user-reported: the release check |
| No real configuration or credential is tracked, and a search of tracked files finds none | **Met** |

## The owner's runs

User-reported on 10 November 2026: every step below passed, on web in Chrome, on one Android phone over `adb reverse`, and with a release build on the same phone. No tokens, codes or passwords were shared. The results were reported as a whole, not step by step.

## Test it

You need two accounts, as in Step 5C: **A**, your main address, and **B**, the second mailbox. Write down what each step shows. Don't send tokens, codes or passwords.

### First: start the API

Docker Desktop must be running. It reads the Neon settings from `services/api/.env`:

```powershell
cd C:\Users\Wilsoft\veloraug
docker compose -f infra/compose.local.yaml up --build -d
docker compose -f infra/compose.local.yaml ps
```

Wait until `ps` shows `(healthy)`.

### Web

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d web-server --web-hostname localhost --web-port 8765 "--dart-define-from-file=dart_defines.local.json"
```

Open `http://localhost:8765` in your normal Chrome, and go to **Account**.

1. **Sign in as A.** Under **Your profile** you should see "You haven't set a display name yet", unless you set one before.
2. **Set a name.** Type `A on the web` and press **Save name**. You should see **Saved.**
3. **Reload the page.** You should still be signed in, with the same name.
4. **Token checks**, under **Development tools**: press **Send no token**, then **Send a changed token**. Both should say "answered 401. As expected". Then press **Keep the current token**, and note the expiry time it shows. **A reload forgets a kept token,** because it lives only in memory, so don't reload the page from here on.
5. **Sign out**, then press **Send the kept token**. It should say "after sign-out: the API answered 200". That is [the known limit](step-05a-neon-plan.md#revocation-limits): a token works until it expires, even after sign-out. **Leave this tab open** for the hour-old check.
6. **Sign in as B.** B should see no name, not A's. Set `B on the web`, and save.

### Android

Run the `adb reverse` command from the [client README](../apps/client/README.md#run-on-an-android-phone-over-usb), then:

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d RFCN70850VT "--dart-define-from-file=dart_defines.local.json"
```

1. **Sign in as A.** You should see A's name from the web, `A on the web`.
2. **Change it** to `A on the phone`, and save.
3. **Close the app fully** and open it again. It should still show `A on the phone`.
4. **Sign out and sign in as B.** You should see `B on the web`, not A's name.

### The hour-old check

In the web tab from step 5, after the expiry time you noted, press **Send the kept token**. It should say "past its expiry: the API answered 401. As expected".

### Release build

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter build apk --release "--dart-define-from-file=dart_defines.local.json"
flutter install --release -d RFCN70850VT
```

This replaces the debug app on the phone. Sign in: it should work through Chrome's Auth Tab, as in debug. **Your profile** should then say "Couldn't reach VeloraUG". That is expected: release builds can't use the plain-HTTP local API, and the HTTPS API comes in Milestone 10. There are no development tools in this build.

**To send me:** what each step showed, and anything that looked wrong or read badly.
