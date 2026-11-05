# Step 5B report: Neon sign-in proof

Date: 3 November 2026. This follows the [Neon plan](step-05a-neon-plan.md).

**Current status: Step 5B is not complete, and its gates must be rechecked.** On 5 November the Neon project was recreated in Frankfurt, next to the Oracle server. [Setup on the new project](#remaining-manual-tests) hasn't been run, so no gate has passed there yet. All earlier gate results come from the old project, and stay here as history. No migration has been run and nothing has been pushed. The cause of the earlier Android `CANCELED` result is unknown.

Status before the move, kept as history: G1, G2 and G7 had passed, G3, G4, G5, G6 and G8 were partially verified, G9 was not tested, and no gate had failed.

Status when this report was first written, kept as history: no gate had passed, the code and deployment files were ready and passed local checks, and nothing had been deployed or changed in Neon. The owner has since created the `development` branch, deployed the pages and created the OAuth clients.

## Implemented

| Item | Where |
| --- | --- |
| Minimal sign-in companion: login, sign-up with email code, reset request, consent, sign-out and the Android callback page | [`apps/auth_pages/`](../apps/auth_pages/README.md) |
| `assetlinks.json` with package `com.example.veloraug` and this computer's debug certificate | [`apps/auth_pages/public/.well-known/`](../apps/auth_pages/public/.well-known/assetlinks.json) |
| Response headers, including `frame-ancestors 'none'` | [`apps/auth_pages/public/_headers`](../apps/auth_pages/public/_headers) |
| OAuth client: authorization code with PKCE S256, state, nonce, `resource`, refresh that runs once at a time, and revoke | [`apps/client/lib/auth/`](../apps/client/lib/auth/oauth_client.dart) |
| Debug-only proof panel on the Account screen, using in-memory tokens | [`dev_auth_proof.dart`](../apps/client/lib/widgets/dev_auth_proof.dart) |
| Web callback page | [`apps/client/web/auth.html`](../apps/client/web/auth.html) |
| Android callback activity with `autoVerify`, in the debug manifest only | [`src/debug/AndroidManifest.xml`](../apps/client/android/app/src/debug/AndroidManifest.xml) |
| Neon setup script for the owner to run, which only targets `development` | [`infra/neon/step-05b-configure.ps1`](../infra/neon/step-05b-configure.ps1) |
| Read-only check of the real configuration | [`infra/neon/check_step05b.py`](../infra/neon/check_step05b.py) |

**Design points:**

- **State and nonce.** `state` is always checked, before anything else in the callback is read. The flow requests `openid`, so the app sends a `nonce` and refuses an ID token whose nonce differs. OIDC doesn't require a nonce for the code flow, but it costs little. The ID token isn't otherwise used.
- **No secrets in public code.** The clients are `public`, so there is no client secret. The app never sends one, and tests confirm that.
- **Logging.** The companion logs nothing. The debug-only panel writes one sanitized `auth-proof` line to the device log for each browser step or failure, holding only timing, plugin code, fixed-message meaning and token shape. The panel shows claim names, shapes and yes/no facts. It never shows tokens, codes or `sub`. Errors keep only an OAuth error code, because a description could quote a value. The Android callback page removes the code from the address bar.
- **Pinned dependencies.** `@neon/auth` 0.8.2, React 19.3.1, Vite 8.3.5, `@vitejs/plugin-react` 6.2.1, `flutter_web_auth_2` 5.1.0 and `crypto` 3.0.8, with both lock files tracked. Wrangler 4.157.0 and the Neon CLI 8.17.1 are pinned in their commands.

**Left out on purpose, for later steps:** token storage on disk, FastAPI changes, database work, `INTERNET` in the release manifest, and finishing a password reset. The proof panel doesn't appear in release builds.

## Tested

Run on this computer, using no real Neon sign-in.

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 96 passed, including state, nonce, callback, issuer and refresh refusals, and checks that no code or token is displayed |
| RFC 7636 S256 example | Passed |
| `npm test` in `auth_pages` | Passed. The sign-out return list refuses other addresses |
| `flutter build web` | Built, and `build/web/auth.html` is present |
| `flutter build apk --debug` | Built. An earlier attempt failed after 5 minutes, and its cause wasn't captured. The next run passed after Gradle finished installing CMake 3.22.1 |
| Certificate in the built APK, using `apksigner` | `50:2F:52:2C:...:E8:87:D1`, **matches `assetlinks.json`** |
| Package ID in the merged debug manifest | `com.example.veloraug`, matches `assetlinks.json` |
| Callback in the merged debug manifest | `https`, `veloraug-auth-dev.pages.dev`, `/auth/callback/android`, `autoVerify="true"` |
| Main manifest | Has no callback activity and no development host |
| Secret search of the web build and APK | `client_secret=`, `postgresql://`, `npg_` and `neondb_owner` not found. `VELORAUG_` not found in the web build, and `VELORAUG_DATABASE` not found in the APK |
| Companion build guard | Refuses a missing or example Auth URL |
| Companion pages in headless Chrome, with a fake Auth address | All render. Calls to the fake address show "Failed to fetch", as expected |
| Setup script | No parse errors. `-DryRun` listed the expected commands for `-Phase Branch` and changed nothing. `-Phase OAuth` refused to run without the branch. **The real run is untested** |
| Check script | Ran, and reported the missing local file and undeployed site as failures, with no phone connected |

The checks show only that the code agrees with itself. **They don't show that any of this works against Neon, or on a phone.**

### What the real project shows

Read-only, on 3 November 2026.

| Fact | Finding | Effect |
| --- | --- | --- |
| Project | `veloraUg`, `round-block-80526448` | The script targets only this project |
| Region | **`aws-us-east-2`**, not the plan's default of Frankfurt | [Decision for you](#decision-for-you) |
| Branches | Only `production`. **`development` doesn't exist** | The script creates it |
| Auth on `production` | **Already enabled**, and the plan expected `development` only. Sign-up is open, verification isn't required, and there are no trusted domains or OAuth provider | Left unchanged. A child branch should inherit Auth, and the script enables it if not |
| Data API | Not enabled | Matches the plan |
| Production JWKS | One key: `OKP`, `Ed25519`, `EdDSA` | Supports G1, on the wrong branch |
| Production metadata | `404`, with the OAuth provider off | Expected. Must be `200` on `development` |
| `veloraug-auth-dev.pages.dev` | Doesn't respond yet | Expected before deployment |
| Phone | None connected | G6 can't run yet |

`services/api/.env` is empty. Step 5B doesn't use it, so no action is needed.

### Checker correction: `frame-ancestors`

After deployment, `check_step05b.py` reported `frame-ancestors` missing on `/login`, `/consent` and `/auth/callback/android`. **The checker was wrong, and the deployed site was correct.**

- **Cause:** Cloudflare Pages sends headers from `_headers` with lower-case names, such as `content-security-policy`. The checker copied the headers into a plain `dict`, which made its lookup of `Content-Security-Policy` case-sensitive. The `assetlinks.json` type check still passed, because Cloudflare sends `Content-Type` with capitals.
- **Not the cause:** the policy is present and well formed, `dist/_headers` is identical to its source, and Cloudflare applies it to all three routes.
- **Fix:** the checker keeps `urllib`'s case-insensitive headers. The requirement is unchanged, and `_headers` wasn't edited.
- **Tests:** [`test_check_step05b.py`](../infra/neon/test_check_step05b.py) passes on lower-case and usual-case names. It still fails with no policy, no directive, `frame-ancestors *`, or a report-only policy. It fails against the old `dict` code.
- **Local check:** `wrangler pages dev` served the rebuilt pages with the policy on all three routes.
- **Live check:** the corrected checker reports no failures. Its only skipped check is Android domain verification, because the app wasn't installed on the connected phone. This is configuration evidence only, and doesn't complete any gate.

## User-tested

Reported by the owner on the physical phone, a Samsung `SM-G981U1` on Android 13 with Chrome 156. The times and details of these runs weren't recorded.

| Result | Reported |
| --- | --- |
| Sign-in on Android, **twice** | Succeeded both times: code exchanged, refresh token returned, ID token nonce matched |
| Earlier sign-in attempts | Failed, showing only `PlatformException` |
| "End browser session" | Failed, showing only `PlatformException` |

### Latest phone results

Reported by the owner, on the build with sanitized diagnostics.

| Observation | Reported |
| --- | --- |
| One sign-in | Returned `CANCELED`, with no callback. Cause unknown |
| Other sign-ins | Multiple sign-ins exchanged codes successfully |
| Refresh tokens | Returned |
| ID token nonce | Matched |
| Refresh | Two refresh operations succeeded, and reported token rotation |
| End browser session | Returned, and reported device tokens cleared |

**What these do not show:** complete server-side logout, revocation of any token, rejection of an old refresh token, or that a JWT signature is valid. "Rotation" here means the panel received a different refresh token. "Device tokens cleared" describes the app's memory only. No component has verified a token signature yet, and that comes in Step 5E.

### Device log

Read from the phone with `adb`, on 3 November. These are the panel's own sanitized `auth-proof` lines. Refresh writes a line only when it fails, so the two successful refreshes aren't in this log and remain user-reported.

| Time | Action | Browser step lasted | Result |
| --- | --- | --- | --- |
| 18:59:42 | Sign in | 3.2 seconds | `CANCELED`, Auth Tab `RESULT_CANCELED`, no native details |
| 19:01:12 | Sign in | 3.4 seconds | Code exchanged, refresh token returned, nonce matched |
| 19:01:15 | Sign in | 1.3 seconds | Same |
| 19:01:36 | End browser session | 4.0 seconds | Returned with the page's confirmation, device tokens cleared |
| 19:01:43 | Sign in | 3.4 seconds | Code exchanged, refresh token returned, nonce matched |
| 19:02:17 | Sign in | 1.4 seconds | Same |

### Latest browser results

Reported by the owner from browser testing. **Which browser was used hasn't been confirmed, so these results aren't attributed to one.** The device log holds none of them.

**Latest sequence, with no sign-in between the steps:**

| Step | Observed |
| --- | --- |
| 1. Fresh sign-in | Succeeded |
| 2. Revoke the refresh token | `200` |
| 3. Refresh immediately | `400 invalid_grant` |

**Earlier results:**

| Step | Observed |
| --- | --- |
| Refresh | Succeeded, and the token rotated |
| Reuse the old refresh token | Rejected |
| Refresh with the current token after that reuse | Rejected |

**What these do and don't show:**

- They record what happened, and not why. Neon's internal handling isn't established, including what it does with a token family after reuse. Neon's guide describes revoking a user's refresh tokens on reuse, and these results are consistent with that, but they don't prove it.
- **Only refresh-token behaviour was tested.** Nothing here shows that an access token stops working when its refresh token is revoked. The plan expects an issued access token to stay valid until `exp`, and that is untested.
- **FastAPI verification hasn't passed, because it doesn't exist yet.** Token signature verification is Step 5E. Sign-out and the Neon browser session are separate from this result too.
- Whether the earlier results came from the same browser, or from the web app at all, isn't recorded.

## Android `PlatformException` investigation

**The cause of the earlier failures isn't established, so no behaviour fix has been applied.** PKCE, state, nonce, callback checks and the sign-in flow are unchanged.

The panel used to show only the exception type, which discarded the plugin's code and message, so those earlier codes are gone. The device logs don't record them either.

### What was added

[`browser_failure.dart`](../apps/client/lib/auth/browser_failure.dart) reports the plugin's code and a meaning, taken only from `flutter_web_auth_2` 5.1.0's fixed messages. Any other message is withheld, and native details are reduced to present or not, because they could quote an address. The panel and device log also record how long the browser step took, but nothing it returned. Tests confirm that secret values placed in a message or in details never appear.

| Code and meaning | What it would show |
| --- | --- |
| `CANCELED`, tab closed (`User canceled authentication`) | Auth Tab returned `RESULT_CANCELED`: closed with no callback. This could be the user, but the code alone doesn't prove it |
| `CANCELED`, resume clean-up (`User canceled login`) | The app resumed with no result pending |
| `FAILED`, Auth Tab result 2 or 3 | Callback failure: Digital Asset Links verification failed or timed out |
| `FAILED`, Auth Tab result -2 or `no URI` | Callback failure: unknown result, or success without an address |
| `NO_BROWSER`, `SECURITY_EXCEPTION` | Browser launch failure |
| `CANNOT_RESTORE` | The app process died during the browser step |
| `failed: The sign-out page did not confirm.` | The tab returned, but without `signed_out=1`. This isn't a `PlatformException` |

### Evidence so far

Sanitized phone logs, with query strings and paths removed before display. Nothing was saved.

| Time, 3 November | Step | Browser step lasted |
| --- | --- | --- |
| 18:41:09 | Auth Tab to Neon authorize | About 7 seconds |
| 18:41:37 | Auth Tab to Neon authorize | About 1 minute 44 seconds |
| 18:43:58 | Auth Tab to `pages.dev`, which is "End browser session" | About 3.3 seconds |
| 18:44:09 | Auth Tab to Neon authorize | About 2 seconds |

- **Launch:** in these four attempts, the plugin chose Auth Tab with the HTTPS callback, and Chrome opened each time. This points away from a launch failure for these attempts. An earlier attempt at 18:36 also opened in Chrome.
- **Verification:** Android reports `veloraug-auth-dev.pages.dev: verified`, read with `pm get-app-links`. That is the current state, and it doesn't show the state during the earliest attempts.
- **Finish reason:** Chrome logs `app-request` every time, so it can't separate success, cancellation or failure.
- **Sign-out:** a preflight and a POST from the Pages origin to Neon's `/sign-out` were allowed, with credentials. So CORS doesn't explain it. These requests had no session, and an untrusted origin also got `success`, so this says nothing about signing out a real session or about origin checks.
- **18:44:09:** two seconds is too short to type a password. Either the session survived the 18:43:58 sign-out attempt, or this attempt ended early. The logs can't tell which.

**Not established:** which earlier attempts failed, and whether "End browser session" failed through cancellation, callback failure or the page. User cancellation hasn't been shown. Logout hasn't been shown to be unsupported.

### Reproduction results

These results concern sign-in and sign-out. The cause of the `CANCELED` result is still unknown, and the [browser results](#latest-browser-results) don't change that.

**The root cause remains unresolved, and no fix has been applied.**

- **What is now known:** the one recorded failure was `CANCELED` with the plugin's "User canceled authentication" message, meaning Auth Tab returned `RESULT_CANCELED`. It wasn't a launch failure, a verification failure or the resume clean-up.
- **What isn't known:** why Auth Tab returned that result. Closing the tab would produce it, but nothing shows the tab was closed by hand, so user cancellation remains unproven.
- **Earlier failures:** their codes were never captured, so they may or may not have had this same cause. "End browser session" later returned normally, which doesn't explain its earlier failure.

**The sign-out result needs care.** The confirmation means the page's `signOut()` call reported no error, and the browser reached the callback.

- It doesn't show that the Neon session ended. An earlier request to `/sign-out` with no session also returned `{"success":true}`, so a success reply alone proves nothing.
- The sign-in at 19:01:43, 6 seconds after that sign-out, returned in 3.4 seconds. That leaves little time to type an email and password, so the session may have survived. Password-manager autofill could also explain it, and nobody has recorded whether the form appeared. This is open, and it is what the [first remaining test](#remaining-manual-tests) settles.

### Separate finding for G8

Neon's metadata lists `client_secret_basic`, `client_secret_post` and `private_key_jwt` for revocation, and not `none`. A public client has no secret, so the panel's **Revoke refresh token** may be refused. That is untested. The metadata also lists an `end_session_endpoint`, which is the alternative to try if `/sign-out` proves inadequate.

**Later result:** revoke was not refused in browser testing. It returned `200`, and the next refresh was refused, despite that metadata. See the [browser results](#latest-browser-results).

## Gate results

**These results are from the old project in `aws-us-east-2`. None has been rechecked on the new project, so treat each gate as not yet verified there.** The Android package, certificate, callback and Pages address didn't change, and the sign-in code is the same, so these results are a guide to what to expect, not proof.

Updated with the [browser results](#latest-browser-results). Gate statuses haven't changed, but the evidence and gaps for G4, G5 and G8 have.

Checked against the `development` branch, whose Auth URL `neon-auth status` confirms is the one in the app's settings. The criteria are the [plan's gate definitions](step-05a-neon-plan.md#step-5b-gates). All phone evidence is from one phone: a Samsung `SM-G981U1` on Android 13 with Chrome 156.

| Gate | Status | Evidence | Still missing |
| --- | --- | --- | --- |
| G1 | **Passed** | Checker: metadata reachable, `issuer` equals the Auth URL, JWKS lists an Ed25519 key | Nothing |
| G2 | **Passed** | Neon accepted the `.invalid` resource (checker), and real access tokens are JWTs with it in `aud` (device log). The configuration alone wouldn't have passed this | Nothing. Signature checking belongs to Step 5E |
| G3 | **Partially verified** | Sign-in on the pages reached the callback repeatedly | Sign-up and email code through consent were not recorded. How long the signed query lasts is not measured |
| G4 | **Partially verified** | Chrome on the phone reached the callback. Sign-ins of 1.3 to 3.4 seconds are consistent with a reused session, but nobody recorded that no form appeared. A fresh sign-in also succeeded in a browser whose identity isn't confirmed | Confirmation on the phone. Which browser was tested, and session reuse in it. Chrome and Edge on the computer are both required, and neither is attributed yet. Firefox not recorded |
| G5 | **Partially verified** | Android: code exchange (device log), and two refreshes reporting rotation (user-reported). Browser testing: sign-in, rotation, old-token rejection, and rejection of the current token after reuse (user-reported). The panel could only show `200` and `400 invalid_grant` if the browser let it read those responses | **Confirmation that the browser results came from the web app at `http://localhost:8765`.** The pass requires web and Android, so the gate stays open until then |
| G6 | **Partially verified** | The pass criterion, "code reaches the app", was met repeatedly. The checker and `pm get-app-links` both report `verified`, and Google's Digital Asset Links service confirms the link | One `CANCELED` result of unknown cause, and earlier failures with no recorded code. Whether the return button is ever needed wasn't recorded. No other phone or default browser tested |
| G7 | **Passed** | Recorded below, with secret values excluded | Nothing. These facts come from an unverified read of the token |
| G8 | **Partially verified** | Revoke for a public client: `200`, then an immediate refresh returned `400 invalid_grant`, with no sign-in between (user-reported, browser unconfirmed). The sign-out page confirmed, and the device cleared its tokens | Whether the next sign-in shows the form isn't recorded, and [timing raises doubt](#reproduction-results). Server-side logout not shown. Revoke on the phone isn't attributed. Access token behaviour after revoke not tested |
| G9 | **Not tested** | None | Everything: what sign-up and reset reveal |

No gate has failed, so the stop rule hasn't been triggered.

### G7: real access token

From four sign-ins in the device log. The signature wasn't checked, so this describes the token's shape and doesn't show it is genuine.

| Item | Value |
| --- | --- |
| Header | `alg: EdDSA`, `kid` present |
| `iss` | The exact `development` Auth URL, including its path |
| `aud` | **An array** of two values: `https://api-dev.veloraug.invalid` and the issuer's `/oauth2/userinfo` address |
| `client_id` | The Android client's ID |
| `scope` | `openid email offline_access` |
| `sub` | A UUID |
| `iat` | Present |
| Lifetime | 3,600 seconds, and `expires_in` is 3600 |
| Claim names | `aud`, `azp`, `client_id`, `exp`, `iat`, `iss`, `jti`, `scope`, `sid`, `sub` |

This confirms what Step 5E's plan needs: `aud` as an array means `strict_aud` must stay off, and `sub` fits the planned `uuid` column. There is no `role` or `email` claim, and the plan doesn't rely on either.

### G4: browsers

One browser test has been reported without its browser being named, so the computer browsers below are "not attributed", rather than untested.

| Browser | Sign-in reaches the callback | Session reused on next sign-in |
| --- | --- | --- |
| Unconfirmed browser | **Yes** (user-reported) | Not recorded |
| Chrome, computer (required) | Not attributed | Not recorded |
| Edge, computer (required) | Not attributed | Not recorded |
| Chrome, phone (required) | **Yes** | Not confirmed. Short sign-ins are consistent with it |
| Firefox, computer | Not attributed | Not recorded |
| Safari | Not tested, and none is available on this computer | Not tested |

### Earlier gate snapshot

Kept as history, and replaced by the results above.

| Gate | Question | Actual result |
| --- | --- | --- |
| G1 | Metadata matches the Auth URL, and JWKS has an Ed25519 key | **Not run on `development`.** Partial evidence above, from `production` |
| G2 | Neon accepts the `.invalid` resource and issues a JWT | **Not run** |
| G3 | Sign-up, code and sign-in resume through consent. Life of the signed query | **Open.** Android sign-in reached the callback twice (user-reported). Whether those runs covered sign-up, the email code and consent wasn't recorded |
| G4 | Session survives the cross-site cookie | **Not run.** See the browser table below |
| G5 | Public-client exchange and refresh, including browser CORS | **Open.** Android exchange succeeded twice, returning a refresh token (user-reported). Refresh, reuse and browser CORS not reported |
| G6 | Android domain verification and callback delivery | **Open, partly evidenced.** The phone reports `verified` (observed with `adb`). The callback reached the app twice (user-reported). Earlier failures are unexplained, and no fallback browser was tested |
| G7 | Real token contents | **Not run** |
| G8 | Revoke, sign-out, and the form on next sign-in | **Open, failing.** "End browser session" reported `PlatformException` (user-reported), cause not established. Revoke not reported |
| G9 | What sign-up and reset reveal | **Not run** |

Refresh behaviour still to record: whether the token rotates, whether a rotated token is refused, and whether that reuse also revokes the current token, as Neon warns.

| Browser (G4) | Sign-in reaches the callback | Session reused on next sign-in |
| --- | --- | --- |
| Chrome, computer (required) | Not run | Not run |
| Edge, computer (required) | Not run | Not run |
| Chrome, phone (required) | Not run | Not run |
| Firefox, computer | Not run | Not run |
| Safari | Not run, and none is available on this computer | Not run |

## Remaining manual tests

These replace all earlier lists, because every result has to come from the new project. Run them in order. The new project has no accounts, so the sign-up comes first. Successful refreshes and revokes aren't in the device log, so **note those results from the panel**. Record the name of each browser you use.

**Set up the new project, in PowerShell:**

```powershell
cd C:\Users\Wilsoft\veloraug
powershell -NoProfile -ExecutionPolicy Bypass -File infra\neon\step-05b-configure.ps1 -Phase Branch

cd apps\auth_pages
npm ci
npm run build
npx --yes wrangler@4.157.0 pages deploy dist --project-name veloraug-auth-dev --branch main

cd ..\..
powershell -NoProfile -ExecutionPolicy Bypass -File infra\neon\step-05b-configure.ps1 -Phase OAuth
python infra\neon\check_step05b.py
```

The Auth URL is built into the pages, so they must be deployed again. This also puts the [restyled pages](step-03b-report.md) on the development site, ahead of your visual approval.

**Install the app on the unlocked phone:**

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run "--dart-define-from-file=dart_defines.local.json"
```

**On the phone, on the Account screen under Sign-in proof:**

1. **G3, sign-up.** Press **Sign in**, choose **Create an account**, and use one of your test mailboxes. Enter the emailed code, and record whether the consent page appears. Press **Allow**, and record whether the app reopens by itself or the "Return to VeloraUG" page appears.
2. **G5, old refresh token.** Press **Refresh**, then **Reuse old refresh token**, then **Refresh** again. Record all three results.
3. **G8, revoke.** Press **Sign in**. Press **Revoke refresh token** and record the status, then press **Refresh** and record the result.
4. **G8, form after sign-out.** Press **End browser session**, then tap the sign-out button on the page. Press **Sign in**, record whether the sign-in form appears, and complete the sign-in. If the form doesn't appear, record that too, because it means the Neon session survived.
5. **G4, session reuse.** Press **Sign in** again. Record whether the app returns with no form.
6. **G6, cancelling on purpose.** Press **End browser session**, and tap the sign-out button. Press **Sign in**, then close the tab with Back. Record that you closed it by hand.
7. **G3, signed query life.** Press **Sign in** and leave the sign-in form open for 15 minutes, then sign in. If it works, repeat with 60 minutes, after signing out as in step 6. Record the outcome and any message.
8. **G9, what the pages reveal.** Sign out as in step 6, then press **Sign in**. Record the exact message for each of these: a wrong password, **Forgot password** with an address that has an account, **Forgot password** with one that doesn't, and **Create an account** with an address that already has one.

**On the computer**, start the web app, allow pop-ups, and open `http://localhost:8765`, then Account:

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d web-server --web-hostname localhost --web-port 8765 "--dart-define-from-file=dart_defines.local.json"
```

9. **G5, G8 and G4, Chrome.** Press **Sign in** and complete it, then press **Refresh**, **Reuse old refresh token** and **Refresh**. Press **Sign in**, then **Revoke refresh token**, then **Refresh**. Press **Sign in** and record whether the form appears. Press **End browser session**, tap the sign-out button, press **Sign in**, and record whether the form appears.
10. **G4, Edge.** Repeat step 9 in Edge.
11. **G4, Firefox, if you have it.** Repeat step 9. A failure here is recorded for you to decide on, and doesn't stop the milestone.

**Last:**

12. Run `python infra\neon\check_step05b.py` again, and send me your notes.

### Test list before the region move

Kept as history.

Only checks that aren't complete, in order. The revoke, rotation and old-token results are already recorded, so they aren't repeated for the browser already tested.

**First, confirm:**

1. **Which browser you used,** whether it was the web app at `http://localhost:8765`, and whether the earlier rotation and old-token results came from the same browser. This can close G5, and it decides what step 8 covers.

**On the phone, on the Account screen under Sign-in proof:**

2. **G8, form after sign-out.** Press **End browser session**, then tap the sign-out button on the page. Press **Sign in**, and record whether the sign-in form appears. Complete the sign-in. If the form doesn't appear, record that too, because it means the Neon session survived.
3. **G4, session reuse.** Press **Sign in** again. Record whether the app returns with no form.
4. **G8, revoke on the Android client.** Skip this if the revoke sequence has already run on the phone. Press **Revoke refresh token** and record the status, then press **Refresh** and record the result.
5. **G6, cancelling on purpose.** Press **End browser session**, and tap the sign-out button. Press **Sign in**, then close the tab with Back. Record that you closed it by hand.
6. **G3, sign-up.** Press **Sign in**, choose **Create an account**, and use a mailbox with no account. Enter the emailed code, and record whether the consent page appears. Press **Allow**, and record whether the app reopens by itself or the "Return to VeloraUG" page appears.
7. **G3, signed query life.** Press **End browser session** and tap the sign-out button. Press **Sign in** and leave the sign-in form open for 15 minutes, then sign in. If it works, repeat with 60 minutes. Record the outcome and any message.
8. **G9, what the pages reveal.** Press **Sign in**. Record the exact message for each of these: a wrong password, **Forgot password** with an address that has an account, **Forgot password** with one that doesn't, and **Create an account** with an address that already has one.

**On the computer**, using the web app:

9. **G4 and G8, the browser already tested.** Press **Sign in** and complete it, then press **Sign in** again and record whether the form appears. Press **End browser session**, tap the sign-out button, then press **Sign in** and record whether the form appears.
10. **G4, each required browser not yet covered.** Chrome and Edge are both required. Repeat step 9 in whichever isn't the browser from step 1.
11. **G4, Firefox, if you have it and it wasn't the browser tested.** Repeat step 9. A failure here is recorded for you to decide on, and doesn't stop the milestone.

**Last:**

12. Run `python infra\neon\check_step05b.py` again, and send me your notes.

### Earlier test list

Kept as history, and replaced by the list above.

Run them in this order, because the earlier ones leave the state that the later ones need. Successful refreshes and revokes aren't in the device log, so **note those results from the panel**.

**On the phone, on the Account screen under Sign-in proof:**

1. **G8, form after sign-out.** Press **End browser session**, then tap the sign-out button on the page. Press **Sign in**, and record whether the sign-in form appears. Complete the sign-in. If the form doesn't appear, record that too, because it means the Neon session survived.
2. **G4, session reuse on the phone.** Press **Sign in** again. Record whether the app returns with no form.
3. **G5, old refresh token.** Press **Refresh**, then **Reuse old refresh token**, then **Refresh** again. Record all three results. The last one shows whether reuse also revoked the current token.
4. **G8, revoke.** Press **Sign in** if the last step ended your tokens. Press **Revoke refresh token** and record the status, then press **Refresh** and record whether it is refused.
5. **G6, cancelling on purpose.** Press **End browser session**, and tap the sign-out button. Press **Sign in**, then close the tab with Back. Record that you closed it by hand. This shows whether a known cancel gives the same result as the unexplained one.
6. **G3, sign-up.** Press **Sign in**, choose **Create an account**, and use a mailbox with no account. Enter the emailed code, and record whether the consent page appears. Press **Allow**, and record whether the app reopens by itself or the "Return to VeloraUG" page appears.
7. **G3, signed query life.** Press **End browser session** and tap the sign-out button. Press **Sign in** and leave the sign-in form open for 15 minutes, then sign in. If it works, repeat with 60 minutes. Record the outcome and any message.
8. **G9, what the pages reveal.** Press **Sign in**. Record the exact message for each of these: a wrong password, **Forgot password** with an address that has an account, **Forgot password** with one that doesn't, and **Create an account** with an address that already has one.

**On the computer**, after starting the web app with the `flutter run -d web-server` command in [section 5](#5-run-the-sign-in-tests), and allowing pop-ups:

9. **G5 and G4, Chrome.** In your normal Chrome, open `http://localhost:8765`, then Account. Press **Sign in** and complete it. Press **Refresh**, then **Reuse old refresh token**, then **Refresh**. Press **Sign in** again and record whether the form appears. Press **End browser session**, then **Sign in**, and record whether the form appears.
10. **G4 and G5, Edge.** Repeat step 9 in Edge.
11. **G4, Firefox, if you have it.** Repeat step 9. A failure here is recorded for you to decide on, and doesn't stop the milestone.

Then run `python infra\neon\check_step05b.py` once more, and send me your notes.

## What you need to do

Kept as history. Steps 1 to 4 have been carried out. The tests in step 5 are replaced by the [remaining manual tests](#remaining-manual-tests), though its web command is still the one to use.

**Run these in PowerShell, in this order.** None of them asks you to paste a secret into chat. The Auth URL, client IDs and panel results are public, so you can share them.

### 1. Create the development branch

**Where it applies:** Neon project `veloraUg`, branch `development`. It also writes the ignored file `apps/auth_pages/.env.local`.

```powershell
cd C:\Users\Wilsoft\veloraug
powershell -NoProfile -ExecutionPolicy Bypass -File infra\neon\step-05b-configure.ps1 -Phase Branch
```

This creates `development` from `production`, which doesn't alter `production`. It turns on email sign-in with required verification by code, and allows localhost. It uses your existing Neon sign-in.

### 2. Deploy the pages

**Where it applies:** your Cloudflare account, a new Pages project named `veloraug-auth-dev`. A browser opens for the Cloudflare sign-in.

```powershell
cd C:\Users\Wilsoft\veloraug\apps\auth_pages
npm ci
npm run build
npx --yes wrangler@4.157.0 login
npx --yes wrangler@4.157.0 pages project create veloraug-auth-dev --production-branch main
npx --yes wrangler@4.157.0 pages deploy dist --project-name veloraug-auth-dev --branch main
```

**The address must be exactly `https://veloraug-auth-dev.pages.dev`.** If Cloudflare gives it a suffix, stop and tell me the address, because the manifest and scripts need updating.

### 3. Create the OAuth settings

**Where it applies:** `development` only. It also writes the ignored file `apps/client/dart_defines.local.json`.

```powershell
cd C:\Users\Wilsoft\veloraug
powershell -NoProfile -ExecutionPolicy Bypass -File infra\neon\step-05b-configure.ps1 -Phase OAuth
```

If Neon refuses the `.invalid` resource, that is the G2 result, so send me the message.

### 4. Connect the phone

Connect it with USB debugging on, and allow the prompt. The first command below installs and opens the app. The second checks everything, and **it is the proof of domain verification on the phone**.

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d <your phone> "--dart-define-from-file=dart_defines.local.json"
```

In a second terminal:

```powershell
cd C:\Users\Wilsoft\veloraug
python infra\neon\check_step05b.py
```

Android verifies the domain shortly after installation, so if the phone line isn't `verified` at first, wait a minute and run the check again.

### 5. Run the sign-in tests

**Phone:** Open **Account**, then scroll to **Sign-in proof**.

1. Press **Sign in**, choose **Create an account**, and use one of your test mailboxes. Enter the emailed code, then press **Allow**. Note whether the app reopened by itself, or whether the "Return to VeloraUG" page appeared.
2. Press **Refresh**, then **Reuse old refresh token**, then **Refresh** again. The last one shows whether the reuse also revoked the current token.
3. Press **Sign in** again. Note whether the consent page reappeared.
4. Press **Revoke refresh token**, then **End browser session**, then **Sign in**. The form should appear again.
5. Press **Sign in** and try these on the pages: a wrong password, then **Forgot password** with a known address and with an unknown one. Also try **Create an account** with an address that already exists. Note the exact messages.

**Web:** Run this, then open `http://localhost:8765` in your normal Chrome and allow pop-ups. Repeat steps 1 to 4 with your second test mailbox, then in Edge. Try Firefox too, if you have it.

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d web-server --web-hostname localhost --web-port 8765 "--dart-define-from-file=dart_defines.local.json"
```

**To send me:** the output of the check script, the text in the proof panel from each platform, your phone's Android and Chrome versions, its default browser, and your notes. I'll then record these here, investigate any failure within Neon's supported options, and update this report.

### Decision for you

**Decided on 5 November 2026: recreate the project in `aws-eu-central-1` (Frankfurt).** The Oracle server is in Frankfurt, and the region can't be changed later. The new project is `veloraug`, `rapid-violet-90573131`. Its default branch is `main`, not `production`, and it started with Auth off and no `development` branch. The old project stays until the new one is verified, and then the owner deletes it. The original question follows, as history.

**Keep `aws-us-east-2`, or recreate the project elsewhere?** It can't be changed later. Every API request will travel between the Oracle server and this region, so it should be close to that server, whose region I still don't know. Step 5B isn't affected. Recreating is cheap now, while the project is empty, so decide before Step 5F. It would need new Auth URLs and clients, and a script change.

## After the gates

Failure on G3 to G6 stops the milestone, as the [plan's stop rule](step-05a-neon-plan.md#step-5b-gates) says. I'd look for a supported Neon fix first, then report a concrete blocker. Steps 5C onward don't start until the gates are recorded.
