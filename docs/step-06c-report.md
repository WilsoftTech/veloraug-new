# Step 6C report: the API's catalogue routes

Date: 11 November 2026. Branch: `feature/step-06a-catalogue-plan`. This follows the [catalogue plan](step-06a-catalogue-plan.md#3-api).

**Step 6C is complete.** The API lists, searches and shows published movies without sign-in, and keeps its copies of TMDB's details fresh in the background. Every check passed locally, and a container run with the real settings served the three published movies from the Neon development branch. Nothing was deployed, and nothing changed in Neon.

## What changed

| Item | Where |
| --- | --- |
| `GET /api/v1/movies`, with `q`, `limit` and `offset`, and `GET /api/v1/movies/{id}` | [`app/routes.py`](../services/api/app/routes.py) |
| Catalogue reads, the age rules, and the `Refresher` that fetches old or missing copies after the response is sent | [`app/catalogue.py`](../services/api/app/catalogue.py) |
| `Database.anonymous()`: a transaction acting for no user, for data that's the same for everyone | [`app/db.py`](../services/api/app/db.py) |
| TMDB's image settings, from `/configuration`, with safe defaults | [`app/tmdb.py`](../services/api/app/tmdb.py) |
| `VELORAUG_TMDB_READ_ACCESS_TOKEN` read by the API, as a secret | [`app/config.py`](../services/api/app/config.py) |
| The owner's script now uses the API's `save_details` and `REFRESH_AFTER` | [`scripts/catalogue.py`](../services/api/scripts/catalogue.py) |
| Docs | [API README](../services/api/README.md) |

## How it behaves

- **Lists** show published movies with a copy no older than 150 days, newest published first. Search matches part of a title, ignoring case, with titles that start with it first. `%` and `_` are searched as plain text.
- **A copy 7 to 150 days old** is served, then refreshed after the response. **Older, or missing:** left out of lists, and the detail answers `503` with `Retry-After: 30` while it's fetched.
- **The refresher:**
  - fetches each movie once at a time,
  - waits 15 minutes before retrying a failure,
  - pauses everything when TMDB sends `429`,
  - stops for good on a refused token,
  - keeps a copy TMDB no longer has until it ages out,
  - does at most 10 fetches per run.

  A list request also looks for missing or old copies, at most every 5 minutes.
- **Without the token,** the API serves the copies it has and refreshes none, and says so once at start-up.
- **Responses** carry VeloraUG's IDs only. Image addresses are built by the API, from TMDB's image settings, read once a day.

**A bug found by the tests:** FastAPI runs background tasks only for a response the route returns, not for a raised error. The first version raised its `503`, so an expired copy would never have been fetched again. The route now returns the `503` with the fetch attached.

## Tested

| Check | Result |
| --- | --- |
| `ruff format --check`, `ruff check` | Clean |
| `pytest` with a local Postgres 17 set up as Neon is | **246 passed**, including 42 new: 31 for the routes and refresher, and 11 for image settings, the new setting and the routes without a database |
| The image, `docker compose build` | Built |
| The container with the real settings, on port 8001, against the Neon development branch | The list gave *Inception*, *Interstellar* and *Fight Club*, with poster addresses. `?q=inter` gave *Interstellar*. The detail gave every field. *The Matrix*, which is hidden, and an unknown ID both answered `404` with the same message. CORS allowed `http://localhost:8765`. A poster address answered `200 image/jpeg` |
| TMDB from inside the container | Reached over HTTPS: image settings and movie 603 |
| The token in the container's logs | Not found |

The container ran on port 8001 because the owner's own API server was using port 8000. That server was left running.

## Acceptance criteria

| Criterion | State |
| --- | --- |
| The routes answer as described, with and without a token, and through real CORS | **Met** |
| Tests with TMDB mocked: fresh, 7-day and 150-day copies, `429`, `404`, timeouts and errors, a missing token, and no token in any response or log | **Met** |
| An unpublished movie answers `404`, the same as a missing one | **Met** |
| A container run with the real settings serves the test movies | **Met** |
