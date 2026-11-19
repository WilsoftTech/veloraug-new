# Client

The VeloraUG Flutter app: one Dart codebase for web and Android.

It is currently a shell, with Home, Search and Account screens. There are no movies, working search or payments yet. Accounts sign in through Neon Auth and the VeloraUG sign-in pages. Apart from that, its only network call is a development-only connection check to the local API.

Everything built into this app can be read by its users, on web and on Android. It may only hold public configuration, never secrets. See [where configuration lives](../../docs/architecture.md#where-configuration-and-secrets-will-live).

## Run it from PowerShell

Start in this folder:

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
```

Run in Chrome:

```powershell
flutter run -d chrome
```

Run on an Android phone or emulator. First check that it is listed and not "offline":

```powershell
flutter devices
flutter run -d <device id>
```

While the app is running, press `r` to hot reload, `R` to hot restart and `q` to quit.

Check your work:

```powershell
dart format lib test
flutter analyze
flutter test
```

Build it:

```powershell
flutter build web
flutter build apk --debug
```

The web build goes to `build\web\`, and the APK to `build\app\outputs\flutter-apk\app-debug.apk`. Git ignores both.

Run only one build at a time on a machine with limited memory. See [Windows setup](../../docs/setup-windows.md) for the Android NDK a first build needs.

## Connect to the local API

The Account screen has a **development-only** connection check. It asks the API whether it is answering, and shows the result. It exists only in debug builds, so release builds leave it out.

A success means only that the API process responded. It does not check sign-in, the database or production readiness. The profile on the Account screen does: see [Profile](#profile).

### In Chrome: two terminals

**Terminal 1, the API.** Docker Desktop must be running:

```powershell
cd C:\Users\Wilsoft\veloraug
docker compose -f infra/compose.local.yaml up --build -d
docker compose -f infra/compose.local.yaml ps
```

Wait until `ps` shows `(healthy)`.

**Terminal 2, the app:**

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d chrome --web-hostname localhost --web-port 8765 "--dart-define=API_BASE_URL=http://127.0.0.1:8000"
```

Keep the quotes around `--dart-define=...`. Wait a few seconds after the app appears, because taps made while it is still starting can be lost on a machine with little memory. Then open **Account** and press **Check connection**. You should see **The API answered**.

The host and port matter. The API only allows the browser origin `http://localhost:8765`, so another port, or `http://127.0.0.1:8765`, will be blocked by the browser.

To stop: press `q` in terminal 2, then run this in terminal 1:

```powershell
docker compose -f infra/compose.local.yaml down
```

### Run on an Android phone over USB

**Why a phone needs an extra step.** `localhost` and `127.0.0.1` always mean "this device". On your computer they mean the computer, but on the phone they mean the phone, where no API is running. And the API is deliberately reachable only from the computer itself, not over your network.

**`adb reverse` connects the two over the USB cable.** It tells the phone: send anything for port 8000 on this phone, through the cable, to port 8000 on the computer. The app keeps using `http://127.0.0.1:8000`. No network or firewall port is opened, and Docker stays bound to `127.0.0.1`.

You need:

- USB debugging turned on, and **Allow** tapped on the phone
- The phone unlocked
- The API running, as in terminal 1 above

`adb` is not on PATH on this machine, so these commands use its full path. First find the phone's ID, which is the first column of the output. It must say `device`, not `unauthorized` or `offline`:

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb devices -l
```

Put that ID in the commands below. `-s` makes sure the command goes to that phone, even if more than one device is connected:

```powershell
$device = "<device id>"
& $adb -s $device reverse tcp:8000 tcp:8000
& $adb -s $device reverse --list
```

Then run the app:

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client
flutter run -d $device "--dart-define=API_BASE_URL=http://127.0.0.1:8000"
```

On the phone, open **Account** and press **Check connection**.

**The mapping is lost whenever the USB connection drops.** If the check shows "Could not reach /health", run the `reverse` command again and press **Try again**.

When you finish, remove only this mapping:

```powershell
& $adb -s $device reverse --remove tcp:8000
```

**Plain HTTP is allowed for debug builds only,** and only to `127.0.0.1` and `localhost`. The rule is in `android/app/src/debug/`, which is not part of release builds. Don't move it to the main manifest.

### The `API_BASE_URL`, `MEDIA_BASE_URL` and `UPLOAD_BASE_URL` settings

| Name | Default | Set with |
| --- | --- | --- |
| `API_BASE_URL` | `http://127.0.0.1:8000` | `"--dart-define=API_BASE_URL=..."` when running or building |
| `MEDIA_BASE_URL` | `http://127.0.0.1:8787` | `"--dart-define=MEDIA_BASE_URL=..."`. The media gateway. The app plays video from nowhere else. See [Watching](#watching) |
| `UPLOAD_BASE_URL` | `http://127.0.0.1:1080/files/` | `"--dart-define=UPLOAD_BASE_URL=..."`. tusd, for the admin screens' [Uploads](#uploads-from-the-browser). Unlike the others it has a path, which must end in `/` |

**This is public configuration, never a secret.** It is built into the app, where anyone can read it. Never pass a key or password with `--dart-define`.

Each value must look like `scheme://host[:port]`. Plain `http` is only accepted for `127.0.0.1` and `localhost`, and anything else must use `https`. An invalid value shows a failure in the connection check, and sends no request.

## How the app is put together

- **`lib/main.dart`** is where the app starts. Flutter runs its `main()` function, which starts the app.
- **Widgets** are the building blocks of the screen. Text, a button and a whole page are all widgets, and they nest inside each other. Each one has a `build` method that describes how it should look right now.
- **Hot reload** puts your code changes into the running app in about a second and keeps its current state, such as text you have typed. Hot restart also applies your changes, but resets that state.
- **`pubspec.yaml`** is the project's settings file: its name, version, and the packages it depends on. After changing it, run `flutter pub get`.

| Path | What is in it |
| --- | --- |
| `lib/app.dart` | App title, theme, localizations, and the sign-in controller and API clients built from this build's settings |
| `lib/auth/` | Sign-in: OAuth with PKCE, the session controller, token storage and messages |
| `lib/theme/` | Design tokens and the theme. See the [design system](../../docs/design-system.md) |
| `lib/shell/app_shell.dart` | Navigation: a bottom bar below 600 pixels wide, and a side rail from 600 up. Admin shows for admins, on the web |
| `lib/screens/` | The Home, See all, VJ, edition, Search, Account and player screens |
| `lib/admin/` | The admin screens: drafts, a draft's page, VJs and settings, and the web image picker |
| `lib/l10n/` | `app_en.arb`, every visible string, and the `AppLocalizations` generated from it |
| `lib/player/` | The video surface: hls.js on the web, ExoPlayer through `video_player` on Android |
| `lib/widgets/` | Shared components, posters with the VJ label, edition grids and rows, the profile section, and the development-only connection and token checks |
| `lib/showcase/` | The development-only design system showcase |
| `lib/api/` | The API address setting, and the connection-check, profile, catalogue, playback and admin clients. `safe_urls.dart` decides which image and trailer addresses the app will use |
| `test/` | Widget and API client tests, using mocked HTTP |
| `android/`, `web/` | Platform files, mostly generated by `flutter create`. `web/vendor/hls.js-1.7.4/` is hls.js's light build and licence, from npm |

## Design system showcase

A development-only catalogue of the tokens and components, holding clearly labelled demonstration content:

```powershell
flutter run -d chrome --web-hostname localhost --web-port 8765 "--dart-define=SHOW_DESIGN_SYSTEM=true"
```

It opens only in a debug build with that setting. Release builds leave it out even when the setting is passed. See the [Step 3B report](../../docs/step-03b-report.md#the-showcase-cant-reach-a-release-build).

## Android application ID

`com.example.veloraug` is Flutter's default, used for local development only. **The production application ID is undecided.** Choose it before the first store release, because it cannot change afterwards.

## Android build warnings

Checked on 3 November 2026 with Flutter 3.47.9, Gradle 9.3.1, AGP 9.1.0, KGP 2.4.0, JDK 25.0.4 and `flutter_web_auth_2` 5.1.0.

### Native access: fixed

JDK 24 and later warn when Gradle's `native-platform` library calls `System::load`. The warning comes from the launcher JVM that `gradlew` starts. The daemon already passes `--enable-native-access=ALL-UNNAMED` to itself and logs no warning, so `org.gradle.jvmargs` can't fix it.

The flag is set as `DEFAULT_JVM_OPTS` in `android/gradlew` and `android/gradlew.bat`, which sets it for this project only.

| Check | Warning lines |
| --- | --- |
| Before the fix | 3 |
| Flag on the launcher only, with a running daemon and with a cold one | 0 |
| `flutter build apk --debug` after the fix | 0 |
| `flutter build apk --debug` from a fresh clone | 0 |
| `android/gradlew` run through Git Bash | 0 |

**Regenerating the wrapper scripts may remove the flag.** That includes running `gradle wrapper`, or deleting the scripts so that Flutter creates its stock copies. Afterwards, check it's still there, and put it back if it isn't:

```powershell
Select-String -Path android\gradlew, android\gradlew.bat -Pattern 'enable-native-access'
```

### Wrapper files in a clean checkout

| File | How a clean checkout gets it |
| --- | --- |
| `android/gradlew`, `android/gradlew.bat` | Tracked in Git |
| `android/gradle/wrapper/gradle-wrapper.properties` | Tracked in Git. It pins Gradle 9.3.1 |
| `android/gradle/wrapper/gradle-wrapper.jar` | Ignored by Git. **Flutter copies it from its own cache during an Android build** |
| `android/local.properties` | Ignored by Git. Flutter creates it |

So run a Flutter Android build first, for example `flutter build apk --debug`. Until then, the jar and `local.properties` don't exist, so `gradlew` can't run directly. This was tested with a fresh clone: the build succeeded, the jar matched Flutter's cached copy, and no tracked file changed, so Flutter left the scripts as they were.

### `flutter_web_auth_2` applies KGP: open upstream issue

Every Android build prints `Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): flutter_web_auth_2`. **This remains open.** Nothing in the app can remove it, and builds still work for now, with `android.builtInKotlin=false` in `android/gradle.properties`.

- Flutter says a future version will fail to build apps with plugins that apply KGP, without giving a version or date ([Flutter's guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)).
- Stable 5.1.0 is the latest stable release and applies KGP. The maintainer closed the request for a 5.x fix as not planned, and says 6.0.0 will be released when it's production-ready ([issue 223](https://github.com/ThexXTURBOXx/flutter_web_auth_2/issues/223)).
- **The project stays on 5.1.0.** `6.0.0-alpha.9` is a prerelease, and hasn't been adopted. On a throwaway copy it removed the warning and built with `android.builtInKotlin` true and false. Sign-in wasn't tested with it.

When 6.0.0 is stable, upgrade, set `android.builtInKotlin=true`, and repeat the sign-in and callback checks. Do this sooner if a Flutter upgrade rejects the plugin.

## Sign-in

The Account screen signs in and out. It needs the Neon settings from the ignored `dart_defines.local.json` file, passed with `--dart-define-from-file=dart_defines.local.json`. Without them, it says sign-in isn't set up and offers no button. See the [Step 5D report](../../docs/step-05d-report.md).

| | Web | Android |
| --- | --- | --- |
| Sign-in page | A popup, so allow pop-ups for `http://localhost:8765` | Chrome's Auth Tab |
| Saved session | The tab's `sessionStorage`: survives a reload, not a closed tab | Encrypted with an Android Keystore key, and kept when the app closes |
| Address | Must be exactly `http://localhost:8765`, the registered callback origin | The callback is `https://veloraug-auth-dev.pages.dev/auth/callback/android` |

Sign-out revokes the refresh token, clears the device, then opens the sign-out page to end the browser's session. With no network, it still clears the device.

**The Android callback host is the development one,** in the main manifest. A production host and signing certificate are needed before a real release.

## Catalogue

Planned in the [VJ catalogue plan](../../docs/step-09a-vj-catalogue-plan.md#6-app). Everything is a **VJ's edition** of a movie or series.

- **Home** has rows for **Latest**, **Movies**, **Series** and each VJ, each with **See all**. Once a second language has something published, there is a row per language too.
- **Every poster card** shows only the VJ's name, small, in the poster's top-left corner, and screen readers read it after the title.
- **A VJ's page** has their photo, name and bio, then their movies and series. The row's **See all**, or the label on an edition's page, opens it.
- **An edition's page** shows the full label, such as **Luganda · VJ Junior**, the year, running time, genres and description, and **Trailer**, which opens TMDB's official trailer on YouTube outside the app. A movie has **Watch**. A series lists its seasons and episodes, each with a play button.
- **Search** looks in titles and VJ names once you've typed 2 letters and paused for 300 ms, or at once when you press search.

Browsing needs no sign-in, and the app sends no token for it. It calls `GET /api/v1/editions`, `/api/v1/editions/{id}`, `/api/v1/vjs`, `/api/v1/vjs/{slug}` and `/api/v1/languages`, which need the API running with its Neon settings, as in [Connect to the local API](#connect-to-the-local-api). Posters load from TMDB's image server, `image.tmdb.org`, or, for images an admin uploaded, from the media gateway's `/i/` route on `MEDIA_BASE_URL`. The app accepts no image address from anywhere else, and opens trailers only on `https://www.youtube.com/watch`.

| What happens | What the screen says |
| --- | --- |
| Nothing published | "Nothing to watch yet" |
| An edition was hidden or removed | "This title isn't available", with **Back** |
| The API, or an edition's details, isn't ready | "VeloraUG is busy right now", with **Try again** |
| No answer, or the browser blocked it | "Couldn't reach VeloraUG", with **Try again** |
| A poster can't load | The plain poster placeholder |

**About**, on the Account screen, credits TMDB with its logo and the notice its terms require. Both show in every build. The logo is TMDB's approved short logo, in [`assets/brand/tmdb_logo.png`](assets/brand/tmdb_logo.png), drawn from TMDB's SVG to a PNG so the app needs no SVG package. It shows 16 pixels tall, smaller than VeloraUG's own brand.

**Restart your API after updating,** or the catalogue routes won't exist and Home answers "Something went wrong".

## Watching

Planned in the [playback plan](../../docs/step-08a-playback-plan.md). On a movie's page, or for each episode of a series:

| The title | Signed in | Signed out |
| --- | --- | --- |
| Has something to watch (`playable`) | **Watch**, or an episode's play button, opens the player | **Sign in to watch** starts sign-in |
| Nothing ready yet | **Watch**, disabled, or the episode, with **Coming soon** | The same |

The player asks the API for a grant for one item, a movie's video or one episode: `POST /api/v1/items/{id}/playback`, with the access token. The answer is an address on the media gateway, which the app accepts only if it is on `MEDIA_BASE_URL`. Then:

- **On the web,** a `<video>` element with the browser's own controls, fed by hls.js, which the app loads from `web/vendor/` the first time a film plays. No outside script is loaded.
- **On Android,** ExoPlayer, through `video_player`, with play, pause, a seek bar and the time.

A grant lasts 6 hours. If playback stops once it has run out, the app gets a new one by itself and carries on from the same moment. Any other stop shows **Try again**, which also carries on from where it stopped.

**Next Episode.** For a series, the bar has a **Next episode** button, and when an episode ends, **Up next** offers it in the middle of the screen. It is the next number in the same season, then the first episode of the next season, always in the same edition, so with the same VJ. Episodes with nothing ready are skipped. Each episode gets its own grant.

**Quality.** The gear in the bar chooses the quality, as on YouTube: **Auto**, the default, which follows the connection, or one of the qualities the film was made in, such as 1080p or 480p, held whatever the connection. The app reads them from the master playlist on the media gateway, with no token, and accepts only a playlist one folder down under the same grant. Choosing one plays that quality's own playlist from the same moment, on the web and on Android, without asking the API again. The choice is kept for the next episode and a renewed grant, until the app is closed. Without a readable master playlist, there is no gear and Auto plays.

**To run it locally,** the API needs its [playback settings](../../services/api/README.md#playback), and the media gateway must be running: see [its README](../../services/media_gateway/README.md#run-it-locally). In Chrome, add `"--dart-define=MEDIA_BASE_URL=http://127.0.0.1:8787"` to the run command. On a phone, also forward the gateway's port:

```powershell
& $adb -s $device reverse tcp:8787 tcp:8787
```

## Admin

Planned in the [VJ catalogue plan](../../docs/step-09a-vj-catalogue-plan.md#6-app). On the web, an **Admin** entry appears in the menu for admins only: the app asks `GET /api/v1/admin/me` after sign-in, and shows it on `200`. Opening the app at `/admin` starts there. It isn't on Android in the first release. Every admin route checks again on the server, so hiding the menu is a convenience, not the protection.

- **Drafts** lists drafts, hidden titles and series with new episodes waiting, each with what it still needs. **New draft** takes the title, movie or series, language, an optional year, and for a series the first episode's numbers. It shows the **upload key once**, with **Copy**. Upload the video with `python tools/veloraug_upload.py <file>` and paste the key when asked.
- **Uploads** does the same from the browser, for many files at once, with no key to copy: see [Uploads from the browser](#uploads-from-the-browser).
- **A draft's page** has, in order:
  - each video's state, with **Preview**, **New upload key**, **Revoke**, and for a published series **Approve episode** and **Add episode**;
  - the **details**: TMDB's candidates with **Use this**, **Search TMDB again**, **Use a TMDB ID**, or **Type the details in**;
  - the **poster**: TMDB's English posters to choose from, or **Upload a poster**;
  - the **VJ credit**: suggestions from the file's name and tags, **Choose a VJ** or **Add a new VJ**. Nothing is credited until the admin confirms it;
  - **Publish**, which lists what is still missing if it is refused, or **Hide**.
- **VJs** adds or changes a VJ's name, other spellings, bio and photo.
- **Settings** lists the admins and who added each one, adds an admin by email, and removes one, except the last. It also lists and adds languages.

Posters and photos are JPEG, PNG or WebP, at most 2 MB. The browser sends them straight to the media gateway with a 10-minute upload address from `POST /api/v1/admin/images`, so the media gateway must be running and redeployed with its image routes.

### Uploads from the browser

Step 9G, in `lib/admin/uploads/`. **Admin → Uploads** takes video files dragged onto the page or picked with **Choose files**, as many as you like.

1. **Each file is read from its name** into a row to check: title, movie or series, year, or season and episode, VJ and language. An episode is matched to the series it belongs to, by title and VJ, from `GET /api/v1/admin/series`. Rows can be changed or left out, and an episode the series already has, or one listed twice, is stopped before anything is made.
2. **Start uploads** makes each file's draft, or adds the episode, with `POST /api/v1/admin/drafts`, and credits the VJ chosen in the row. Choosing a known VJ there and starting is the admin's confirmation. A VJ the file names who isn't known yet is left for the draft's page. The upload key goes straight into the upload and is never shown or kept.
3. **Two files upload at a time**, each with a progress bar, the percentage, MB sent, speed and time left, and **Pause**, **Resume**, **Remove** and **Open draft**. The list can be filtered by VJ.

**The naming guide,** shown on the screen, puts the VJ first, so files sort and search by VJ in Windows Explorer too:

```text
VJ Junior - Commando (1985).mp4
VJ Junior - Prison Break S01E02.mp4
```

Other styles, such as `Fast.X.2023.VJ.Junior.Luganda.mp4`, are read as well as they can be: known VJs and their other spellings are found anywhere in the name, and words like HD, 720p and Luganda are dropped.

**Nothing starts again from the beginning.** The app speaks tus, the same protocol as the upload script, in Dart in [`tus.dart`](lib/admin/uploads/tus.dart):

| What happens | What the app does |
| --- | --- |
| The connection drops, or the server is down | tusd keeps every byte it got. The app tries again after 1, 3, 5, 10, 20 and 30 seconds, then every minute, and at once when the browser is back online. It asks tusd how much it has (`HEAD`) and sends only the rest |
| A request hangs without failing | After 60 seconds with no progress, it is given up and tried again the same way |
| **Pause** | The request in flight is stopped. **Resume** carries on from tusd's offset |
| The tab closes, the browser restarts, or the power goes | Each upload is kept in the browser's IndexedDB with its upload address and how far it got. Opening **Uploads** again lists it. In Chrome and Edge, the file's handle is kept too, so **Resume** opens it again after Chrome asks to allow access. Elsewhere, drop or choose the same file again: it is recognised by name, size and date, and carries on |
| tusd lost the upload | It starts again with a new key, and says so |
| **Remove** | It stops, and deletes the part uploaded from tusd with `DELETE`. tusd's `pre-terminate` hook refuses that for a finished upload. The draft stays in Drafts |

Each part sent is at most 50 MB, under Cloudflare's 100 MB limit on a request, for Milestone 11. The browser warns before leaving the page while anything is uploading. Uploads carry on while you use other screens, but stop when the tab closes.

**To run it locally,** start tusd and the hooks with the `uploads` profile, as in [the API's README](../../services/api/README.md#start-the-upload-services). tusd only answers browsers on `http://localhost:8765`, so run the app on that port, as in [In Chrome](#in-chrome-two-terminals). Upload addresses kept in the browser give access to that one unfinished upload, like the script's `.veloraug-upload` file.

## Text and languages

Every visible string is in [`lib/l10n/app_en.arb`](lib/l10n/app_en.arb), read through `AppLocalizations`, which `flutter gen-l10n` generates into `lib/l10n/` (it also runs on `flutter run`, `build` and `test`). Screens use `context.l10n`. The design system's components take their text from their callers, and fall back to the file for their own labels. Titles, VJ names and language names are data, and aren't translated. The debug-only tools, the showcase and the connection and token checks, keep their English.

To add Luganda, copy `app_en.arb` to `app_lg.arb`, translate the values, and run `flutter gen-l10n`. `test/l10n_test.dart` fails if a visible English string is written in the code instead of the file.

## Profile

Signed in, the Account screen shows **Your profile**. It loads the display name from `GET /api/v1/me`, and **Save name** sends it with `PATCH /api/v1/me`. Both carry the access token in the `Authorization` header, renewed first if it is about to expire. The API creates the profile on first use.

It needs the API running with its Neon settings, as in [Connect to the local API](#connect-to-the-local-api). Run the app with `--dart-define-from-file=dart_defines.local.json`, which includes `API_BASE_URL`.

| What happens | What the screen says |
| --- | --- |
| The API refuses the token | "VeloraUG didn't accept your sign-in. Sign out, then sign in again." |
| The API or its database is unavailable | "VeloraUG is busy right now." |
| No answer, or the browser blocked it | "Couldn't reach VeloraUG." |

**Release builds** still call `http://127.0.0.1:8000`, so their API calls fail until an HTTPS API exists, in Milestone 11. Sign-in itself works in a release build.

### Token checks, debug builds only

Under **Development tools**, **Development only: token checks** sends `/api/v1/me` with:

- **no token**, which should get `401`,
- **a changed token**, with one character of the signature changed, which should get `401`, or
- **a kept token**: **Keep the current token** holds it in memory, and **Send the kept token** sends it later. Before it expires it should get `200`, even after sign-out. After it expires, an hour after it was issued, it should get `401`.

It shows only the status code and whether that was expected. The kept token is never shown, logged or copied, and is gone when the app closes or the web page reloads. Release builds leave the whole card out.
