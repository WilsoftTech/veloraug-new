# Step 5B report: Neon sign-in proof

Date: 3 November 2026. This follows the [Neon plan](step-05a-neon-plan.md). **Step 5B is not complete. No gate has passed yet.** The code and deployment files are ready and pass local checks, but no gate can run until the owner carries out the [actions below](#what-you-need-to-do). Nothing has been deployed, no Neon setting was changed, no migration was run, and nothing was pushed.

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
- **Logging.** Neither app logs anything from these flows. The panel shows claim names, shapes and yes/no facts. It never shows tokens, codes or `sub`. Errors keep only an OAuth error code, because a description could quote a value. The Android callback page removes the code from the address bar.
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

## User-tested

Nothing yet.

## Pending: gate results

| Gate | Question | Actual result |
| --- | --- | --- |
| G1 | Metadata matches the Auth URL, and JWKS has an Ed25519 key | **Not run on `development`.** Partial evidence above, from `production` |
| G2 | Neon accepts the `.invalid` resource and issues a JWT | **Not run** |
| G3 | Sign-up, code and sign-in resume through consent. Life of the signed query | **Not run** |
| G4 | Session survives the cross-site cookie | **Not run.** See the browser table below |
| G5 | Public-client exchange and refresh, including browser CORS | **Not run** |
| G6 | Android domain verification and callback delivery | **Not run.** `apksigner` confirms the certificate, but only the phone can prove verification and delivery |
| G7 | Real token contents | **Not run** |
| G8 | Revoke, sign-out, and the form on next sign-in | **Not run** |
| G9 | What sign-up and reset reveal | **Not run** |

Refresh behaviour still to record: whether the token rotates, whether a rotated token is refused, and whether that reuse also revokes the current token, as Neon warns.

| Browser (G4) | Sign-in reaches the callback | Session reused on next sign-in |
| --- | --- | --- |
| Chrome, computer (required) | Not run | Not run |
| Edge, computer (required) | Not run | Not run |
| Chrome, phone (required) | Not run | Not run |
| Firefox, computer | Not run | Not run |
| Safari | Not run, and none is available on this computer | Not run |

## What you need to do

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

**Keep `aws-us-east-2`, or recreate the project elsewhere?** It can't be changed later. Every API request will travel between the Oracle server and this region, so it should be close to that server, whose region I still don't know. Step 5B isn't affected. Recreating is cheap now, while the project is empty, so decide before Step 5F. It would need new Auth URLs and clients, and a script change.

## After the gates

Failure on G3 to G6 stops the milestone, as the [plan's stop rule](step-05a-neon-plan.md#step-5b-gates) says. I'd look for a supported Neon fix first, then report a concrete blocker. Steps 5C onward don't start until the gates are recorded.
