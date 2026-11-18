# Step 9G: run sheet for browser uploads

The owner's checks for **Admin → Uploads**: drag and drop, the naming guide, progress, pause, resume, retry, remove, and carrying on after a lost connection, a closed tab and a power cut. How it works is in the app's README, under [Uploads from the browser](../apps/client/README.md#uploads-from-the-browser).

Use short test clips you are allowed to publish, or real translated films. Each upload makes a real draft on Neon: hide the ones you don't want afterwards.

## 1. Start everything

From the repository root:

```powershell
docker compose -f infra/compose.local.yaml --profile uploads up --build -d
```

This rebuilds the API, which has the new `GET /api/v1/admin/series` route, and the upload hooks, which have the new check for **Remove**. tusd restarts with its new settings. Then run the app in Chrome on port 8765, as for 9F:

```powershell
cd apps\client
flutter run -d chrome --web-hostname localhost --web-port 8765 --dart-define-from-file=dart_defines.local.json
```

`UPLOAD_BASE_URL` defaults to `http://127.0.0.1:1080/files/`, so the file needs nothing new.

Check: **Admin** has a fourth tab, **Uploads**, with a drop area and **How to name files**.

## 2. Names, and several files at once

Name three files by the guide, for a VJ you have already added in **VJs**:

```text
VJ Junior - Commando (1985).mp4
VJ Junior - Kabaka S01E01.mp4
VJ Junior - Kabaka S01E02.mp4
```

Drag all three onto the page, with a text file as well.

Check:

- The page lights up while you drag. The text file is left out, and a message says so.
- Each row is filled in: *Commando*, a movie, 1985, VJ Junior; the two episodes as a new series *Kabaka*, season 1, episodes 1 and 2.
- **Start 3 uploads**: two start at once, each with a bar, a percentage, MB sent, speed and time left. The third waits.
- **Drafts** shows *Commando* credited to VJ Junior, and *Kabaka* as **one** series with two episodes.

## 3. Pause and resume

While a file is uploading, press **Pause**. Check that it says **Paused at N%**. Wait a minute, then press **Resume**. It should carry on from N%, not from 0%.

## 4. A lost connection

While a file is uploading, turn off Wi-Fi, or pull the cable. Check that it says **Offline** or **Connection lost**, with the percentage it reached. Turn the network back on. It should carry on by itself within a few seconds, from that percentage.

## 5. A closed tab, or a power cut

While a larger file is at about 30% or more:

1. Close the tab. Chrome asks **Leave site?**: leave.
2. For a real power cut, switch the PC off at the wall instead.
3. Start Chrome and the app again, and open **Admin → Uploads**.

Check:

- The upload is listed: **Stopped at N% when the page closed**.
- **Resume**, then **Allow** when Chrome asks about the file. It carries on from N%.
- Edge works the same. In another browser, drop the same file again instead, and it carries on.
- In **Drafts**, there is still only one draft for it.

## 6. Remove

Start an upload, then press **Remove** and confirm. Check:

- It disappears from the list.
- `services\worker\uploads\` no longer has its partial file. The newest file there is named by the upload's ID.
- `catalogue.py uploads`, from `services\api`, shows it as `removed`.
- Its draft is still in **Drafts**, with no video. Hide it, or give it a new upload.

## 7. Once processed

When the uploads from step 2 show **Uploaded**, open their drafts from **Open draft**. Check that the video goes on to **Converting**, then **Ready**, as with the upload script.

## What to send back

- For each step: passed, or what you saw instead.
- Which browsers you tried for step 5, and whether you did a real power cut.
- Anything confusing on the screen.
