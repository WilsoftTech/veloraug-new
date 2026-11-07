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

A success means only that the API process responded. It does not check sign-in, payments, a database or production readiness, and none of those exist yet.

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

### The `API_BASE_URL` setting

| Name | Default | Set with |
| --- | --- | --- |
| `API_BASE_URL` | `http://127.0.0.1:8000` | `"--dart-define=API_BASE_URL=..."` when running or building |

**This is public configuration, never a secret.** It is built into the app, where anyone can read it. Never pass a key or password with `--dart-define`.

The value must look like `scheme://host[:port]`. Plain `http` is only accepted for `127.0.0.1` and `localhost`, and anything else must use `https`. An invalid value shows a failure in the connection check, and sends no request.

## How the app is put together

- **`lib/main.dart`** is where the app starts. Flutter runs its `main()` function, which starts the app.
- **Widgets** are the building blocks of the screen. Text, a button and a whole page are all widgets, and they nest inside each other. Each one has a `build` method that describes how it should look right now.
- **Hot reload** puts your code changes into the running app in about a second and keeps its current state, such as text you have typed. Hot restart also applies your changes, but resets that state.
- **`pubspec.yaml`** is the project's settings file: its name, version, and the packages it depends on. After changing it, run `flutter pub get`.

| Path | What is in it |
| --- | --- |
| `lib/app.dart` | App title, theme, and the sign-in controller built from this build's settings |
| `lib/auth/` | Sign-in: OAuth with PKCE, the session controller, token storage and messages |
| `lib/theme/` | Design tokens and the theme. See the [design system](../../docs/design-system.md) |
| `lib/shell/app_shell.dart` | Navigation: a bottom bar below 600 pixels wide, and a side rail from 600 up |
| `lib/screens/` | The Home, Search and Account screens |
| `lib/widgets/` | Shared components, and the development-only connection check |
| `lib/showcase/` | The development-only design system showcase |
| `lib/api/` | The API address setting, and the client that calls the API |
| `test/` | Widget and API client tests, using mocked HTTP |
| `android/`, `web/` | Platform files, mostly generated by `flutter create` |

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
