# Client

The VeloraUG Flutter app: one Dart codebase for web and Android.

It is currently only a shell, with Home, Search and Account screens. There are no movies, working search, accounts or payments yet. Its only network call is a development-only connection check to the local API, and it calls no third-party service.

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
| `lib/app.dart` | App title and dark theme |
| `lib/shell/app_shell.dart` | Navigation: a bottom bar below 600 pixels wide, and a side rail from 600 up |
| `lib/screens/` | The Home, Search and Account screens |
| `lib/widgets/` | Layout pieces the screens share, and the development-only connection check |
| `lib/api/` | The API address setting, and the client that calls the API |
| `test/` | Widget and API client tests, using mocked HTTP |
| `android/`, `web/` | Platform files, mostly generated by `flutter create` |

## Android application ID

`com.example.veloraug` is Flutter's default, used for local development only. **The production application ID is undecided.** Choose it before the first store release, because it cannot change afterwards.
