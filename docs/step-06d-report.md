# Step 6D report: home, search and detail screens

Date: 11 November 2026. Branch: `feature/step-06a-catalogue-plan`. This follows the [catalogue plan](step-06a-catalogue-plan.md#4-app).

**Step 6D is complete except for TMDB's logo.** Home, Search and the new detail screen show the real catalogue, and **About** on Account carries TMDB's notice. Every check passed, and real posters loaded in the web build from the Neon development branch, which is gate T2. TMDB's terms also require its logo. Adding it means downloading the logo file from TMDB, which needs the owner's permission first. See [still to do](#still-to-do).

## What changed

| Item | Where |
| --- | --- |
| The catalogue client: lists, search, pages and details. It sends no token, and accepts images only from `https://image.tmdb.org` | [`lib/api/catalogue_api.dart`](../apps/client/lib/api/catalogue_api.dart) |
| `CatalogueScope`, which gives every screen, including pushed ones, the catalogue built from `API_BASE_URL` | [`lib/app.dart`](../apps/client/lib/app.dart) |
| **Home:** a poster grid, newest first, with **Show more**. Skeletons while loading. Empty, error and **Try again** states | [`home_screen.dart`](../apps/client/lib/screens/home_screen.dart) |
| **Search:** after 2 letters and a 300 ms pause, or at once on the search key. Out-of-date answers are ignored | [`search_screen.dart`](../apps/client/lib/screens/search_screen.dart) |
| **Detail**, new: backdrop, poster, title, year, running time, genres and description. **Watch** is disabled, marked **Coming soon**. A hidden movie says "This movie isn't available", with **Back** | [`movie_detail_screen.dart`](../apps/client/lib/screens/movie_detail_screen.dart) |
| Posters with the placeholder while loading, on failure and when missing, and the shared grid | [`movie_poster.dart`](../apps/client/lib/widgets/movie_poster.dart) |
| **About** on Account: TMDB's notice, word for word, in every build | [`account_screen.dart`](../apps/client/lib/screens/account_screen.dart) |
| Docs | [Client README, Catalogue](../apps/client/README.md#catalogue) |

**One change from the plan:** Home loads more with a **Show more** button, not on scroll. A button works the same with a keyboard, a screen reader and a mouse, and the catalogue is small.

## Tested

| Check | Result |
| --- | --- |
| `dart format`, `flutter analyze` | Clean |
| `flutter test` | **309 passed**, including 37 new: 22 for the catalogue client, and 15 for the screens, covering loading, empty, error, retry, pages, out-of-date search answers, the disabled **Watch**, the 404 screen, About, and a 320-pixel phone at text sizes 1 and 2 with no overflow |
| The shell's existing tests | Updated for the real Home and Search, all passing |
| **Gate T2:** the web build in headless Chrome, against the API with the real settings | *Inception*, *Interstellar* and *Fight Club* showed with their real posters from `image.tmdb.org`. *The Matrix*, hidden, didn't |
| `flutter build web` | No TMDB token, and no call to TMDB's API |
| `flutter build apk --release` with the real settings | Built, 48.4 MB. No TMDB token. The TMDB notice is in it |

**How the web check ran:**
- The owner's own `flutter run` server held `localhost:8765`, still serving the old app, so the check used port 8766.
- A separate API container allowed only that origin, and was removed afterwards.
- The owner's servers on 8000 and 8765 were left running.
- A phone-width screenshot looked clipped. That was headless Chrome's minimum window width, about 500 pixels, not the app: the 320-pixel widget test passes.

## Acceptance criteria

| Criterion | State |
| --- | --- |
| Home, search, detail and About work, with tests for loading, empty, error and retry | **Met** |
| Gate T2 passes | **Met**: real posters in the web build |
| The TMDB notice and logo show in a release build | Notice: **met**. Logo: **not yet**. See below |
| `flutter analyze` and `flutter test` are clean, and the web and release builds contain no TMDB token | **Met** |

## Still to do

- **TMDB's logo.** TMDB's terms say "You must use the TMDB logo", less prominent than VeloraUG's own brand. It comes from TMDB's logos and attribution page, `https://www.themoviedb.org/about/logos-attribution`. Downloading it needs the owner's permission. It would then be added as an asset under **About**, small, beside the notice.
- **Restart the owner's local API** before trying the app. The server running on port 8000 predates Step 6C, so it has no catalogue routes.
