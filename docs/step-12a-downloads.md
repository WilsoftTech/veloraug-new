# Step 12A: Downloads for watching offline

Written and built on 23 November 2026, at the owner's request to implement movie downloads, UI and functionality. **Not yet approved, and not yet checked on a phone.** Code only: not deployed.

## What viewers get

On **Android only**, a signed-in viewer can download a movie, or any episode, to watch without a connection.

- **Download** sits beside **Watch** on a movie's page, and a download icon sits beside each episode's play button. Tapping it gets the download ready, then offers each quality with about how much room it takes, such as "720p, About 1.2 GB".
- While it downloads, the button shows its progress. When it's done, the button reads **Downloaded**, and tapping it plays the film from the phone.
- A **Downloads** tab, between Search and Account, lists every download: poster, title, VJ label, quality, size, progress, and how long it plays offline. Each has pause, resume, try again, delete (confirmed) and play. The tab also shows how much room downloads take.
- Downloads are not offered on the web. Browsers stream only.

## How it works

| Part | What it does |
| --- | --- |
| `POST /api/v1/items/{id}/download` | The same checks as playback: published and ready, and with passes required, a running pass, this device registered and no more devices than the plan allows. It returns a grant **with no playback session**, for one hour and never past the pass, and `offline_until` |
| `POST /api/v1/me/offline-licences` | Renews `offline_until` for up to 200 items at once. `null` for an item taken down. `402`, `403` or `409` if the device may keep none |
| Media gateway | **No change.** A grant without a session is served exactly as before |
| App: `lib/downloads/` | Fetches one quality's playlist, its init file and its chunks from the media gateway, three at a time, and keeps them in the app's private storage, laid out as on the gateway. The kept master playlist names only that quality. The player opens it as a `file://` address |

### Decisions

| # | Decision | Why |
| --- | --- | --- |
| 1 | A download's grant has no playback session | A session would take one of the viewer's streams for as long as the download ran. It would also replace the player's session on the same phone, so watching one thing while downloading another would stop one of them. The download checks pass and devices when it starts, and again whenever its one-hour grant runs out |
| 2 | Downloads play offline for **7 days** at most (`OFFLINE_DAYS`), and never past the end of the viewer's passes | Long enough for a trip, short enough that an ended pass or a removed device stops downloads soon. The app renews every licence at once when it's online, at most every 6 hours |
| 3 | A title taken down is deleted from the phone at the next check-in | Rights can be withdrawn |
| 4 | An ended pass, too many devices or a removed device stops downloads playing, but keeps their files | Buying a pass or removing a device makes them play again, without downloading again. A device that was removed registers itself again on its next check-in, as playback already does, within the device-switch limit |
| 5 | One quality per download, chosen by the viewer | Phones have little room. One fixed quality also plays the same with no connection |
| 6 | One download at a time, three files at once, each file written whole and then renamed | A pause, a lost connection, the app being closed or a power cut loses at most the files being fetched. The download carries on from the last whole file |
| 7 | A lost connection is retried by itself: 15 seconds, then longer each time, up to 5 minutes | Ugandan mobile data drops often |
| 8 | A clock turned back by more than an hour stops downloads playing until the app checks in | Otherwise turning the clock back would extend a licence |

## What this does not protect against

Downloads are **not encrypted and not DRM-protected.** The files are ordinary HLS in the app's private storage. Other apps can't read them, they aren't backed up (`allowBackup` is off), and uninstalling the app removes them. But someone with a **rooted** phone could copy them out and play them anywhere, with no expiry. The 7-day limit is enforced by the app, not by the files.

This is the same trust the streaming side already places in the app: a grant's address can be copied too. If rights holders require more, the next step is Widevine DRM with offline licences, through a DRM provider. That is a larger change to the media worker, the gateway and the player, and has a monthly cost.

## Known limits

- **Downloads run while the app is open.** Android may stop them soon after the app goes to the background, and always when it is closed. They carry on from where they stopped the next time the app opens. A background download service with a notification is the next step if viewers need it.
- **Downloads aren't tied to the account.** Signing out, or signing in as someone else on the same phone, leaves them in the Downloads tab. They still need the device's check-in every 7 days, so they stop if that device's account loses its pass or removes the device.
- **No check of free space before starting.** A full phone stops the download with "Your phone is full", and keeps what it has.
- The size shown before downloading is an estimate, from the playlist's average bitrate and length.

## Checks done

- API: 9 new tests in `services/api/tests/test_downloads.py`, on a local Postgres set up as Neon is: passes off and on, no pass, no device, a removed device, a pass ending, a title taken down, admins, at most 200 licences, and **a download never stops the player or takes a stream**. The whole API suite passes: 609 tests.
- App: 33 new tests in `apps/client/test/downloads/`: playlist parsing that refuses anything the media worker doesn't write, downloading, carrying on after the app closes (only the missing files are fetched), renewing a refused grant, retrying, a full phone, pause, resume and delete, every licence case, and the screens. The whole app suite passes: 478 tests. `flutter analyze` is clean.
- Both builds compile: the web release, and an Android debug APK (`--flavor dev`).

## Still to check, on a phone

Not done: no phone or emulator was connected. **Playing a download on a phone is unverified.** The player hands ExoPlayer a `file://` address to the kept master playlist, with the HLS hint. ExoPlayer's default data source reads `file://` addresses, and that is how video_player 2.12 builds its media source, but it hasn't been run.

1. Install the dev build on the phone, with passes off, against the development API and Worker. Sign in.
2. Open a movie. Tap **Download**, check the qualities and sizes, and choose 360p.
3. Watch the button count up. Open **Downloads** and check the progress bar, then **Pause** and **Resume**.
4. While it downloads, turn on flight mode. It should say **Waiting for a connection**, then carry on by itself once flight mode is off.
5. Close the app part way through, and open it again. It should carry on from where it was, not from the start.
6. When it says **Downloaded**, turn on flight mode and tap it. The film should play, and seeking should work.
7. Download an episode from a series. Check its icon shows progress, then a tick.
8. Delete a download, and check the room shown in the Downloads tab goes down.
9. With passes required (the 10E run sheet's set-up), check that a viewer without a pass is offered **Choose a plan** instead of qualities, and that removing the phone in **My devices** from another device stops its downloads playing after **Check now**.
