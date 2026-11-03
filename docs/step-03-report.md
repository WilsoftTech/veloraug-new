# Step 3 report: Flutter app shell

Date: 2 November 2026. This is Milestone 3 in the [roadmap](roadmap.md). Milestone 3 is **not complete**, because the app has not been run on an Android device.

Tools: Flutter 3.47.9 (stable), Dart 3.13.7, Windows 11, about 6 GB of RAM.

## Verification note, 3 November 2026

*Added after this report was written. The report below is kept as written, and where they differ, this note is current.*

**The remaining Milestone 3 checks are now confirmed by manual, user-reported verification.** The project owner reported that all of these passed:

| Where | Check |
| --- | --- |
| Chrome | Navigation between Home, Search and Account |
| Chrome | Narrow and wide layouts |
| Chrome | Tab and Enter controls |
| Physical Android phone | Navigation |
| Physical Android phone | Rotation between portrait and landscape, and the layout in each |

The owner observed these results directly. They were not seen by the automated tooling, and no screenshots were captured. The report did not name the phone.

**Milestone 3 is complete.** Its two remaining criteria were a click-through of every screen in a browser and a run on a phone or emulator, and both are now met.

This note does **not** verify:

- Keyboard use on a phone, which was not part of the owner's report
- A failure and retry cycle inside the app on a phone
- Any other Android device
- Use with a real screen reader
- Building or running an ARM64 image, on Oracle or anywhere else

The results from the [Step 4C report](step-04c-report.md#verification-note-3-november-2026) are separate: that note covers the API connection check on the phone.

## What was built

- A Flutter app in `apps/client/`, for web and Android only, with the Dart package name `veloraug`.
- A dark shell with Home, Search and Account screens. It uses a bottom bar below 600 pixels wide and a side rail from 600 up.
- Honest empty states. There are no movies or posters, search returns nothing, sign-in does not exist, and nothing mentions payments as working.
- No packages beyond the ones `flutter create` adds, and no third-party services.

Repository housekeeping:

- Git now ignores `node_modules/` at any depth, `services/worker/uploads/`, `services/worker/transcoding/`, `.netrc` and `.claude/settings.local.json`. SQL files and TypeScript `.ts` files stay trackable.
- `services/media_gateway/` is documented as the future Cloudflare Worker location. It holds only a README.
- Upload authorization and playback authorization are recorded as [open design tasks](architecture.md#open-design-tasks). Neither exists.

## Verification results

All results are for the final code unless noted.

| Check | Result |
| --- | --- |
| `dart format --set-exit-if-changed lib test` | Passed, 0 files changed |
| `flutter analyze` | Passed, no issues |
| `flutter test` | Passed, 18 of 18 |
| `flutter build web` | Passed, output in `apps/client/build/web/` |
| `flutter build apk --debug` | Passed on the second attempt (see below), output in `apps/client/build/app/outputs/flutter-apk/app-debug.apk`, 157.8 MB |
| `flutter run -d chrome` | Launched, connected to the debug service, no errors logged |
| Screenshots of the web build in headless Chrome, 1200 and 520 pixels wide | Home screen rendered correctly with the rail and the bottom bar |
| Android device or emulator run | **NOT TESTED** |

The tests cover both layouts and the breakpoint, navigation on both layouts, search text surviving a screen change and resize, large text on small screens, the honest placeholders, keyboard navigation, screen reader labels, tap target sizes and text contrast.

### Problems found and fixed

- **Android build failure.** The first `flutter build apk --debug` failed with `Android sdkmanager did not install NDK 28.2.13676358 into ...\Android\sdk`, after `Package ndk not found` and `Package 28.2.13676358 not found`. The Android tools have replaced `sdkmanager` with a new CLI, which names this package `ndk/28.2.13676358`. The likely cause is that the old wrapper does not handle the form Gradle passes to it. The fix was to install that one NDK version with `android sdk install`. No project file or tool version was changed. The build also installed Android SDK Platform 36 by itself.
- **Content centered on wide screens.** A screenshot showed the Home content 280 pixels down on wide layouts, which the first set of tests had missed. It is fixed, and a test now covers it.

## Outstanding checks

- **Android execution: NOT TESTED.** `flutter devices` and `adb devices` showed no phone or emulator. The emulator `Medium_Phone_API_37.0` is installed but was not started, because only about 0.5 GB of RAM was free and an earlier emulator session stayed offline. A successful APK build does not show that the app runs.
- **Clicking through in a real browser: not done.** Only the Home screen was seen in a real browser. Search, Account and keyboard use were checked by widget tests only.
- **Screen reader use: not tested** with a real screen reader. Tests check the labels only.

## Known limitations

- `com.example.veloraug` is for local development only. The production Android application ID is undecided.
- The app icons are still Flutter's defaults.
- The `flutter build web` warning about `CupertinoIcons` fonts was left as is. The app uses only Material icons, and the shell rendered correctly in the screenshots.
- `android/gradle.properties` still has Flutter's default `-Xmx8G`, more than this machine's RAM. The builds passed, so it was not changed. Lower it if Gradle runs out of memory.
- No backend, accounts, catalogue, video or payments exist yet.
- The repository has no remote, so this work exists only on this machine.
