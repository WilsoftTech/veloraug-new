# Step 12A: Downloads as files to keep

Written and built on 23 and 24 November 2026, at the owner's request. **Not yet checked on a phone or in a browser against a real film.** Replaces the first version from the same step, merged in PR #4: that version kept downloads private to the Android app, playable for 7 days at a time. The owner then decided, on 24 November 2026:

- Downloads are saved where viewers keep their own files: the **computer's Downloads folder** from a browser, and the **phone's storage** from the Android app.
- They are **ordinary .mp4 files, theirs to keep**. They play in any video player, can be copied and shared, and never expire. The pass and the device are checked only when a download starts.
- The server makes the files, in **every quality**.

## What viewers get

- **Download** beside **Watch** on a movie's page, and a download icon beside each episode's play button, in the browser and in the Android app. Tapping it lists each quality with its exact size, such as "720p, 1.2 GB".
- **In a browser,** choosing a quality hands the file to the browser, which saves it to the Downloads folder and shows its progress, as for any download. The file is named, for example, `Fast X - VJ Junior - 720p.mp4`, or `Kabaka - S01E02 - VJ Emmy - 720p.mp4`.
- **On Android,** Android's own download manager saves it to **Downloads/VeloraUG** on the phone. It shows a notification, carries on with the app closed and after a dropped connection, and keeps the file if the app is uninstalled. The Download button then shows the progress, then **Downloaded**, which opens the file in the phone's video player. A **Downloads** tab, between Search and Account, lists each download with its progress, size and file name, with **Open**, **Download again** after a failure, and **Delete**, which asks first and deletes the file.

## How it works

| Part | What it does |
| --- | --- |
| Media worker | After converting a film to HLS, joins each quality's chunks into one `<quality>/download.mp4` with FFmpeg, copying the video and sound as they are (`-c copy`), with the index at the start (`+faststart`). Tried on a real 1 h 43 min film: 29 seconds for 360p, 283 MB, H.264 and AAC. The publisher uploads it with the chunks |
| `python -m app.download_files` | Makes the files for films published before this step: see [Making files for films already published](#making-files-for-films-already-published) |
| `POST /api/v1/items/{id}/download` | The same checks as playback: published and ready, and with passes required, a running pass, this device registered, and no more devices than the plan allows. Returns a grant with **no playback session**, for **24 hours** and never past the pass, and a file name such as `Fast X - VJ Junior` |
| Media gateway | Serves `<quality>/download.mp4` under the grant, with `Content-Disposition: attachment` and the file name from `?name=`, made safe. Ranges work, so downloads resume |
| App | Reads the qualities from the master playlist, and each file's size with a `HEAD` request. A quality whose file isn't there yet is left out. Then: on the web, follows the file's address, which the browser saves; on Android, hands it to `DownloadManager` through `MainActivity.kt` |

### Decisions

| # | Decision | Why |
| --- | --- | --- |
| 1 | Files are joined on the server, once per film and quality | Works the same in every browser and on every phone, and lets the browser's and Android's own downloaders resume. Joining in the app would hold the whole film in memory in most browsers |
| 2 | The grant lasts 24 hours, with no playback session | The browser's and Android's downloaders can't ask for a new grant, and a big film on a slow connection takes hours. A session would take one of the viewer's streams, and stop the player on the same phone |
| 3 | On Android, the system's download manager, into Downloads/VeloraUG | Background downloading, resuming and notifications come free. The files are where viewers look for them, and stay theirs |
| 4 | Android 9 and older are asked for storage permission once | Those versions need it to write to Downloads. Android 10 and newer don't ask |
| 5 | The pass is checked when a download starts, and never again | The owner's decision: the files are the viewer's to keep |

## What this means

- **Anyone holding a download's address can download the film for 24 hours**, without signing in. The address appears only in the viewer's browser or phone, but it can be shared.
- **Downloaded films can be copied and shared freely, and never expire.** Each VJ's permission should cover this, as well as the rights to the source film. See [Check before launch](roadmap.md#check-before-launch).
- **R2 storage roughly doubles** per film, since each quality is kept twice: as chunks for streaming, and as one file. At R2's price, about $0.015 per GB a month, 100 films at 2 to 5 GB each across all qualities adds roughly $3 to $8 a month. Downloads themselves cost nothing: R2 charges nothing for data leaving it.

## Making files for films already published

Run once on the server, after deploying. It goes through every ready film, fetches each quality's chunks from R2 into a scratch folder, joins them, uploads `download.mp4`, checks its size, and deletes the scratch folder. A quality that already has its file is skipped, so a run that stops can be started again. One quality failing doesn't stop the others.

```bash
cd /opt/veloraug/repo
docker compose -f infra/compose.prod.yaml exec media-worker python -m app.download_files --list
docker compose -f infra/compose.prod.yaml exec media-worker python -m app.download_files
```

The first lists what it would make. Until a film has its files, its Download says "This can't be downloaded yet".

## Checks done

- API: `tests/test_downloads.py` (10), `tests/test_download_files.py` (9), and new media worker and publisher tests, on a local Postgres. The full API suite passes.
- Media gateway: 5 new tests, 44 in all.
- App: 22 tests in `test/downloads/`. The full app suite passes: 468 tests. `flutter analyze` is clean.
- Builds: the web release with production settings, and an Android debug APK, which compiles the Kotlin.
- The FFmpeg join, run by hand on a real converted film in the media worker's image.

## Still to check

1. Deploy the API, worker and media gateway, run the backfill above on development, then on production.
2. **In Chrome, Edge and Firefox on a computer:** Download a movie in each quality. The file should land in Downloads with its name, and play in VLC and in Windows' own player.
3. **On an Android phone:** Download a movie and an episode. Check the notification, the progress in the Downloads tab, turning on flight mode part way through and off again, closing the app, and **Open**. Then find the file in the Files app under Downloads/VeloraUG.
4. On a phone with Android 9 or older, if one is available: the permission question, and refusing it.
5. With passes required: no pass offers **Choose a plan**, and a removed device can't start a download.
