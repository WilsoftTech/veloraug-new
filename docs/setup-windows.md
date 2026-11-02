# Windows setup

Versions checked on 2 November 2026 on Windows 11. Newer versions may also work.

| Tool | Version checked |
| --- | --- |
| Git | 2.53.0 |
| Flutter / Dart | 3.47.9 / 3.13.7 |
| Python / pip | 3.13.14 / 26.1.2 |
| Docker engine / Compose | 29.9.2 / v5.6.1 |
| Android SDK | Platforms 36 and 37.0, Build-Tools 36.0.0, Platform-Tools 37.0.1, NDK 28.2.13676358 |
| Browsers | Chrome 156, Edge 156 |

Visual Studio's C++ tools are not needed, because web and Android are the only targets. `flutter doctor` will still report them as missing, and you can ignore that line.

## Check your machine

Open a new terminal and run:

```powershell
git --version
flutter --version
dart --version
python --version
python -m pip --version
docker version
docker compose version
flutter doctor -v
```

`docker version` must show a **Server** section. If it doesn't, start Docker Desktop.

If `flutter` is not found, add Flutter's `bin` folder to your user PATH, then reopen your terminals and VS Code:

```powershell
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ";$env:USERPROFILE\flutter\bin", 'User')
```

PATH is the list of folders Windows searches for commands. The line above assumes Flutter is in your user folder.

## Test on Android

**A physical phone is recommended,** especially on a machine with limited memory:

1. Turn on Developer options and USB debugging on the phone.
2. Connect it by USB and tap **Allow** on the phone.
3. Run `flutter devices` and check that the phone is listed without an "offline" message.

**To use an emulator instead:**

```powershell
flutter emulators
flutter emulators --launch <emulator id>
flutter devices
```

`flutter emulators` lists installed emulators. `flutter devices` lists what is running now. An emulator must appear in `flutter devices` before you can use it.

## Memory

The checked machine has about 6 GB of RAM, which is not enough to run Android Studio, an emulator and Docker comfortably together. Close whichever you are not using.

## Known quirk

Running `sdkmanager` on the checked version downloaded an extra Android CLI tool and showed a usage-data notice. Use `flutter doctor -v` for routine checks.

## First Android build

The first `flutter build apk` can fail with `Android sdkmanager did not install NDK 28.2.13676358`, after `Package ndk not found`. On the checked version, Gradle's automatic install did not work. Install that one NDK yourself, about 2.1 GB unpacked, then build again:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\android.exe" sdk install "ndk/28.2.13676358"
```

The build then adds Android SDK Platform 36 by itself.

## Not verified yet

An Android device run and an actual Docker container run. See the [roadmap](roadmap.md#still-unverified).
