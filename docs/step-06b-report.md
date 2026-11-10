# Step 6B report: TMDB key, catalogue tables and the owner's script

Date: 10 November 2026. Branch: `feature/step-06a-catalogue-plan`, from the Step 5G branch. This follows the [catalogue plan](step-06a-catalogue-plan.md#implementation-sequence).

**Step 6B is not complete.** The migration, the TMDB client, the owner's catalogue script and the new database checks pass every local check, including a run of each command against real TMDB and a local Postgres. The remaining work needs the owner's database password: running migration `0002` on the Neon development branch, the database checks there, and adding the test movies. See [test it](#test-it). Nothing was deployed, and no Neon setting changed.

## What changed

| Item | Where |
| --- | --- |
| TMDB client: a movie's details, with the read access token in the header only. Typed failures that never quote the token or TMDB's reply | [`app/tmdb.py`](../services/api/app/tmdb.py) |
| Migration `0002`: `movies` and `tmdb_movie_details`, with row-level security. The API's role sees published movies only, can refresh their details, and can't add, publish, hide or remove movies, or delete details | [`0002_catalogue.py`](../services/api/migrations/versions/0002_catalogue.py) |
| The owner's script: `add`, `publish`, `unpublish`, `list`, `refresh` and `purge-tmdb`. It asks for the owner string, hidden, and checks the branch first, like the migration | [`scripts/catalogue.py`](../services/api/scripts/catalogue.py) |
| Five catalogue checks in the database checker | [`scripts/check_database.py`](../services/api/scripts/check_database.py) |
| `httpx2` moved from the test tools into `requirements.txt`, with `httpcore2` and `truststore`. Same versions | [`requirements.txt`](../services/api/requirements.txt) |
| The local test database setup moved into a shared module, so the catalogue tests use the same database | [`tests/db_support.py`](../services/api/tests/db_support.py), [`conftest.py`](../services/api/tests/conftest.py) |
| Docs: the token in `.env.example`, the API README's [catalogue](../services/api/README.md#catalogue) section, and `httpx2` in the plan | |

The app, the sign-in pages and the API's routes are unchanged. The API itself doesn't use TMDB until 6C.

## Gates

### Gate T1: the key

**Passed on the owner's decision.** The owner created a TMDB account and an API key, and on 10 November 2026 chose to **use TMDB's free plan now and get a paid plan later**. The read access token works: TMDB answered `200` for a movie, `/configuration` and `/authentication`. Neither the token nor the key was shown or sent.

What TMDB said about the application wasn't reported. **The licence risk stays open:** TMDB's terms count an app built to earn money as commercial, and TMDB decides that "in its sole discretion". A signed agreement, or [the fallback](step-06a-catalogue-plan.md#the-licence-risk), is needed before anyone is charged. That is on the roadmap under [check before launch](roadmap.md#check-before-launch).

The first token in `.env` was refused with `401`. One character in its scope read `apl_read` rather than `api_read`, so it had been changed when it was copied. The owner rotated it, and the new one works.

### Gate T2: images in Flutter web

**Headers checked, app check at 6D.** A real poster from `image.tmdb.org`, asked for with `Origin: http://localhost:8765`, came back with `Access-Control-Allow-Origin: *` and a one-year cache. That is what Flutter web needs. Loading a poster in the real web app is still a [6D criterion](step-06a-catalogue-plan.md#6d-app).

## Tested

| Check | Result |
| --- | --- |
| `ruff format --check`, `ruff check` | Clean |
| `pytest` with a local Postgres 17 set up as Neon is | **200 passed**, including 36 new: 12 for the TMDB client with TMDB mocked, and 24 for the catalogue |
| `alembic heads`, and `upgrade head --sql` without a database | `0002 (head)`. The SQL reads as planned |
| Every script command against real TMDB and the local database | `add 550` showed *Fight Club (1999)*, *Drama, Thriller*, and added it hidden. `publish`, `list`, `refresh` and both answers to `purge-tmdb` worked. An unknown ID said "TMDB has no movie 999999999" |
| `docker compose build`, then the API with the real settings | Built and healthy. `/health` answered `200`, and `/api/v1/me` without a token `401` |
| Tracked files | No `.env`. No token, key or password in the changes |

**Fixed during the run:**
- `add` for a movie already in the catalogue asked for `yes` before saying so. It now says so first.
- A prompt with no input crashed with `EOFError`. It now counts as no.
- Counts now say "1 movie", not "1 movies".

**Found in the owner's `.env`, and fixed:** `VELORAUG_NEON_AUTH_CLIENT_IDS` had lost its square brackets, probably when the file was edited to add the token. Docker Compose refused the whole file, so the API wouldn't have started. The brackets were put back and nothing else changed. Compose's error message quoted part of one client ID, which is public, not secret. The copy of `.env` made before the fix was deleted.

## Acceptance criteria

| Criterion | State |
| --- | --- |
| Gate T1 passes, with TMDB's answer recorded | **Met on the owner's decision.** The token works. TMDB's answer to the application wasn't reported |
| Migration `0002` runs locally, then on the Neon development branch | **Met**: locally, and on Neon, user-reported. See [the Neon run](#the-neon-run) |
| Database checks for the catalogue | **Met**: locally, and 25 of 25 on Neon through the pooler, user-reported. **Needs the owner**: Neon step 5, with a hidden movie in the table |
| Every script command works locally with TMDB mocked, and the owner adds and publishes the test movies on the development branch | Local: **met**, with real TMDB too. **Needs the owner**: Neon step 4 |
| No token or password printed, logged or tracked | **Met** |

## The Neon run

User-reported on 10 November 2026, with secret values excluded. Branch: `development` in the Frankfurt project, database host `ep-floral-salad-b98b3l94.c-7.eu-central-1.aws.neon.tech`, with 16 `neon_auth` tables.

- **Before the migration,** `alembic current` showed `0001`, and the checker refused `.env`. `VELORAUG_DATABASE_URL` held the **old us-east-2 project's owner string** (`neondb_owner` at `ep-twilight-breeze-be9id8hj`), probably pasted there by mistake while copying connection strings. The API and the checker both refuse an owner connection, so nothing ran with it.
- **The owner ran `create_app_role.py`,** which gave `veloraug_app` a new password and wrote its pooled Frankfurt connection back to `.env`, then **ran migration `0002`**.
- **`check_database.py` passed 25 of 25** through the pooler, as `veloraug_app`: the 20 from Step 5F and the 5 catalogue checks. The catalogue had no movies yet, so "hidden movies can't be seen" passed with 0 hidden movies. Step 5 below repeats it with one.
- **The old project's owner password** has now been saved in `.env` twice. The owner should reset it in the old project's Console, or delete that project, as the [Step 5F report](step-05f-report.md) says.

## Test it

You need the owner connection string for the **`development`** branch of the Frankfurt project, as in [Step 5F](../services/api/README.md#1-copy-the-owner-connection-string): `neondb_owner`, connection pooling **off**. Each command asks for it, hidden. Don't send it, the token or any password.

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
```

That installs nothing new, but checks the virtual environment matches the pinned files.

1. **Read the SQL first.** This needs no connection:

   ```powershell
   .\.venv\Scripts\python.exe -m alembic upgrade head --sql
   ```

2. **Run the migration**, then check where it is:

   ```powershell
   .\.venv\Scripts\python.exe -m alembic upgrade head
   .\.venv\Scripts\python.exe -m alembic current
   ```

   Both print `Branch: matches sign-in` before doing anything. `current` should show `0002 (head)`.

3. **Check the database** as the API's role. This asks for nothing:

   ```powershell
   .\.venv\Scripts\python.exe scripts\check_database.py
   ```

   Every line should say `PASS`: 25 checks, the 20 from Step 5F and 5 new ones for the catalogue.

4. **Add four test movies,** *Fight Club*, *Inception*, *Interstellar* and *The Matrix*, then publish all but *The Matrix*, so a hidden movie can be tested later. Type one command at a time:

   ```powershell
   .\.venv\Scripts\python.exe scripts\catalogue.py add 550 27205 157336 603
   .\.venv\Scripts\python.exe scripts\catalogue.py publish 550 27205 157336
   .\.venv\Scripts\python.exe scripts\catalogue.py list
   ```

   `add` shows the four titles and years, then asks for the owner string and `yes`. `list` should end with `4 movies, 3 published`.

   The first try failed with "Refused: The connection string must start with postgresql://" and changed nothing. Several commands were pasted together, so each hidden prompt read the wrong input. A shortcut that set the string with `Read-Host -AsSecureString` kept only one character, because Windows PowerShell 5.1's hidden prompt didn't take the paste. `add`, `publish` and `unpublish` now take several movies at once, so the whole step needs three pastes.

5. **Run the checks again**, now that real movies exist:

   ```powershell
   .\.venv\Scripts\python.exe scripts\check_database.py
   ```

   Still 25 `PASS`. The check "hidden movies and their details can't be seen" now proves something, with your hidden movie in the table.

**To send me:** what `current` showed, the pass and fail counts from steps 3 and 5, and the output of `list`. Titles and IDs are fine to share. Nothing in that output is secret.
