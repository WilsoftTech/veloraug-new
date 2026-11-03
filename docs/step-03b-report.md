# Step 3B report: design system first

Date: 3 November 2026. Branch: `feature/step-05b-neon-oauth-proof`, which was kept as it was. Step 5C and other sign-in feature work stayed paused.

| Item | Status |
| --- | --- |
| **Implementation** | Complete, and automated checks pass |
| **User visual approval** | **PENDING USER REVIEW** |
| **Phone check** | **Not done.** The phone dropped off `adb` during this step: see [outstanding checks](#outstanding-checks) |

The specification is in [design-system.md](design-system.md).

## What changed

| Area | Change |
| --- | --- |
| Tokens and theme | `lib/theme/`: `tokens.dart`, a `VeloraPalette` `ThemeExtension`, and `ThemeData` with component themes. It replaces the old amber seed colour |
| Components | `lib/widgets/`: buttons, labelled text and password fields, search, movie cards with neutral artwork, loading placeholders, status badges and the wordmark. `EmptyState` was extended, with a new `ErrorState` beside it, and `ScreenBody` was extended |
| Dialogs and notifications | Themed built-in `AlertDialog` and `SnackBar`, with no wrappers |
| Home, Search and Account | Restyled. Navigation is unchanged, and the screens still show honest empty states with no sample movies |
| Development panels | The connection check and sign-in proof keep their behaviour and are restyled, under a "Development tools" heading. Both are still debug-only |
| Web first paint | `web/index.html` now has a charcoal background, so loading doesn't flash white |
| Showcase | `lib/showcase/`, debug builds only |
| Sign-in pages | `src/tokens.css` and a rewritten `src/style.css`. `App.jsx` gains only the wordmark in its root markup |

### Sign-in pages: what didn't change

The `App.jsx` diff is limited to the root element. These files have no changes: `src/auth.js`, `src/returnTarget.js`, `public/_headers` and `public/.well-known/assetlinks.json`. Requests, session handling, OAuth state, nonce, PKCE, consent, callback addresses, redirects and form submission are all as they were. In the Flutter app, `lib/auth/`, `lib/api/` and `web/auth.html` have no changes.

The `.notice` box looks the same for progress and for failure, because the pages use one message element for both. Its words carry the meaning. Telling them apart would change page logic, so that belongs in Step 5C.

### Dependencies

**None added or changed.** `flutter_web_auth_2` stays at stable 5.1.0, and both `pubspec.yaml` and `package.json` are untouched. No font files were added.

### Boundaries kept

No backend changes, migrations, cloud configuration, deployment, push or global upgrades. No new sign-in functionality. No Android files changed.

## Automated checks

These were run on this computer. They show the code works as written, not that it looks right.

| Check | Result |
| --- | --- |
| `dart format` | No changes needed |
| `flutter analyze` | No issues |
| `flutter test` | **235 passed**: the 101 existing tests with no test edited, and 134 new ones |
| Sign-in tests within that (`test/auth`, `dev_auth_proof_test.dart`) | 29 passed. **No regression** |
| `npm test` in `auth_pages` | **8 passed**: the 2 existing and 6 new |
| `npm run build` in `auth_pages` | Built. The built `_headers` and `assetlinks.json` match their sources |
| `flutter build web` | Built. `auth.html` is present |
| `flutter build apk --debug` | Built, after the web build, using the existing Gradle memory limits. It still prints the known `flutter_web_auth_2` KGP warning |
| Secret search of the web build | `client_secret=`, `postgresql://`, `npg_` and `neondb_owner` not found |

The new Flutter tests cover contrast for every token pair, `tokens.dart` against `tokens.css`, component behaviour, validation, the password toggle, reduced motion, 48 pixel targets, tap target, label and contrast guidelines, and overflow at 320, 768 and 1440 pixels wide with text at 100% to 300%.

### The showcase can't reach a release build

`showcaseEnabled` is a compile-time constant, `kDebugMode && bool.fromEnvironment('SHOW_DESIGN_SYSTEM')`, so a release build removes the code. To check, a **release** web build was made **with the define passed**, and its `main.dart.js` was searched:

| Text | Times found |
| --- | --- |
| `Design system showcase` | 0 |
| `Demonstration dialog` | 0 |
| `SHOW_DESIGN_SYSTEM` | 0 |
| `Simulate reduced motion` | 0 |
| `Demo Title One` | 0 |
| `Sign-in proof`, `API connection check` | 0 |
| `No movies yet`, `Search isn't connected`, as a control showing the search works | 1 each |

This was checked on the web build only. No Android release build was made.

## Visual checks

Run by the agent, in headless Chrome, from screenshots. **This is not the owner's approval, and not a phone check.** Text used Roboto, as it would on the web.

| Looked at | Width | Result |
| --- | --- | --- |
| Home, Search, Account | 390 and 1280 | Looks as specified. Account's development panels are clearly separate |
| Keyboard focus on the side rail | 1280 | Visible as a fill on the focused item |
| Showcase: Tokens, Actions, Fields, Movies, Feedback, dialog | 1280 | Looks as specified |
| Showcase: Text size and Movies tabs, top of each page | 390 | No clipping in the visible part |
| Showcase: Layouts, narrow example | 1280 | Looks as specified |
| Validation errors | 1280 | Border, icon and words |
| Browser `prefers-reduced-motion` | 1280 | **Reaches Flutter:** the page reads "on", the spinner becomes an hourglass and placeholders hold still |
| Sign-in pages: `/login` with focus (1280), `/sign-up`, `/consent`, `/sign-out` (390), Android callback (1280) | As listed | Consistent with the app. The focused field is clearly marked |
| Sign-in pages, served with the real `_headers` | Both | No style, font or image violations |

The sign-in pages were checked with a fake Auth address, so nothing reached Neon. "Failed to fetch" in those screenshots is that fake address being blocked, as expected. Chrome also logged a `script-src` note attributed to the JavaScript bundle. Styling can't cause that, but it wasn't compared with a build from before this step. Kaspersky on this computer also injects a script into pages, so its address appears in the logs.

**Two defects were found by looking, then fixed, and now have tests:** disabled fields looked almost enabled, and cards in a row had uneven bottoms.

### Not looked at

Automated tests cover these, but nobody has seen them:

- The medium and wide layout examples in the showcase, and the lower part of the long tabs
- 130% and 200% text
- Bottom bar focus, movie card focus and hover, and the notification
- `/reset`, and the "Enter your code" page

## Outstanding checks

| Check | State |
| --- | --- |
| **Your visual approval** | **PENDING USER REVIEW** |
| Showcase and normal app on the phone | **Not run.** `RFCN70850VT` was listed at the start, then `adb devices` listed nothing for the rest of the step, including the last retry. Reconnect it and use the commands below |
| Sign-in on Android and web with the restyled panel | **Not run.** Sign-in code is unchanged and its tests pass, but nothing here shows it working against Neon again. Step 5B's open gates stay open |
| Real screen reader | Not tested. Automated tests check labels only |
| Keyboard use on a phone | Not tested |
| Android launch screen | Still white until Flutter's first frame. Android files were left alone in this step |
| App icons | Still Flutter's defaults |

## Commands

Run these in PowerShell.

### Open the showcase

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d chrome --web-hostname localhost --web-port 8765 "--dart-define=SHOW_DESIGN_SYSTEM=true"
```

On the phone. Check that it's listed first:

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter devices
flutter run -d RFCN70850VT "--dart-define=SHOW_DESIGN_SYSTEM=true"
```

The debug web build can take about a minute to start, on a charcoal page. Press `q` to quit.

The visual checks above used `-d web-server` with the same settings, to reach headless Chrome. `-d chrome` and the phone commands weren't run in this step.

### Run the normal app with the existing Neon settings

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d chrome --web-hostname localhost --web-port 8765 --dart-define-from-file=dart_defines.local.json
```

On the phone:

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d RFCN70850VT --dart-define-from-file=dart_defines.local.json
```

### Preview the sign-in pages

This uses a fake Auth address for this terminal only, so nothing reaches Neon and `.env.local` isn't changed. Calls to the address fail, and the pages show "Failed to fetch". The server was started this way and served the fake address, using the same setting from Git Bash. The screenshots came from a build served with the real headers, because this preview server doesn't apply `_headers`.

```powershell
cd C:\Users\Wilsoft\veloraug\apps\auth_pages
$env:VITE_NEON_AUTH_URL = "https://auth.example.invalid/neondb/auth"
npm run dev
```

Then open these. `sig=demo` only makes the form appear, and it isn't a real signed request:

- <http://localhost:5173/login?sig=demo>
- <http://localhost:5173/sign-up?sig=demo>
- <http://localhost:5173/reset>
- <http://localhost:5173/consent?client_id=demo&scope=openid&resource=https://api.example.invalid&redirect_uri=https://example.invalid/cb>
- <http://localhost:5173/sign-out>
- <http://localhost:5173/auth/callback/android>

Press `Ctrl+C` to stop, then clear the setting:

```powershell
Remove-Item Env:VITE_NEON_AUTH_URL
```

**Don't deploy a build made with this setting.** `npm run dev` doesn't write to `dist/`. The current `dist/` was rebuilt from your `.env.local` in this step and hasn't been deployed, so the live development site still has the old styling.

## Questions for your review

1. Is the electric blue right, and is the dark charcoal deep enough?
2. Do you want a distinctive display font? System fonts cost nothing and load instantly, but look less distinctive. A bundled font would add file size, and the sign-in pages would need to host it themselves. **I recommend deciding this once the rest looks right.**
3. Does the two-stroke V work as a first identity? It is a placeholder for review, not a finished logo.
4. On Home, is the blue hero panel restrained enough, or too much?
5. Should the Android launch screen and app icons be done next?
