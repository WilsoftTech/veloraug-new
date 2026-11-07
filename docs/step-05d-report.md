# Step 5D report: sign-in in the Flutter app

Date: 7 November 2026. Branch: `feature/step-05d-flutter-sign-in`. This follows the [Neon plan](step-05a-neon-plan.md#5d-flutter) and the [Step 5C report](step-05c-report.md).

**Step 5D is complete.** The code passes local checks, and on 7 November 2026 the project owner reported that every Android and web test below passed against Neon (user-reported, on one phone and in Chrome). Nothing was deployed, and no Neon setting changed.

## What changed

| Item | Where |
| --- | --- |
| Session controller: restore at launch, sign-in, one refresh at a time, sign-out, and messages | [`lib/auth/auth_controller.dart`](../apps/client/lib/auth/auth_controller.dart) |
| Token storage: Android Keystore-backed `flutter_secure_storage` 11.2.0 on Android, the tab's `sessionStorage` on the web | [`lib/auth/token_store.dart`](../apps/client/lib/auth/token_store.dart) and the two `platform_token_store` files |
| Typed failures, so the app can word them, and the ID token's `email` claim for display | [`lib/auth/oauth_client.dart`](../apps/client/lib/auth/oauth_client.dart) |
| Wording for each failure. It never repeats a code, token, address or the server's text | [`lib/auth/auth_messages.dart`](../apps/client/lib/auth/auth_messages.dart) |
| Account screen: **Sign in**, "Signed in as …", **Sign out**, and the last outcome as a notice | [`lib/screens/account_screen.dart`](../apps/client/lib/screens/account_screen.dart) |
| Android: `INTERNET`, `allowBackup="false"` and the callback activity moved to the main manifest | [`src/main/AndroidManifest.xml`](../apps/client/android/app/src/main/AndroidManifest.xml) |
| **Removed:** the Step 5B sign-in proof panel and its test | |

**How it behaves:**

- **Launch.** A saved session is loaded. If its access token has expired, it is renewed straight away, so a session ended elsewhere shows as signed out. With no network, the person stays signed in and the next request tries again.
- **Refresh.** Tokens are renewed 60 seconds before expiry. Calls made during a renewal share it, because presenting a rotated refresh token makes Neon end the session. A refused renewal (`400` or `401`) signs the person out with "Your sign-in has ended". A network failure keeps the session and reports the failure, with no retry loop.
- **Sign-out.** The device is cleared first, then the refresh token is revoked, then the sign-out page ends the browser's session. With no network, the browser step is skipped, because the page couldn't load, and the notice says the browser may still remember the person. A revoke reply of `400` is treated as done, because Neon answered `400` for an already-unusable token in Step 5C.
- **Failures** each leave the person signed out, with a message: a closed browser, a denied consent, a timed-out request, a changed `state` or issuer, or no network.
- **Logs.** Debug builds log only the failure kind and the client's fixed message, and release builds log nothing. Tests check that no token or code reaches the log.

**Differences from the plan:**

- **Configuration.** Builds without sign-in settings show "Sign-in isn't set up in this version of the app" and no button, in place of the plan's "Sign-in is not configured". `flutter test` runs that way.
- **Release callback host.** The callback in the main manifest uses the development host, `veloraug-auth-dev.pages.dev`, as the plan's example does. A production host and signing certificate must replace it before a real release.

## Tested

| Check | Result |
| --- | --- |
| `dart format`, `flutter analyze` | Clean, no issues |
| `flutter test` | 255 passed |
| Two calls near expiry cause one refresh only | Passed, automated |
| A refused refresh signs out, and a second call makes no new request | Passed, automated |
| Sign-out with no network clears the device and opens no tab | Passed, automated |
| Changed `state`, cancelled browser, denied consent and timed-out request each leave the person signed out, with a message, and exchange no code | Passed, automated |
| No token or code in the debug log | Checked in every controller test |
| `flutter build web` with the real settings | Built. No `postgresql://`, `npg_`, `neondb_owner`, `VELORAUG_` or `client_secret` |
| `flutter build apk --release` with the real settings | Built, 47.8 MB. The same search of the unpacked APK found nothing |
| Packaged release manifest | `INTERNET` present, `allowBackup="false"`, `autoVerify="true"` on the callback, no `networkSecurityConfig` and no `usesCleartextTraffic` attribute |
| Debug manifest | Keeps the loopback rule in `src/debug/`. Its merged copy wasn't rebuilt in this step, and the next `flutter run` on the phone rebuilds it |

## Acceptance criteria

"User-reported" means the project owner ran the step and reported it as passed on 7 November 2026.

| Criterion | State |
| --- | --- |
| Sign-in works on web and Android, and the app verifies `state` | **Met**. `state` checked in tests; real sign-in user-reported on both |
| A changed `state`, a cancelled browser and a denied consent each leave the user signed out, with a message | **Met**. All three in tests; cancel and deny user-reported on both |
| The session survives a reload on web, and a full close and reopen on Android | **Met**, user-reported |
| Web closed and reopened either restores silently or shows sign-in, and the result is recorded | **Met**, user-reported as passed. The expected result is **Sign in**, because `sessionStorage` ends with the tab |
| Two simultaneous calls near expiry cause one refresh only (automated) | **Met** |
| A refused refresh signs the user out instead of looping (automated) | **Met** |
| Sign-out meets all three parts, and sign-out with no network still clears the device | **Met**. In tests, and user-reported on the phone, including flight mode |
| No token appears in logs | **Met** in tests. The owner's run reported no problem |
| The merged release manifest has `INTERNET`, no `networkSecurityConfig` and no `usesCleartextTraffic` | **Met** |
| The debug manifest keeps its loopback rule, and the Step 4C phone check still passes | **Met**. Rule unchanged; the phone check user-reported |
| `allowBackup` is `false` | **Met** |
| Format, analyze, tests and web and APK builds pass | **Met**, with a release APK. The debug APK is built by `flutter run` |
| Searching the web build and APK for `postgresql://`, `npg_`, `neondb_owner` and `VELORAUG_` finds nothing | **Met** |

## Test it

These are the steps the owner ran on 7 November 2026. All were reported as passed.

### Android

Start the API and the port mapping if you also want the Step 4C check: see the [client README](../apps/client/README.md#connect-to-the-local-api). Then:

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d RFCN70850VT "--dart-define-from-file=dart_defines.local.json"
```

On **Account**:

1. **Sign in.** Press **Sign in**, sign in, and press **Allow** if asked. You should see "Signed in as" and your address.
2. **Reopen.** Close the app fully, from the recent apps list, then open it again. You should still be signed in, with no browser.
3. **Sign out.** Press **Sign out**. A tab should open briefly, then "You're signed out." Press **Sign in**: the sign-in form should appear, rather than signing straight back in.
4. **Cancel.** Press **Sign in**, then go back without signing in. You should see "Sign-in was cancelled".
5. **Deny.** Press **Sign in**, sign in, and press **Deny**. You should see "You didn't allow VeloraUG to use your account".
6. **Offline sign-out.** Sign in, turn on flight mode, and press **Sign out**. You should see "You're signed out on this device" and the note about the browser. Turn flight mode off.
7. **Connection check.** If the API is running, **Check connection** should still say "The API answered".

### Web

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d web-server --web-hostname localhost --web-port 8765 "--dart-define-from-file=dart_defines.local.json"
```

Open `http://localhost:8765` in your normal Chrome, and allow pop-ups. Repeat steps 1, 3, 4 and 5, then:

- **Reload** the page. You should still be signed in.
- **Close the tab** and open `http://localhost:8765` again. Note whether you are signed in or see **Sign in**.

**To send me:** what each step showed, any message that was unclear, and anything that looked wrong. Don't send tokens, codes or passwords.
