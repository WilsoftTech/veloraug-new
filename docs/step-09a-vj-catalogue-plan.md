# Step 9A plan: the VJ catalogue and admin publishing

Date: 17 November 2026. This plans Milestone 9 in the [roadmap](roadmap.md). **Approved by the owner on 17 November 2026,** with the answers recorded [at the end](#the-owners-answers-17-november-2026). All SQL, routes and screens below are designs until the step that builds them reports.

## Why this milestone exists

VeloraUG is a streaming app for **Luganda-translated movies and series by Ugandan VJs**, with each VJ as a way to browse. The owner confirmed this on 17 November 2026. The catalogue built in [Milestone 6](step-06a-catalogue-plan.md) doesn't match it:

- it is keyed by TMDB film, with `tmdb_id` unique, so a film can't have two VJ editions,
- it has no VJs, no series and no episodes,
- the owner adds a film from TMDB *before* any video exists, and
- "languages other than English" were ruled out of Milestone 6.

**The video pipeline stays as it is.** Upload keys, tusd, FFmpeg, private R2, the Worker, grants and both players are kept, and the Worker deployed in 8E doesn't change at all.

## Summary

- **A source title can have many VJ editions.** *Fast X* is a source title. *Fast X · Luganda · VJ Junior* and *Fast X · Luganda · VJ Emmy* are two editions, each with its own video.
- **Every edition is a movie or a series.**
  - A movie edition has **one** playable item.
  - A series edition has **one playable item per episode**, numbered by season and episode, so **Next Episode** stays with the same VJ.
- **Upload first, describe after.** The admin starts an **upload draft** with:
  - the title as submitted,
  - movie or series,
  - optionally, the release year,
  - and for an episode, its season and episode numbers.

  The upload key is bound to that draft's item.
- **After the video is ready, TMDB fills in the details.**
  - The API searches TMDB for the submitted title and offers the source title, description, poster options and an official trailer.
  - **A clear match prefills the draft.** An unclear one, or a choice of posters, needs the admin to pick before publishing.
  - If TMDB finds nothing or is down, the draft waits. The admin can retry, give a TMDB ID, or type the details in.
- **The VJ credit comes after the upload too.**
  - The worker reads the file's name and its embedded tags, and the API suggests a VJ from them.
  - The admin previews the actual video and confirms or corrects the credit, or assigns it by hand when the credit is only spoken or on screen.
- **Processing and publishing are separate.** A converted video stays private until its details and VJ credit are approved and the admin publishes it.
- **Admin screens in the web app,** for signed-in admins only, so posters and previews can be seen. **Admins add and remove other admins in Settings.** The owner adds the first admin from the terminal, and can always add or remove one there.
- **Luganda first, other languages when there are editions in them.** Each edition has a language, chosen when the draft starts. On its page an edition is labelled **Luganda · VJ Junior**.
- **VJs have a name, photo and bio,** shown on their own page. **On poster cards, only the VJ's name shows,** as a label in the poster's top-left corner.
- **English menus and buttons for the first release,** with every string moved into Flutter's localization files, so Luganda can be added later without touching screens.
- **The four test films are deleted,** with their videos, once the first real edition is published.
- **Existing links keep working.**
  - Today's films become movie editions **with the same IDs**.
  - Videos stay at the same R2 paths, and grants keep the same format.
  - Unused upload keys and unfinished uploads carry on.

## Implementation sequence

| Step | Scope | Finished when |
| --- | --- | --- |
| **9A**, this step | This plan | The owner approves it. **Approved 17 November 2026** |
| **9B** | Migration `0005`: VJs, source titles, editions, items, upload drafts, admins, the editor role, and today's films moved across with their IDs. The worker and publisher use items. Credit hints from FFprobe | [9B criteria](#9b-database-and-pipeline) pass |
| **9C** | The API's admin routes: drafts and keys, preview grants, TMDB search and selection, VJ credit, publish and hide | [9C criteria](#9c-admin-api) pass |
| **9D** | The API's viewer routes: VJs, editions, seasons and episodes, search, and playback by item | [9D criteria](#9d-viewer-api) pass |
| **9E** | The app: localization set-up, the viewer screens (home, VJ, edition, episodes, Next Episode, search) and the admin screens on the web | [9E criteria](#9e-app) pass |
| **9F** | On Neon and Cloudflare: the migration, a real translated movie and a series of at least two episodes published through the admin screens, watched on the web and one phone | [9F criteria](#9f-end-to-end) pass |

Not in Milestone 9: payments (Milestone 10); uploading from the browser (the admin still uses `tools/veloraug_upload.py` with the key); several sound tracks in one video; subtitles; Luganda menus (only made possible); VJ accounts that upload or edit their own titles; ratings, favourites and watch history beyond Next Episode; playing trailers inside the app.

## Decisions

| # | Decision | Why |
| --- | --- | --- |
| 1 | **Source title → VJ edition → playable item.** A movie edition has one item; a series edition has one item per episode | One rule for what a grant, an upload key and an original belong to: an item. Next Episode follows the edition, so it follows the VJ |
| 2 | **An item keeps the role a movie had in R2 and in grants.** R2 paths stay `movies/<item ID>/<original ID>/…`, and a grant's `m` names the item | The deployed Worker, every published file and every live grant keep working unchanged. Only the meaning of the ID widens |
| 3 | **Today's films move across with the same IDs.** Each movie row becomes a source title, a movie edition and an item, the edition and item both taking the movie's ID | Existing app addresses, R2 paths, grants and upload keys stay valid with no copying |
| 4 | **Drafts first, details later.** The admin starts an upload draft with the title, type, optional year and, for episodes, season and episode numbers. The key is bound to the draft's item when it is made | As the owner set out: the details and the credit are decided once the real file exists |
| 5 | **Publishing needs four things:** a `ready` original, approved details (from TMDB or typed in), a chosen poster, and a confirmed VJ credit | Processing and publishing stay separate. A ready video can stay private as long as needed |
| 6 | **TMDB is the default source of details,** searched with the submitted title after the upload is ready. A clear match prefills; anything unclear waits for the admin | The owner's rules, below. TMDB's licence risk remains; typing details in is also the [fallback](step-06a-catalogue-plan.md#the-licence-risk) |
| 7 | **The displayed title is the submitted title,** which the admin can edit. TMDB's title is kept beside it as the source title | VJ editions are often known by their own names |
| 8 | **VJ credit is suggested, never applied by itself.** Suggestions come from the file's name and its embedded tags, matched to known VJs. The admin confirms, corrects, or assigns it by hand after previewing | Names in files are unreliable. A wrong credit is a real harm to a VJ |
| 9 | **One edition per source title per VJ.** Confirming a credit that would make a second one is refused, and the admin is pointed to the existing edition | Stops duplicate editions. A better copy replaces the video of the same edition, as in [Step 7F](step-07f-report.md) |
| 10 | **A series edition takes one VJ,** set from its first episode. Later episodes inherit it; an episode whose file suggests another VJ is flagged for the admin | Next Episode must stay with one VJ |
| 11 | **Admin screens are in the Flutter web app,** at `/admin`, shown only to admins. Not on Android in the first release | Posters and previews need a screen. One app, one sign-in, one design system |
| 12 | **Admins manage admins in Settings.** An admin adds another by email, and can remove any admin except the last one. Each change records who made it. The owner adds the first admin from the terminal (`catalogue.py admin add`), and can always add or remove one there, to recover from a mistake | The owner's choice. Neon Auth's own roles aren't needed. Keeping the last admin, and the terminal, means the catalogue can't be locked out |
| 13 | **The API's admin routes connect as a new role, `veloraug_editor`,** separate from `veloraug_app` | Viewer routes still can't change the catalogue even if a bug lets them run arbitrary SQL. The editor role can't touch profiles, Neon Auth or the schema |
| 14 | **Admins preview with the same grants,** issued by an admin route whatever the publish state | The Worker needs no change, and the preview is the real file, as converted |
| 15 | **Posters and backdrops come from TMDB's image servers,** as today. A poster for typed-in details, and every VJ's photo, is uploaded by the admin, stored in R2 under `posters/` or `vjs/`, and served by a new, public route on the Worker for images only | Typed-in details need a poster without TMDB. Existing Worker routes don't change |
| 16 | **Trailers are links,** to TMDB's official trailer on YouTube, opened outside the app | Playing YouTube inside the app brings YouTube's player terms. A link is enough for the first release |
| 17 | **English interface, ready for Luganda.** Flutter's `gen-l10n`, with every visible string in `app_en.arb`. Language names and VJ names are data, not strings | The owner's choice for the first release |
| 18 | **Today's four test films** stay published as editions with no VJ, marked as tests, until the first real edition is published. Then the owner **deletes** them: their videos are removed from R2 through the worker, as in Step 7F, and their rows deleted | Keeps 8E's checks and links working through the migration, then leaves only real editions. They never appear on VJ pages |
| 19 | **Each edition has a language,** from a `languages` list that admins can add to. Luganda (`lg`) is first and the default for a new draft | The owner wants Luganda, plus other languages when there are editions in them. Browsing by language appears once a second language has a published edition |
| 20 | **VJs have a name, photo and bio.** Poster cards everywhere show **only the VJ's name**, as a small label in the poster's top-left corner. The full label, such as **Luganda · VJ Junior**, is on the edition's page | The owner's choice. Two editions of the same film side by side are told apart at a glance |

### Routes ruled out

| Route | Why not |
| --- | --- |
| Keep `movies` and add a `vj` column | One edition per film, and no series |
| A separate catalogue entry per edition, each looked up from TMDB | Duplicates TMDB's data per VJ, and TMDB IDs would no longer be unique |
| New R2 paths, such as `editions/<id>/…` | Every published file would need copying, the Worker would change, and live grants would break |
| Several sound tracks in one video, one per VJ | VJ editions are usually complete separate files, sometimes edited, so they rarely share one video exactly |
| Applying the suggested VJ credit by itself | A wrong credit, published, is worse than a short wait for the admin |
| An admin command line only | Choosing between posters and previewing video need a screen |
| A separate admin website | A second app, sign-in and design system to maintain, for one or two admins |

## 1. Database

Migration `0005_vj_catalogue`. As always: hand-written SQL, row-level security forced on every new table, and nothing granted to `public`.

### New tables

| Table | What it holds |
| --- | --- |
| `vjs` | `id`, `name` ("VJ Junior"), `slug` (`vj-junior`, unique), `match_names` (other spellings for suggestions, such as `{"vj junior", "junior"}`), `photo_path` (stored in R2 under `vjs/`, served like uploaded posters), `bio` (up to 1,000 characters), `created_at`. Photo and bio are optional when the VJ is added, so a credit is never held up |
| `languages` | `code` (such as `lg`), `name` ("Luganda"). Starts with Luganda. Admins can add more |
| `sources` | One row per source title: `id`, `kind` (`movie` or `series`), `tmdb_id` (nullable; unique with `kind`), the details copied from TMDB or typed in (title, original title, overview, year, genres, poster and backdrop paths, trailer key), `details_from` (`tmdb` or `manual`), `fetched_at` |
| `editions` | `id`, `kind`, `source_id` (nullable until matched), `vj_id` (nullable until credited), `language` (from `languages`, `lg` by default), `display_title`, `submitted_year`, `poster_path` (the chosen one), `status`, `published_at`, `test` (true only for the four moved films). Unique on `(source_id, vj_id)` once both are set |
| `items` | `id`, `edition_id`, `season` and `episode` (both null for a movie, both set for a series), `episode_title`, `approved_at`, `created_at`. One item per movie edition; unique `(edition_id, season, episode)` for series |
| `tmdb_matches` | The candidates TMDB returned for an edition: TMDB ID, title, year, poster path, and whether the admin chose it. Cleared after publishing |
| `admins` | `user_id` (Neon Auth's), `email`, `added_by` (an admin's user ID, or null for the owner's terminal), `added_at`. A rule in the database refuses removing the last admin |

An edition's `status` is `draft`, `published` or `hidden`. Everything in between (waiting for upload, converting, needs details, needs a poster, needs a credit, ready to publish) is **worked out** from the data, not stored, so it can't go stale. See [the publishing flow](#3-the-publishing-flow).

### Changed tables

- `media_originals.movie_id` and `upload_keys.movie_id` become **`item_id`**, referencing `items`. The values don't change.
- `media_originals` gains `credit_hints`: up to 500 characters of the file's embedded `title`, `artist`, `album_artist`, `comment` and `description` tags, as FFprobe read them. The original `filename` is already stored.
- `media_renditions` doesn't change.

### Moving today's films across

In the same transaction, for each row in `movies`:

1. a `sources` row with its `tmdb_id`, and the details from `tmdb_movie_details`,
2. an `editions` row, kind `movie`, **with the movie's ID**, no VJ, `test = true`, and the same published state,
3. an `items` row **with the movie's ID**.

Then `movies` and `tmdb_movie_details` are dropped. *The Matrix*'s ready original still points at item `4e804389-…`, so its R2 files at `movies/4e804389-…/<original>/` and any live grant naming it keep working.

### Roles

| Role | Can |
| --- | --- |
| `veloraug_app`, the viewer side of the API | Read published editions, their sources and VJs, approved items of published editions, and the ID, item and state of their ready originals. Nothing about drafts, keys, matches or admins |
| `veloraug_editor`, new, the admin side of the API | Read and write VJs, languages, sources, editions, items and matches; make and revoke upload keys (storing only the hash); read originals and their hints; add and remove admins. No profiles, no `neon_auth`, no schema changes |
| `veloraug_media`, the worker and hooks | As today, with `item_id` for `movie_id`, plus writing `credit_hints` |
| `neondb_owner` | Migrations, and the owner's terminal commands, including `admin add` |

## 2. TMDB rules

When an item's original becomes `ready` for an edition with no source yet, the API looks it up.

1. **Clean the submitted title.** Remove VJ names known or in the form `VJ <name>`, the words "Luganda", "translated", "full movie", and quality tags such as `1080p`, `HD` or `HDRip`.
2. **Search.**
   - For a movie: TMDB's movie search, with the year if one was given.
   - For a series: TMDB's TV search, with the first-air year if one was given.
3. **Decide whether it's a clear match.** It's clear only when **exactly one** result has the cleaned title as its title or original title, ignoring case, punctuation and a leading "The", **and**, when a year was given, the same year.
   - **Clear:** the draft is prefilled with that result.
   - **Not clear:** the candidates go in `tmdb_matches`, and the admin chooses.
4. **Fetch the details:** title, original title, overview, year, genres, poster options and backdrop. For a series, also the season and episode names.
   - **Posters:** the eligible ones are in English or have no text. With more than one, **the admin must choose** before publishing.
5. **Fetch a trailer,** if there's one: the newest video that is on YouTube, has type `Trailer`, and is marked official.
6. **If TMDB finds nothing or doesn't answer:** the draft stays a draft and shows why. The admin can:
   - **retry,**
   - **give a TMDB ID,** which is checked by fetching it, or
   - **type the details in,** uploading a poster.

The submitted title remains the **display title**, and the admin can edit it. The exact TMDB search parameters and image-language filters are checked against TMDB's documentation at 9C.

TMDB's 6-month storage limit and 7-day refresh from [Milestone 6](step-06a-catalogue-plan.md) carry over to `sources`. The licence risk is unchanged: see [Check before launch](roadmap.md#check-before-launch).

## 3. The publishing flow

```text
Admin starts a draft            title, movie or series, year?, season and episode?
  -> edition (draft) + item + upload key, shown once
Uploader runs veloraug_upload.py with the key
  -> tusd -> hooks -> original "received"
Worker checks and converts (as in Milestone 7), reads credit hints
  -> original "ready", private in R2
API looks the title up on TMDB                    (section 2)
  -> details prefilled, or candidates to choose from
Admin opens the draft
  - previews the video (admin grant)
  - chooses the match and the poster, if asked
  - confirms or corrects the VJ credit            (section 4)
  - edits the display title, if needed
  -> Publish   (allowed only when all four are done)
Viewers see it
```

For a series, the first episode's draft creates the series edition. Each later draft picks that edition and gives a season and episode number. A new episode of a published series appears once its own video is ready and the admin approves it. The edition's details and credit are already done.

**Replacing a video** is a new draft for the same item. The old original is replaced exactly as in Step 7F, and the edition stays published throughout.

## 4. VJ credit suggestions

- **Where suggestions come from:**
  - the original file name, such as `Fast.X.2023.VJ.Junior.Luganda.1080p.mp4`,
  - the `credit_hints` from FFprobe, and
  - the submitted title.
- **How names are found:** a pattern finds `VJ` followed by one or two words, in any mix of dots, dashes, underscores and spaces.
- **How they're matched:** each name found is compared with every VJ's `name` and `match_names`, ignoring case, spaces and punctuation, so `VJ ICEP` matches **VJ Ice P**.
- **What the admin sees:**
  - the suggestions, with where each came from,
  - a preview player,
  - a list of all VJs, and
  - **Add a new VJ**.

  Nothing is credited until the admin confirms.
- **When nothing is suggested,** because the credit is only spoken or shown on screen, the admin chooses the VJ by hand after watching.

## 5. API

### Viewer routes (9D)

| Route | Answer |
| --- | --- |
| `GET /api/v1/vjs` | VJs with at least one published edition: name, slug, photo |
| `GET /api/v1/vjs/{slug}` | A VJ and their published movies and series |
| `GET /api/v1/editions?kind=&vj=&language=&genre=&q=&limit=&offset=` | Published editions, newest first, each with its VJ's name for the poster label. `q` searches display titles, source titles and VJ names |
| `GET /api/v1/editions/{id}` | One edition: label (`Luganda · VJ Junior`), VJ name, photo and slug, details, poster, trailer link, `playable`, and for a series its seasons and approved episodes |
| `POST /api/v1/items/{id}/playback` | A grant, as today. 401, 404, 409 and 503 as today |

`GET /api/v1/movies`, `GET /api/v1/movies/{id}` and `POST /api/v1/movies/{id}/playback` keep answering for the moved films until the app uses the new routes. They are removed at the end of 9E. A grant made by either route is the same.

### Admin routes (9C)

Every admin route needs a signed-in user listed in `admins`, and connects as `veloraug_editor`.

| Route | Does |
| --- | --- |
| `POST /api/v1/admin/drafts` | Starts a draft: title, kind, year?, and for an episode the series edition (or a new one), season and episode. Returns the upload key once |
| `GET /api/v1/admin/drafts` | Drafts and unpublished items, each with the step it is waiting for |
| `POST /api/v1/admin/items/{id}/preview` | A grant for the item's ready original, published or not |
| `POST /api/v1/admin/editions/{id}/tmdb/search` | Searches again, with an optional corrected title or year |
| `PUT /api/v1/admin/editions/{id}/source` | Chooses a match, a TMDB ID, or typed-in details |
| `PUT /api/v1/admin/editions/{id}/poster` | Chooses a TMDB poster, or uploads one |
| `GET /api/v1/admin/editions/{id}/credit` | The credit suggestions, with where each came from |
| `PUT /api/v1/admin/editions/{id}/credit` | Confirms a VJ, or creates one and confirms it |
| `POST /api/v1/admin/editions/{id}/publish`, `/hide` | Publishes, refusing with the list of what's missing, or hides |
| `POST /api/v1/admin/items/{id}/approve` | Approves a new episode of a published series |
| `GET/POST/PATCH /api/v1/admin/vjs` | Lists, adds and edits VJs, including the photo and bio |
| `GET/POST /api/v1/admin/languages` | Lists and adds languages |
| `GET/POST/DELETE /api/v1/admin/admins` | Lists, adds (by email) and removes admins. Removing the last admin is refused |
| `POST /api/v1/admin/keys/{id}/revoke` | As `catalogue.py revoke-upload` today |

The owner's terminal commands stay, and gain `admin add`, `admin remove`, `admin list` and `delete-test-films`. `delete-test-films` asks the owner to type `delete`, has the worker remove the test films' videos from R2, then deletes their rows.

**Adding an admin by email.** The person must already have signed in to VeloraUG once. The API looks for a Neon Auth user with that email, **and a verified address**, and adds them; otherwise it says the person must sign in first. Whether the email can be read from the sign-in token, or needs a call to Neon Auth, is checked at 9C. If neither is possible, Settings shows each user their own **account ID** to copy, and the admin adds that instead.

## 6. App

**Localization (first in 9E).** Add `flutter_localizations` and `gen-l10n`, move every visible string to `lib/l10n/app_en.arb`, and read them through `AppLocalizations`. The design system's components keep taking text from their callers. No Luganda strings yet.

**Viewer screens:**

| Screen | Shows |
| --- | --- |
| Poster cards, everywhere | The poster, with **only the VJ's name** in a small label at its top-left corner, readable over any poster, and announced by screen readers with the title |
| Home | Latest editions; a row per VJ; Movies and Series; a row per language once a second language has published editions |
| VJ | The VJ's photo, name and bio, then their movies and series |
| Edition | Poster and backdrop, display title, the label **Luganda · VJ Junior**, year, genres, overview, **Trailer** (opens YouTube), and **Watch**, or for a series the seasons and episodes |
| Player | As in Milestone 8, plus **Next Episode** at the end of an episode: the next number in the season, then the first episode of the next season, in the same edition |
| Search | Titles and VJ names |

**Admin screens, web only:**
- **Drafts:** a list showing what each draft is waiting for.
- **New draft:** title, movie or series, language, year, season and episode. Shows the key once.
- **Draft:** the preview player, TMDB candidates, poster choice, credit suggestions and **Publish**.
- **VJs:** add or edit a VJ's name, photo, bio and other spellings.
- **Settings → Admins:** add an admin by email, remove one, and see who added whom.

The **Admin** entry in the menu shows only for admins.

## 7. Looking ahead to Milestone 10: passes

The owner's direction for Milestone 10:
- **The passes:** prepaid daily, weekly and monthly catalogue passes, through Pesapal.
- **What's left out at first:** pay per title and automatic renewal. Prices stay open.
- **What Milestone 10 proves first:** **one sandbox pass**, to show that payment is confirmed, playback is allowed, and the pass expires.

**How it fits the 6-hour grants:** today, `POST …/playback` signs a grant that expires 6 hours after it's made. With passes, the API would sign it to expire at **whichever comes first: 6 hours from now, or the end of the viewer's pass**. So **no grant outlives the pass**.

| Part | Change |
| --- | --- |
| The Worker | **None.** It already refuses an expired grant on every chunk |
| The grant route | Checks for an active pass and answers **402** without one. Caps the expiry at the pass's end |
| The player | Already renews an expired grant once, keeping the place. At the pass's end the renewal answers 402, and the player shows "Your pass has ended" with a way to buy one, instead of "Try again". After buying, playback carries on from the same moment |
| Admin previews | Not capped by passes |

**What viewers would notice:**
- **Just after a pass ends:** a viewer can keep watching only what their player has already buffered, usually under a minute. After that, every chunk is refused.
- **A shared address:** it still works for anyone holding it, but now only until the pass ends, never past it.

## Acceptance criteria

### 9B database and pipeline

- Migration `0005` runs on a local Postgres set up as Neon is, and again on a copy of today's data:
  - the four films become editions and items with the same IDs,
  - *The Matrix*'s original keeps its item, and
  - an unused key and an unfinished upload still work.
- Database checks cover each role:
  - the viewer role sees only published, approved things,
  - the editor role can't read profiles, `neon_auth` or change `admins`, and
  - the media role works as before.
- The worker stores credit hints, and publishes to the same R2 paths.

### 9C admin API

- Tests for:
  - non-admins refused,
  - adding and removing admins, and removing the last admin refused,
  - adding a language, and a VJ with a photo and bio,
  - a draft and its key,
  - preview grants,
  - each TMDB outcome: a clear match, an unclear one, nothing found, TMDB down, a manual ID and typed-in details,
  - poster choice required,
  - credit suggestions from names and tags,
  - duplicate editions refused,
  - publishing refused with what's missing,
  - episode approval.

### 9D viewer API

- Tests for VJs, editions, filters, search and series episodes.
- Drafts and hidden editions are never shown.
- Playback by item, and by the old movie route for moved films.

### 9E app

- Widget tests for:
  - each viewer screen, signed in and out,
  - Next Episode, including across seasons,
  - the admin screens hidden from non-admins,
  - each draft state.
- Every visible string comes from `app_en.arb`.
- The web build and a debug APK build.

### 9F end to end

- On Neon and the deployed Worker, all through the admin screens:
  - **a real translated movie** and **a series of at least two episodes**, both of which the owner has the right to use, are drafted, uploaded, matched on TMDB, credited and published.
  - At least one of them has its credit corrected or assigned by hand.
- Both are watched on the web and one phone.
  - **Next Episode** moves to episode 2 of the same VJ.
  - *The Matrix*'s existing link still plays.
- Poster cards show the VJ's name at the top left, and the VJ's page shows the photo and bio.
- A second admin is added from Settings by the first, and can publish. Removing the last admin is refused.
- Then the owner runs `delete-test-films`. The four films are gone from the app, their videos are gone from R2, and their old links answer `404`.

## Risks

| Risk | What happens |
| --- | --- |
| **Rights to VJ translations** | Showing one legally needs the rights to the source film **and** the VJ's permission. Many VJ films in circulation have neither. Cloudflare and Pesapal can close accounts over copyright complaints. Each published edition should have both on file. Added to [Check before launch](roadmap.md#check-before-launch) |
| TMDB's licence | Unchanged from Milestone 6: no commercial use without an agreement. Typed-in details are the fallback, and work without TMDB |
| Titles TMDB can't find | Remade, renamed or local titles. The draft waits; manual ID or typed-in details |
| A wrong VJ credit | Only the admin can credit, after previewing. Credits can be corrected after publishing |
| More admin power in the API | Admin routes use their own role, check `admins` every time, and can't reach accounts or the schema |
| An admin account is taken over | Whoever holds it can publish, hide and add admins. Every admin change records who made it, and the owner can remove any admin from the terminal. Two-step sign-in for admins can follow when Neon Auth's is set up |
| Migration on live data | Rehearsed on a local copy, then on a throwaway Neon branch, before the development branch |

## The owner's answers (17 November 2026)

| Question | Answer | Where it is in this plan |
| --- | --- | --- |
| VJ photo and bio, or just the name? | All three. Only the name appears on posters, as a label at the top left | Decision 20, `vjs`, poster cards |
| Luganda only? | Luganda, plus other languages when there are editions in them | Decision 19, `languages` |
| Hide the four test films once the first real edition is published? | Delete them | Decision 18, `delete-test-films`, 9F |
| Who else will be an admin? | Admins can add other admins in Settings | Decision 12, `admins`, Settings → Admins |
