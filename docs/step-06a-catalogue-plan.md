# Step 6A plan: movie catalogue

Date: 10 November 2026. This plans Milestone 6 in the [roadmap](roadmap.md). **Milestone 6 is not complete, and nothing here is implemented.** No TMDB account or key exists yet, no migration was written or run, and no dependency was added. All SQL and code below are drafts that have never run.

TMDB behaviour comes from the [pages listed at the end](#sources), as read on this date.

## Summary

- **The catalogue lists only VeloraUG's own movies.** The owner adds each one, by its TMDB ID. The app never shows a movie VeloraUG can't play. Upload and playback come in Milestones 7 and 8.
- **TMDB supplies the details:** title, description, year, runtime, genres, poster and backdrop. The API fetches them with a key the app never sees, and keeps a copy in Neon.
- **TMDB's free licence doesn't cover a paid app.** Its terms say the licence "does not permit any commercial use", and give "charging users a fee for Your Application" as an example. The owner chose to build on TMDB now and get a commercial agreement before launch. See [the licence risk](#the-licence-risk).
- **The app's movie shape doesn't depend on TMDB.** If no agreement is reached, the copy from TMDB can be replaced by details the owner types in, without changing the API's responses or the app.
- **Browsing doesn't need sign-in.** The list, search and detail routes answer without a token. Watching will need one, from Milestone 8.

## Implementation sequence

| Step | Scope | Finished when |
| --- | --- | --- |
| **6A**, this step | This plan | Committed locally |
| **6B** | The owner's TMDB key, migration `0002`, and the owner's catalogue script | [6B criteria](#6b-key-database-and-script) pass, including [gate T1](#gate-t1-the-key) |
| **6C** | The API's catalogue routes, with the TMDB client and copy refresh | [6C criteria](#6c-api) pass |
| **6D** | Home, search and detail screens in the app, and TMDB's credit | [6D criteria](#6d-app) pass |
| **6E** | End-to-end checks on web and Android, the report, and closing the milestone | [6E criteria](#6e-end-to-end) pass |

Not in Milestone 6: uploads, playback, prices, watch history, favourites, ratings, an admin website, TV series, languages other than English, TMDB search inside the app.

## Decisions

| # | Decision | Why |
| --- | --- | --- |
| 1 | A movie is in the catalogue only if the owner added it and published it | The owner's choice, 10 November 2026. It matches what VeloraUG has rights to |
| 2 | The owner adds movies with a script, `scripts/catalogue.py`, as the database owner | There are no admin roles yet. The upload design in Milestone 7 decides who may manage movies, and may replace the script with admin routes |
| 3 | The API's role, `veloraug_app`, can read movies but can't add, publish or remove them | A fault in the API can't change the catalogue |
| 4 | The API keeps a copy of each movie's TMDB details in `tmdb_movie_details`, and refreshes it | Browsing works when TMDB is slow or down, and TMDB gets a few requests a day, not one per visitor |
| 5 | No copy is served once it is **150 days** old. A copy older than **7 days** is refreshed after the response is sent | TMDB's terms forbid keeping its data "for longer than 6 months". 150 days leaves a margin |
| 6 | Images load straight from `image.tmdb.org` | TMDB's documented way to show images. VeloraUG doesn't store or serve TMDB's images. Web loading is [gate T2](#gate-t2-images-in-flutter-web) |
| 7 | Responses use VeloraUG's movie ID, a UUID, never the TMDB ID | The app stays the same if details later come from elsewhere |
| 8 | Search looks only in VeloraUG's catalogue, by title, in Postgres | The catalogue is small. Searching TMDB would show movies nobody can watch |
| 9 | The API calls TMDB with `httpx`, using the v4 **read access token** as a bearer token | Header, not URL, so the token stays out of logs. `httpx` has a built-in mock transport for tests |
| 10 | Details are fetched in English, `en-US` | The audience reads English, and TMDB's English details are the most complete |
| 11 | TMDB's notice and logo appear on the Account screen, under **About** | TMDB's terms require them, in an "About" or "Credits" section, less prominent than VeloraUG's own brand |

### Routes ruled out

| Route | Why not |
| --- | --- |
| The app calling TMDB itself | Ships the key in the app, where anyone can read it |
| Browsing all of TMDB | The owner's choice. Shows movies nobody can watch |
| Fetching from TMDB on every request | Slow, fails when TMDB does, and uses TMDB's bandwidth, which its terms let it restrict |
| Copying TMDB's images into R2 | Its terms say TMDB is not an image host, and the 6-month limit would apply to every copy |
| Keeping copies without an age limit | Breaks the 6-month rule |

## The licence risk

From TMDB's [API terms](https://www.themoviedb.org/api-terms-of-use), as read on 10 November 2026:

- The free licence "does not permit any commercial use of TMDB, the TMDB APIs, or TMDB Content". Examples include "charging users a fee for Your Application" and "operating a website that generates revenue through charging users for access to content".
- Commercial use without a written agreement "constitutes a material breach". TMDB decides what counts as commercial, "in its sole discretion".
- Its [FAQ](https://developer.themoviedb.org/docs/faq) says a project is commercial "if the primary purpose is to create revenue for the benefit of the owner", and sends commercial requests to sales@themoviedb.org.
- **No price is published.** Third-party blogs mention about $149 a month for small companies. That's unconfirmed, and it is over seven times the $20 a month pilot target.

**What this means now.** VeloraUG is built to earn money, so TMDB may count it as commercial before it charges anyone. When the owner applies for a key, they must describe the project truthfully, as a paid streaming app in development. If TMDB answers that a commercial agreement is needed before any use, [gate T1](#gate-t1-the-key) fails and Milestone 6 stops until the owner decides.

**The fallback.** Decision 7 keeps this cheap to change. Without TMDB, `movies` would gain columns for the details, filled in by the owner's script, posters would be uploaded to R2, and `tmdb_movie_details` would be dropped. The API's responses and the app wouldn't change.

**Before charging anyone,** the owner must have a signed TMDB agreement, or have switched to the fallback. This is added to the roadmap's [check before launch](roadmap.md#check-before-launch).

## 1. Database

Migration `0002`, hand-written like `0001`.

```sql
create table public.movies (
  id uuid primary key default gen_random_uuid(),
  tmdb_id integer not null unique check (tmdb_id > 0),
  published boolean not null default false,
  added_at timestamptz not null default now(),
  published_at timestamptz
);

-- TMDB's details, as fetched. Only the fields the app shows.
create table public.tmdb_movie_details (
  tmdb_id integer primary key references public.movies (tmdb_id) on delete cascade,
  title text not null,
  original_title text,
  overview text,
  release_date date,
  runtime_minutes integer check (runtime_minutes is null or runtime_minutes >= 0),
  genres text[] not null default '{}',
  poster_path text,
  backdrop_path text,
  fetched_at timestamptz not null default now()
);

create index tmdb_movie_details_title_idx
  on public.tmdb_movie_details (lower(title) text_pattern_ops);

alter table public.movies enable row level security;
alter table public.movies force row level security;
alter table public.tmdb_movie_details enable row level security;
alter table public.tmdb_movie_details force row level security;

revoke all on table public.movies, public.tmdb_movie_details from public;

-- The API sees published movies only, signed in or not.
grant select on table public.movies to veloraug_app;
create policy movies_select_published on public.movies
  for select to veloraug_app using (published);

-- The API reads and refreshes copies, for published movies only. It can't
-- delete them: the owner's script does.
grant select, insert, update on table public.tmdb_movie_details to veloraug_app;
create policy details_published on public.tmdb_movie_details
  for all to veloraug_app
  using (exists (select from public.movies m
                 where m.tmdb_id = tmdb_movie_details.tmdb_id and m.published))
  with check (exists (select from public.movies m
                      where m.tmdb_id = tmdb_movie_details.tmdb_id and m.published));
```

- **Search** uses `lower(title) like lower($1) || '%'` for title starts, and `%…%` for anything else. With a few hundred movies, a full scan is fine. `pg_trgm` can come later if needed.
- **No user rows.** Unlike `profiles`, these tables are the same for everyone, so the API reads them in a transaction with no `app.user_id`. 6C adds `Database.anonymous()` beside `as_user()`.
- **Ages:** the API ignores a copy older than 150 days, so even if refreshing stops, old data isn't shown. The owner's script deletes copies older than 180 days, as the last safeguard. See [the script](#2-the-owners-catalogue-script).

## 2. The owner's catalogue script

`services/api/scripts/catalogue.py`, run from the owner's terminal. It asks for the owner connection, hidden, like the migration, and reads the TMDB token from `services/api/.env`. It never prints either.

| Command | What it does |
| --- | --- |
| `add <tmdb_id>` | Fetches the movie from TMDB, shows its title and year, asks to confirm, then adds it **unpublished** with its copy |
| `publish <id or tmdb_id>` / `unpublish …` | Shows or hides it in the app |
| `list` | Every movie, published or not, with the copy's age |
| `refresh` | Refetches every copy older than 7 days, and deletes any copy older than 180 days that failed to refresh |
| `purge-tmdb` | Deletes every TMDB copy, after typing `purge` to confirm. For when the licence ends: TMDB's terms require prompt deletion |

The owner finds a movie's TMDB ID in its address on themoviedb.org, such as `550` in `themoviedb.org/movie/550-fight-club`.

## 3. API

### Routes

All three answer without a token. A token, if sent, is ignored here.

| Route | Answers |
| --- | --- |
| `GET /api/v1/movies?limit=&offset=` | Published movies, newest published first. `limit` 1 to 50, default 24 |
| `GET /api/v1/movies?q=…` | The same, filtered by title. `q` is 2 to 80 characters after trimming. Title starts sort first |
| `GET /api/v1/movies/{id}` | One published movie. `404` if it doesn't exist or isn't published, with the same message for both |

```json
{
  "id": "6f1c…",
  "title": "…",
  "year": 2024,
  "overview": "…",
  "runtime_minutes": 112,
  "genres": ["Drama"],
  "poster_url": "https://image.tmdb.org/t/p/w342/….jpg",
  "backdrop_url": "https://image.tmdb.org/t/p/w780/….jpg"
}
```

The list gives `id`, `title`, `year` and `poster_url` only. Image addresses are built by the API, so the app needs no TMDB knowledge. The base and sizes come from TMDB's `/configuration` once a day, falling back to `https://image.tmdb.org/t/p/` and `w342` or `w780`.

### Copies and refresh

- A movie with no copy, or only one older than 150 days, is **left out** of lists, and its detail answers `503` with "This movie's details aren't available right now". The API then fetches it in the background.
- A copy 7 to 150 days old is served, and refreshed in the background.
- At most one refresh per movie at a time, with a 10-second timeout. TMDB's `429` is respected using `Retry-After`. Its limit is "somewhere in the 40 requests per second range".
- TMDB failures are logged by status code and TMDB ID only. The token is never logged.
- A TMDB `404`, such as a deleted movie, keeps the old copy until it ages out, and is logged for the owner.

### Settings

| Variable | Secret | Purpose |
| --- | --- | --- |
| `VELORAUG_TMDB_READ_ACCESS_TOKEN` | **Yes** | The v4 read access token. `SecretStr`, like the database URL |

Without it, the catalogue routes still serve existing copies, and nothing is refreshed. The API's start-up log says so once.

New dependency: `httpx`, pinned with what it needs, following [change a dependency](../services/api/README.md).

## 4. App

| Screen | Change |
| --- | --- |
| **Home** | Replaces the empty state with a grid of published movies, using the existing `MovieCardGrid` and `MovieCard`, with skeletons while loading. Loads more on scroll. "No movies yet" when empty |
| **Search** | Searches as the user types, after 2 characters and a 300 ms pause. "No movies match" when empty |
| **Detail**, new | Backdrop, poster, title, year, runtime, genres and description. The watch button is shown disabled with "Coming soon" until Milestone 8 |
| **Account** | Adds **About**, with TMDB's logo and: "This product uses the TMDB API but is not endorsed or certified by TMDB." Shown signed in or not, and in release builds |

- **Images** use the poster placeholder while loading and when an image fails, never a broken image.
- **Errors** follow the profile section: "Couldn't reach VeloraUG", with a retry, never a server message.
- **No token is sent** on catalogue calls, so signed-out browsing works the same way.
- **The TMDB logo** is one of the approved logos from TMDB's branding page, added as an asset in 6D. It is smaller than VeloraUG's own brand, as TMDB's terms require.

## Owner setup

### At 6B: the TMDB key

1. Create an account at themoviedb.org, with the owner's address.
2. In account settings, open **API** and apply for a key. Describe VeloraUG truthfully: a paid movie streaming app for Uganda, in development, not yet charging anyone, planning to sign a commercial agreement before launch. **Note what TMDB answers.**
3. Copy the **API Read Access Token**, the long one, not the short API key. Add it to `services/api/.env`:

   ```text
   VELORAUG_TMDB_READ_ACCESS_TOKEN=<the token>
   ```

   Never put it in the app, `dart_defines.local.json`, a commit or a message.
4. Pick 3 to 5 movies to test with, ideally ones VeloraUG means to show, and note their TMDB IDs.

### Before launch

Email sales@themoviedb.org with the country, Uganda, for a quote. Sign an agreement, or switch to [the fallback](#the-licence-risk), before anyone is charged.

## Gates

### Gate T1: the key

TMDB issues a key for the project as described. **If TMDB says a commercial agreement is needed before any use,** Milestone 6 stops, and the owner chooses between paying and [the fallback](#the-licence-risk).

### Gate T2: images in Flutter web

At 6D, a poster from `image.tmdb.org` shows in the web build, in Chrome. Flutter web's renderer needs the image server to allow cross-origin reads. **Unconfirmed.** If it fails, the API serves images through itself, with a short browser cache and no storage, and that design is checked against TMDB's terms first.

## Acceptance criteria

### 6B key, database and script

- Gate T1 passes, with TMDB's answer recorded.
- Migration `0002` runs on a local Postgres set up as Neon is, and then on the Neon development branch.
- Database checks, added to `check_database.py`: as `veloraug_app`, unpublished movies are invisible, and adding, publishing, deleting movies or deleting copies is refused. A copy of an unpublished movie can't be read or written.
- `catalogue.py add`, `publish`, `unpublish`, `list`, `refresh` and `purge-tmdb` work against a local database, with TMDB mocked, and the owner adds and publishes the test movies on the development branch.
- No token or password is printed, logged or tracked.

### 6C API

- The three routes answer as described, with and without a token, and through real CORS from `http://localhost:8765`.
- Tests with TMDB mocked: a fresh copy is served without calling TMDB, a 7-day-old copy is served and refreshed once, a 150-day-old copy is not served, TMDB's `429`, `404`, timeouts and errors, a missing token, and that no response or log contains the token.
- An unpublished movie answers `404`, the same as a missing one.
- A container run with the real settings serves the test movies.

### 6D app

- Home, search, detail and About work, with tests for loading, empty, error and retry states.
- Gate T2 passes.
- The TMDB notice and logo show in a release build.
- `flutter analyze` and `flutter test` are clean. The web and release builds contain no TMDB token.

### 6E end to end

- On web and on one Android phone: browse, search and open each test movie, signed in and signed out.
- An unpublished movie disappears from both after `unpublish` and a refresh.
- With the token removed from `.env` and the API restarted, existing movies still show.
- The report records TMDB's answer from gate T1 and the licence state.

## Cost

Nothing during development: TMDB's key is free for the project as accepted, and the tables are a few kilobytes in Neon's free allowance. **The commercial agreement is the open cost,** and is not known yet.

## Still unconfirmed

- Whether TMDB treats VeloraUG as commercial during development. [Gate T1](#gate-t1-the-key).
- The commercial price. Only third-party figures were found.
- Whether `image.tmdb.org` allows cross-origin image reads for Flutter web. [Gate T2](#gate-t2-images-in-flutter-web).
- TMDB's rate limit is approximate and "subject to change without notice".

## Sources

Read on 10 November 2026:

- [TMDB API terms of use](https://www.themoviedb.org/api-terms-of-use): commercial use, attribution, the 6-month cache limit, image hosting, deletion when the licence ends
- [TMDB developer FAQ](https://developer.themoviedb.org/docs/faq): commercial definition, attribution wording and placement, sales contact
- [TMDB API for business](https://www.themoviedb.org/api-for-business): a contact form, no prices
- [TMDB rate limiting](https://developer.themoviedb.org/docs/rate-limiting)
- [TMDB image basics](https://developer.themoviedb.org/docs/image-basics)
