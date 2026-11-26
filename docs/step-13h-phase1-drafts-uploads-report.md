# Step 13H, Phase 1: Drafts and Uploads

Written and built on 26 November 2026, as Phase 1 of the admin panel upgrade. Built on `main` after Step 13G. **Not yet deployed or checked against Neon. No screenshots were taken:** the screens were checked with widget tests, not in a browser against a running API.

## What an admin sees now

### Drafts

- **Only drafts with a finished upload are listed.** A draft whose videos are all still uploading, or that has no video yet, moves to a folded section at the bottom, **"N drafts still uploading"**. It shows each one's upload percentage when this browser is uploading it, and a **Go to Uploads** button.
- **Each video shows its stage as a bar** once it has finished uploading:

  | Stage | Bar | Text |
  | --- | --- | --- |
  | Waiting to convert | Empty | "Number 2 in line" |
  | Checking the file | Moving, with no figure | "Takes a few seconds" |
  | Converting | 0 to 99% | "40% · 2 min left" |
  | Sending to the server | 0 to 99% | "80% · 1 min left" |

  A series shows at most 3 bars, then "and N more videos". Failed and refused videos are listed in red with their reason. **The list refreshes every 5 seconds** while any video is in one of these stages, and stops when none is.
- **Delete permanently**, from each draft's ⋮ menu and from the bottom of the draft's own page. It asks first, names the title, and says it can't be undone. Published titles have no Delete here: hide them first. Deleting from the Library comes in Phase 2.
- **Delete all drafts**, at the top. It says how many will go, and that published and hidden titles stay. The button stays off until **DELETE** is typed.

### New draft

**New draft** now opens a full page instead of a small dialog:

1. **Movie or series.** For a series, it adds to an existing series or starts a new one, with season, episode and episode title. An episode number the series already has is refused before anything is sent.
2. **Title and VJ, both required.** A VJ can be added on the spot. Language and year are here too.
3. **Details:** *Find on TMDB* (the default, searched at once), *Type the details in* (description, genres, running time), or *Later*.
4. **Categories**, with the same input and suggestions as the draft page.
5. **Poster**, optional: JPEG, PNG or WebP, up to 2 MB.
6. **Video:** choose the file, and it joins the Uploads queue using the draft's own upload key. Without a file, the upload key is shown once, as before, for whoever has the file.

**Create draft** makes the draft, then saves each part in turn. If one part fails, such as the VJ credit, the others are still saved. The draft opens and the message names what wasn't saved. Existing series skip steps 2 to 5, since the series already has them.

### Uploads

- **Pause all, Resume all, Remove all** sit above the queue, with a summary line such as "2 running · 1 of 3 finished · 1.2 GB of 3.4 GB". Each button is greyed out when it has nothing to do.
- **Remove all** asks first. It stops every upload, deletes each one's part from tusd, and clears finished uploads from the list. Their drafts stay.
- **Resume all** skips files too large to upload, and uploads whose removal failed.
- **Each upload already showed its %, speed, time left, and a Try again for failures.** That's unchanged.

## Decisions to review

| Question | Decision | Why |
| --- | --- | --- |
| Where do incomplete uploads go? | A folded section at the bottom of Drafts, not only the Uploads tab | An upload started from another browser, or by a VJ with a key, isn't in this browser's queue. Hiding it from Drafts completely would leave no way to see or delete it. Folded, it stays out of the way |
| Which drafts count as complete? | Any with at least one video past uploading, **including failed ones** | A failed conversion needs the admin's attention, so it belongs in the main list |
| % while checking | **None**, a moving bar | FFprobe gives no progress, and checking takes seconds. A made-up percentage would break the "never fake it" rule |
| Where conversion % comes from | FFmpeg's own `-progress` output: time converted ÷ the film's length | Real, and costs nothing extra. Tested against real FFmpeg, not only the fakes (see below) |
| Where sending % comes from | Bytes sent to R2 ÷ all bytes to send | Real. One report per file |
| Time left | The time so far in this stage, scaled to what's left | Uses the worker's own clock. None is shown before the first 1% |
| How often progress is written | At most every 5 seconds, or sooner after a 5-point jump | A 2-hour film costs about 30 small updates. A failed write is logged and never stops the conversion |
| Delete all and hidden titles | **Kept.** Delete all deletes drafts only | Hidden titles were published once and may have viewers. Each can still be deleted one at a time |
| Test films | Refused, with "Test films are deleted with the owner's script" | That script already handles them in two runs |
| Trailer link | **Not added** | Editions have nowhere to keep one; trailers come from TMDB. It needs a new column, and is better decided with Phase 2's edit form |
| "Save progress as you go" | Each part is saved separately when Create is pressed | The form doesn't keep half-typed values between visits. Once created, the draft holds everything, and its page shows what's missing |

## How deleting works

Deleting has to remove files from R2 and this computer, which only the media worker can do. So it happens in two steps, as `delete_test_films` already did:

1. **At once:** the edition is marked deleted, so no list shows it and viewers never see it. Its unused upload keys are revoked, and its videos are marked `removing`. A video still being checked or converted is left to finish first, because the worker would only put it back.
2. **Soon after:** the media worker deletes each video's files. Once all are gone, the rows are deleted: the edition, its items, keys and videos, viewers' history of it, and its source if nothing else uses it. This tidy-up runs on every worker loop and whenever Drafts loads.

Two new database functions, `delete_edition` and `purge_deleted_editions`, do this as the database owner. That's because the editor role can't change a video's state or delete rows, and still can't. The worker also tidies up *before* picking up its next video, so a deleted draft's upload is never converted.

Every delete is logged as an audit event: `edition_deleted` with the admin's and edition's IDs, or `drafts_deleted` with the count.

## What changed

| File | Change |
| --- | --- |
| `migrations/versions/0015_draft_progress_and_deleting.py` | `editions.deleted_at`; `media_originals.progress` and `progress_at`, which the media role may write; the two delete functions |
| `app/admin_catalogue.py` | Each video's progress, time left, place in line and size. Each edition's `incomplete`. Deleted editions are left out of every list. `delete_edition`, `delete_all_drafts`, `purge_deleted` |
| `app/admin.py` | `DELETE /admin/editions/{id}`, and `POST /admin/drafts/delete-all`, which needs `{"confirm": "DELETE"}`. Drafts tidies up as it loads |
| `app/editions.py` | A deleted series takes no new episodes, and a deleted edition can't be published |
| `app/media_worker.py` | Reads FFmpeg's progress line by line, and writes the percentage. Tidies up deleted editions |
| `app/media_publisher.py` | Reports the share of bytes sent |
| `app/audit.py` | `edition_id` may be logged |
| `lib/admin/drafts_view.dart` | The new Drafts list: stages, the incomplete section, the menu, the deletes, and the refresh |
| `lib/admin/new_draft_screen.dart` | New: the New draft page |
| `lib/admin/admin_common.dart` | `confirm` can be a danger action and can ask for a typed word. `VideoStageProgress`. `checkNumber` moved here |
| `lib/admin/draft_screen.dart` | Delete permanently, for drafts |
| `lib/admin/uploads/upload_queue.dart` | `pauseAll`, `resumeAll`, `removeAll`, `removeForEdition`, and `addToItem`, which uploads into a draft that already exists |
| `lib/admin/uploads/uploads_view.dart` | The bulk bar |
| `lib/api/admin_api.dart` | The new fields, `deleteEdition` and `deleteAllDrafts` |
| `lib/l10n/app_en.arb` | 51 new strings |

## Deploying

1. **Run migration 0015 first**, then deploy the API and the media worker.
2. Until the new worker is running, videos being converted show a moving bar with no figure. Nothing breaks.
3. A worker without R2 set up, as in local development, never removes files. So deleted drafts with videos disappear from every screen at once, but their rows stay until R2 is set up.

## How to test it

1. Upload two films from Uploads. Press **Pause all**, then **Resume all**, then **Remove all**, then Cancel. Each should do what it says.
2. While they upload, open Drafts. Both are under "2 drafts still uploading", with their percentages.
3. When one finishes, it moves to the main list. Watch it go through *Waiting to convert*, *Checking the file*, *Converting* with a percentage and time left, and *Sending to the server*, without pressing Refresh.
4. Press **New draft**. Fill in a movie with a VJ and choose a video. Press Create. The draft opens and the video appears in Uploads.
5. Delete that draft from its ⋮ menu. It disappears at once, and its upload stops. A minute later its rows are gone: `select * from public.editions where deleted_at is not null` returns nothing.
6. Press **Delete all drafts**. The button stays off until DELETE is typed. Hidden and published titles are still listed afterwards.

## Checks done

- **API:** 787 tests pass, 1 skipped, with 25 new. `ruff check` and `ruff format --check` are clean.
  - `tests/test_admin_drafts.py` (11): progress, time left and place in line; no time shown before the first report; which drafts are incomplete; deleting for good once the files are gone; a draft without a video goes at once; a converting video is left to finish; published and test titles are refused; only admins can delete; a deleted series takes no episodes and can't be published; Delete all needs the word, and keeps hidden titles; Delete all needs an admin.
  - `tests/test_media_worker.py` (13): the FFmpeg command asks for progress; progress lines become percentages (8 cases); none without a length; progress reported while converting; written now and then, never backwards, and only while working; a deleted draft's upload is never converted, and its rows go once its file is removed.
  - `tests/test_media_publisher.py` (1): sending reports the share of bytes sent.
- **Real FFmpeg:** the new streaming code was run, in the local media worker's container, on a 40-second 720p test film converted to 360p and 720p. FFmpeg exited cleanly with every playlist made, and sent 42 progress reports, rising from 1% to 99%.
- **App:** 695 tests pass, with 18 new, and `flutter analyze` is clean.
  - Drafts (2): stages, percentages, time left and place in line; refreshing while converting, and stopping after.
  - Deleting (5): one, after confirming; cancelling; no Delete for a published title; Delete all only once DELETE is typed; deleting from the draft's page.
  - New draft (5): a title and VJ are needed; a movie with its VJ and TMDB details, its key shown once, then the draft opens; typed details, with a failed part named; an episode added to an existing series, never twice; a narrow phone with large text.
  - Uploads (2): pause, resume and remove all at once; Remove all can be cancelled.
  - Upload queue (5): a file for an existing draft uses its item and key; without its key, a new one is made for that item; pause, resume and remove all; Resume all leaves a file that's too large; deleting an edition removes only its own uploads.
  - The old New draft dialog test was replaced.
