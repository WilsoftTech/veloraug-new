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

To reach the local API from a phone, see [Run on an Android phone over USB](../apps/client/README.md#run-on-an-android-phone-over-usb).

**To use an emulator instead:**

```powershell
flutter emulators
flutter emulators --launch <emulator id>
flutter devices
```

`flutter emulators` lists installed emulators. `flutter devices` lists what is running now. An emulator must appear in `flutter devices` before you can use it.

## Memory

The checked machine has about 6 GB of RAM, which is not enough to run Android Studio, an emulator and Docker comfortably together. Close whichever you are not using.

### Android build memory

Android builds start three separate JVMs, and each is configured in a different place:

| JVM | Setting | Where | Peak private memory in a fresh-clone debug build |
| --- | --- | --- | --- |
| Launcher, started by `gradlew` | No limit set, because it stays small | `DEFAULT_JVM_OPTS` in `apps/client/android/gradlew` and `gradlew.bat` | 200 MB |
| Gradle daemon | `-Xmx2g`, 768 MB metaspace, 256 MB code cache | `org.gradle.jvmargs` in `apps/client/android/gradle.properties` | At most 1,500 MB |
| Kotlin daemon | `-Xmx1g`, 512 MB metaspace, 128 MB code cache | `kotlin.daemon.jvmargs` in the same file | 690 MB |

**Why these limits.** The Gradle daemon had been allowed `-Xmx8G` on a machine with 5.9 GB of RAM, and the Kotlin daemon inherited that because it had no setting of its own. With those settings, the Gradle daemon peaked at 3,687 MB and the Kotlin daemon at 772 MB in a fresh-clone debug build.

**Results on 3 November 2026.** These are single runs of debug builds, so they aren't a benchmark. The later builds also had warmer caches, so their times aren't comparable.

| Build | Result | Time | Lowest free commit |
| --- | --- | --- | --- |
| Fresh clone, old settings | Succeeded | 276 s | 4.08 GB |
| Fresh clone, new settings | Succeeded | 171 s | 5.71 GB |
| This project, new settings, no daemon running beforehand | Succeeded, and the live JVMs had the new flags | 116 s | 6.09 GB |

**What the crash logs show.** Four JVM crash logs from 3 November, three from the Gradle daemon and one from the launcher, report that the system had run out of commit: 0 to 183 MB left of about 24.5 GB. The crashing JVMs held only 161 MB to 2.3 GB, and desktop apps held much of the rest when measured later, so these limits lower the risk without removing it. None of the three builds above crashed. The cause of the one earlier APK build failure was never captured, so it isn't attributed to memory.

**Before a large build,** close browsers and other apps you don't need, and stop WSL with `wsl --shutdown` if nothing needs it.

**Not tested:** release builds, which may need more memory. If a build reports an `OutOfMemoryError`, raise that JVM's `-Xmx`. To apply a change, stop the daemons first, because a running daemon keeps its settings:

```powershell
cd C:\Users\Wilsoft\veloraug\apps\client\android
.\gradlew.bat --stop
```

## Known quirk

Running `sdkmanager` on the checked version downloaded an extra Android CLI tool and showed a usage-data notice. Use `flutter doctor -v` for routine checks.

## First Android build

The first `flutter build apk` can fail with `Android sdkmanager did not install NDK 28.2.13676358`, after `Package ndk not found`. On the checked version, Gradle's automatic install did not work. Install that one NDK yourself, about 2.1 GB unpacked, then build again:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\android.exe" sdk install "ndk/28.2.13676358"
```

The build then adds Android SDK Platform 36 by itself.

## Not verified yet

Keyboard use and a failure and retry cycle on a phone, other Android devices, a real screen reader and an ARM64 image. Navigation and rotation on a phone have passed: see the [Step 3 report](step-03-report.md#verification-note-3-november-2026). The app has reached the local API from a phone, and a Linux AMD64 container has run: see the [Step 4C report](step-04c-report.md). See the [roadmap](roadmap.md#still-unverified).
