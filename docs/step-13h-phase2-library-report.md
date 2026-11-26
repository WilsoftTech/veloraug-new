# Step 13H, Phase 2: The Library

Written and built on 26 November 2026, as Phase 2 of the admin panel upgrade. Built on Phase 1 (pull request #21), which isn't merged yet, so this pull request is based on Phase 1's branch. **Not yet deployed or checked against Neon. No screenshots were taken:** the screens were checked with widget tests, not in a browser against a running API.

## What an admin sees now

### The Library tab, next to Uploads

Every title viewers can see, or once could: **published**, **hidden**, and **withdrawn** (back to a draft after being published). Test films and deleted titles are left out.

- **Search** by title, by the film's original title, or by VJ.
- **Filter** by state, kind (movies or series), VJ and category.
- **Sort** by newest, oldest, title, most viewers, or recently changed.
- **Each row shows:**
  - poster, title and year
  - kind, VJ and categories
  - publish date (with the year)
  - **viewers in the last 30 days**
  - for a series: its episodes, how many are hidden, and how many are waiting for approval
  - a state badge.
- **50 titles at a time**, with *Show more*.
- **Each title's ⋮ menu:** Edit, Hide or Show again, Withdraw, Delete permanently.
- **Tick titles, or tick all those shown,** to Hide, Show again, Withdraw or Change VJ for all of them at once. Each title is changed on its own. Any that can't be are listed with the reason, such as "Commando: Only a published title can be hidden" or "Still needs a chosen poster".

### A title's page

The Library opens the same editor as Drafts, which now also has:

- **What viewers see:** year, language, description, trailer (any YouTube address) and backdrop (upload your own, or go back to TMDB's). **These are this title's own.** TMDB's details are shared by every VJ's edition of the same film, so editing them directly would change other VJs' titles too. A field left empty shows TMDB's, or the typed-in details, as before. Only what changed is saved. The trailer link deferred in Phase 1 is here.
- **Publishing:**
  - Hide, Withdraw and Delete permanently for a published title.
  - Show again and Withdraw for a hidden one.
  - Show again for a withdrawn one, which keeps its first publishing date, so it goes back to its old place among the newest.
- **Each episode's menu:** Edit (season, episode and title), Hide or Show, Withdraw (back to waiting for approval in Drafts), and Delete. Delete isn't offered for a series' only episode.

### What viewers notice

| Action | Viewers |
| --- | --- |
| Hide | Gone from every list, search and page at once. Show again restores it exactly |
| Withdraw | The same, and the title waits in Drafts. Nothing is deleted |
| Delete | Gone at once, and its files are removed from R2 within the worker's next minute or so |
| Hide or withdraw one episode | Only that episode disappears from the series |
| Any of these | **Copies already downloaded are the viewer's.** Downloads are never checked again once saved (Step 12A), so they can't be taken back. Watch history is kept, but the title leaves Continue watching and every list while it isn't published. The confirmation messages say this |

## Decisions to review

| Question | Decision | Why |
| --- | --- | --- |
| Edit TMDB's details, or the title's own? | The title's own description, backdrop and trailer, shown over TMDB's | A TMDB film is shared by every VJ's edition. Editing it directly would change other VJs' titles |
| Withdraw vs Hide | Hide keeps it published-but-hidden. Withdraw sends it back to Drafts | As asked. Both are undone with Show again |
| Delete a published title | Allowed from the Library and its page, **only after typing DELETE** | It's the most harmful action. The message also suggests hiding instead |
| Episode delete | Allowed, except for a series' only episode, and not for a movie's video | A series with no episodes, or a movie with no video, would be broken. Delete the title instead |
| A deleted episode's number | Stays taken until its files are removed, usually within a minute | The rows go only after the files, as in Phase 1 |
| Reordering episodes | Edit an episode's number: a number another episode has **swaps** the two | Simple, and nothing can end up with no number |
| Viewer counts for admins | Admins may now run `edition_viewers`, which gives **counts only**, never who watched | A test asserted the opposite, written when only viewers needed it. It now says admins may |
| Hidden titles' viewers | Shown as 0 | The count covers what viewers can watch now |
| Featured on the home hero | **Proposed, not built** | Home's hero shows the newest titles. A "Feature" switch would need a column and a change to Home. Worth doing alongside Phase 5's settings |
| Scheduled publishing | **Proposed, not built** | It needs a publish time and something to run at that time, such as the media worker's loop. A good small follow-up |

## Also fixed

Two kinds of problem from Phase 1:

1. **CodeRabbit's review of #21.** Nine points, all fixed on Phase 1's branch; see the Phase 1 report.
2. **The Drafts list overflowed** on a 320-pixel phone with large text: a draft's status badge didn't fit beside its title. The Library's test found it. The badge now sits under the draft's details, as in the Library.

## What changed

| File | Change |
| --- | --- |
| `migrations/versions/0016_library.py` | `editions.overview`, `backdrop_path`, `trailer_key`; `items.hidden_at`, `deleted_at`. The viewers' rule for episodes leaves out hidden and deleted ones. `delete_item`, and the purge also clears deleted episodes. Admins may count viewers |
| `app/admin_catalogue.py` | `list_library`, `update_details` (with `trailer_key`, which reads YouTube addresses), `withdraw`, the episode actions (hide, show, withdraw, delete, renumber with swap), `bulk_change` |
| `app/admin.py` | `GET /admin/library`, `POST /admin/library/bulk`, `POST /editions/{id}/withdraw`, `PATCH /editions/{id}` takes every detail, `DELETE /editions/{id}?published=true`, `PATCH`/`DELETE /items/{id}`, `POST /items/{id}/hide`, `/show`, `/withdraw`. Edits, withdrawals, deletes and bulk changes are audit-logged |
| `app/viewer.py`, `app/images.py` | Viewers get the title's own description, backdrop and trailer when it has them. Uploaded backdrops get addresses |
| `app/editions.py` | Publishing again doesn't approve deleted episodes |
| `lib/admin/library_view.dart` | New: the Library tab |
| `lib/admin/draft_screen.dart` | What viewers see, Show again, Withdraw, deleting a published title, and the episode menu |
| `lib/admin/admin_screen.dart` | The Library tab, after Uploads |
| `lib/admin/drafts_view.dart` | The badge sits under the details |
| `lib/api/admin_api.dart` | The Library, details, withdraw, bulk and episode calls |
| `lib/l10n/app_en.arb` | 75 new strings |

## Deploying

Run migration **0016** before the API. The worker needs no change: deleted episodes are purged by the purge function it already calls. Phase 1's migration 0015 must be there first.

## How to test it

1. Open **Library**. Every published title is listed with its viewers. Search for a VJ's name: their titles are listed.
2. Tick two titles and press **Hide**. Both are hidden, and gone from the app's Home. Press **Show again**: they're back.
3. Open a title and fill in **Description** and **Trailer** with a YouTube address. Press **Save details**. The app's page for it shows both. Empty them and save: TMDB's are back.
4. **Withdraw** a title. It's in Drafts and the Library ("Withdrawn"), and gone from the app. Press **Show again**: it's back in its old place among the newest.
5. In a series, **hide** one episode. It's gone from the app's episode list. Edit another episode's number to one already used: the two swap.
6. **Delete permanently** a published title. The button stays off until DELETE is typed.

## Checks done

- **API:** 814 tests pass, 1 skipped, with 25 new in `tests/test_admin_library.py`:
  - trailer addresses read (7 cases) and others refused (3)
  - the Library lists the right titles in the right states, with viewers and episodes
  - searching, filtering, sorting and pages
  - bad filters refused, and admins only
  - a title's own details shown over its source's, and cleared back
  - bad details refused
  - withdrawing and showing again
  - deleting a published title only when asked plainly
  - an episode hidden and shown
  - withdrawn to wait for approval
  - deleted once its video is gone
  - a movie's video and a series' only episode refused
  - episodes renamed and swapped
  - bulk changes each on their own, with reasons, credits and show
  - a title that isn't ready isn't shown again, and says why
  - bulk requests checked.
  
  `ruff check` and `ruff format --check` are clean.
- **App:** 713 tests pass, with 13 new.
  - **Library (9):** rows and their facts; search, filters and sort sent to the server; Show more; hiding many, with skipped titles named; crediting many; withdrawing, with the downloads warning; deleting a published title only once DELETE is typed; Show again from the menu; a narrow phone with large text.
  - **A title's page (4):** only changed details are saved; Hide, Withdraw and Delete for a published title; a hidden title says so and offers Show again; each episode edited, hidden, shown, withdrawn and deleted.
  
  `flutter analyze` is clean.
