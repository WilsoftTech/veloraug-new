# Step 6E report: end to end

Date: 12 November 2026. Branch: `feature/step-06a-catalogue-plan`. This follows the [catalogue plan](step-06a-catalogue-plan.md#6e-end-to-end), and closes Milestone 6.

**Step 6E is complete, and so is Milestone 6.** On 12 November 2026 the owner browsed, searched and opened every published movie on the web and on one Android phone, signed in and signed out, and reported that every check passed. Unpublishing a movie removed it from both, and publishing it again brought it back. With no TMDB token, the API still served every movie. Nothing was deployed. **TMDB's licence is still open:** VeloraUG uses the free plan, and needs a commercial agreement, or the fallback, before anyone is charged.

## Checks

| Check | How | Result |
| --- | --- | --- |
| Every movie opens with its details | Each published movie through `GET /api/v1/movies/{id}` on the owner's API | *Inception*, 2010, 148 min; *Interstellar*, 2014, 169 min; *Fight Club*, 1999, 139 min. Each with genres and a description |
| Search | `?q=inter` | *Interstellar* only |
| Existing movies show without the TMDB token | A second API on port 8001, started from a temporary copy of `.env` with the token line removed. The copy was deleted afterwards | The API logged that the token wasn't set, then served all three movies with posters and details |
| Browse, search and open each movie, **signed out**, on the web and on the phone | The owner | **Passed** |
| The same, **signed in** | The owner | **Passed** |
| TMDB's logo and notice under **About** | The owner | **Passed** |
| An unpublished movie disappears from both | The owner ran `unpublish 550`, then refreshed the web app and the phone app | **Passed**: *Fight Club* was gone, and searching for it found nothing |
| Publishing it again brings it back | `publish 550` | **Passed**. The database shows *Fight Club* published again at 11:28 UTC, with *The Matrix* still hidden |

The token check didn't change the owner's `.env`. The first try at it didn't count: in PowerShell, setting a variable to an empty string deletes it, so that server still read the token from `.env`. Using the copy without the token line fixed that.

## Problems found and fixed

| Problem | Fix |
| --- | --- |
| The API README's start command didn't pass `.env`, so the API started without a database, and the app said "VeloraUG is busy right now" | Added `--env-file .env` to the command, with a line on why. Commit `b9bc999` |
| The phone couldn't reach the API | It hadn't yet allowed USB debugging, so `adb reverse` failed. After the owner allowed it, the reverse was set again, and the phone got `200` from the API |
| The owner's first `unpublish 550` failed with only "OperationalError", and changed nothing | No trigger, open transaction, waiting lock or timeout was found on the branch. A failure now prints Postgres's code and full message, with the password masked, and a test covers it. Commit `756f1a2`. The retry worked, so the cause wasn't seen. It was most likely a dropped connection |

## TMDB's licence

- **Gate T1:** passed on the owner's decision on 10 November 2026: use TMDB's free plan now, and a paid plan later. TMDB's answer to the key application wasn't reported. See the [Step 6B report](step-06b-report.md#gate-t1-the-key).
- **The state now:** no commercial agreement, and no published price. TMDB counts an app built to earn money as commercial.
- **Before anyone is charged:** get a quote from `sales@themoviedb.org` and sign, or switch to [the fallback](step-06a-catalogue-plan.md#the-licence-risk). This stays on the [roadmap's open issues](roadmap.md#open-issues) and in [check before launch](roadmap.md#check-before-launch).

## Acceptance criteria

| Criterion | State |
| --- | --- |
| On web and one Android phone: browse, search and open each test movie, signed in and signed out | **Met**, owner-reported |
| An unpublished movie disappears from both after `unpublish` and a refresh | **Met**, owner-reported, and the database agrees |
| With the token removed and the API restarted, existing movies still show | **Met**, on a second API without the token |
| The report records TMDB's answer from gate T1 and the licence state | **Met**: TMDB's answer wasn't reported, and the licence is open. See above |

## Not checked

- **Details older than 150 days** aren't served. The automated tests in Step 6C cover this. It wasn't run against Neon, because the copies are a day old.
- **One phone only**, a Samsung Galaxy S20 (SM-G981U1). See [still unverified](roadmap.md#still-unverified).
