# Step 6D report: home, search and detail screens

Date: 11 November 2026. Branch: `feature/step-06a-catalogue-plan`. This follows the [catalogue plan](step-06a-catalogue-plan.md#4-app).

**Step 6D is complete.** Home, Search and the new detail screen show the real catalogue, and **About** on Account carries TMDB's logo and notice. Every check passed, and real posters loaded in the web build from the Neon development branch, which is gate T2. The logo was added on 12 November, once the owner allowed the download. See [TMDB's logo](#tmdbs-logo).

## What changed

| Item | Where |
| --- | --- |
| The catalogue client: lists, search, pages and details. It sends no token, and accepts images only from `https://image.tmdb.org` | [`lib/api/catalogue_api.dart`](../apps/client/lib/api/catalogue_api.dart) |
| `CatalogueScope`, which gives every screen, including pushed ones, the catalogue built from `API_BASE_URL` | [`lib/app.dart`](../apps/client/lib/app.dart) |
| **Home:** a poster grid, newest first, with **Show more**. Skeletons while loading. Empty, error and **Try again** states | [`home_screen.dart`](../apps/client/lib/screens/home_screen.dart) |
| **Search:** after 2 letters and a 300 ms pause, or at once on the search key. Out-of-date answers are ignored | [`search_screen.dart`](../apps/client/lib/screens/search_screen.dart) |
| **Detail**, new: backdrop, poster, title, year, running time, genres and description. **Watch** is disabled, marked **Coming soon**. A hidden movie says "This movie isn't available", with **Back** | [`movie_detail_screen.dart`](../apps/client/lib/screens/movie_detail_screen.dart) |
| Posters with the placeholder while loading, on failure and when missing, and the shared grid | [`movie_poster.dart`](../apps/client/lib/widgets/movie_poster.dart) |
| **About** on Account: TMDB's logo, small, and its notice, word for word, in every build | [`account_screen.dart`](../apps/client/lib/screens/account_screen.dart) |
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
| The TMDB notice and logo show in a release build | **Met**: both are in the web build and the release APK |
| `flutter analyze` and `flutter test` are clean, and the web and release builds contain no TMDB token | **Met** |

## TMDB's logo

Added on 12 November 2026, with the owner's permission to download it.

- **Source:** TMDB's [logos and attribution page](https://www.themoviedb.org/about/logos-attribution). TMDB offers its logos only as SVG. This is the "Alt short" logo, a 2,065-byte SVG. It was checked before use: no scripts and no links.
- **Format:** Flutter can't draw SVG without an extra package, so headless Chrome drew it to a PNG, 820 × 107 pixels with a transparent background: [`assets/brand/tmdb_logo.png`](../apps/client/assets/brand/tmdb_logo.png), 44,724 bytes. Its colours and shape are unchanged.
- **Placement:** under **About**, between the description and the notice, 16 pixels tall, so it's less prominent than VeloraUG's own brand. Screen readers read it as "TMDB logo".
- **Checks:** `flutter analyze` clean; `flutter test`, 309 passed, with the About test now also checking the logo; the logo is in `flutter build web` and in the release APK, 48.5 MB.

## Still to do

- **Restart the owner's local API** before trying the app. The server running on port 8000 predates Step 6C, so it has no catalogue routes.
