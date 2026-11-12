# Steps 8B to 8D report: playback, built and checked on this PC

Date: 12 November 2026. From the [playback plan](step-08a-playback-plan.md). **Milestone 8 is not complete:** Step 8E needs the owner, on Neon and Cloudflare.

## What exists now

- **The API grants viewings.** `POST /api/v1/movies/{id}/playback` answers a signed-in viewer with a playback address on the media gateway, valid 6 hours. A film's details say whether it is `playable`. Migration `0004` lets the API see the ID, movie and state of ready originals of published films, and nothing else.
- **The media gateway**, a Cloudflare Worker in `services/media_gateway/`, checks the grant in each address's path and serves HLS from the R2 binding. It never touches a database or the API.
- **The app plays.** **Watch** on a film's details opens a player: hls.js 1.7.4 on the web, from `web/vendor/`, and ExoPlayer through `video_player` 2.14.1 on Android. Signed out, the button reads **Sign in to watch**. A grant that runs out mid-film is renewed by itself, from the same moment.

## The checks

| What | How | Result |
| --- | --- | --- |
| API tests | `pytest`, with a local Postgres set up as Neon is | **397 passed**, 28 of them new: signing, settings, the route's 200, 401, 404 and 409, `playable`, what the API's role can see, and `0004` down and up |
| Database checks | `scripts/check_database.py`'s upload checks, narrowed for `0004` | Pass locally. The API's role reads only `id`, `movie_id` and `state` of originals, ready ones of published films only, and changes none |
| Worker tests | `npm test`, Node's own runner | **21 passed**: each file served, ranges, `304`, `HEAD`, CORS, and refusals for every bad grant, other origins, other films' and originals' paths, `..` and unknown files |
| Shared test vector | One grant checked by both the API's and the Worker's tests | Pass in both: the Python signer and the Worker's Web Crypto agree byte for byte |
| Flutter tests | `flutter test` | **340 passed**, with new ones for the playback client, Watch signed in, signed out and not ready, the player's renewal, and each failure |
| Builds | `flutter analyze`, `flutter build web`, `flutter build apk --debug` | No issues; both build. `video_player` adds no Kotlin plugin warning |
| **A real film through the Worker** | The 30-second 720p test clip converted by the media worker's own image and command, put in Wrangler's local R2, served by `wrangler dev`, and followed from the master playlist as a player does | **22 of 22 files** reached, all byte-identical to the source. A range answered `206` |
| **Ways in that must fail** | `curl`-style requests to the local Worker | No grant, an expired grant, another key's grant, a changed signature and a path to the original: all refused. Another web origin: `403` |
| **Seeking in hls.js** | Chrome, headless, playing a grant from the local Worker with the vendored hls.js, on an allowed origin | Played, switched 360p → 720p, then seeked to 17.3 s (inside a chunk), 26 s and back to 4.5 s, landing exactly and playing on each time. No errors, no dropped frames |

## What 8E needs from the owner

1. **Run migration `0004`** on the Neon development branch, then `scripts\check_database.py`: every line `PASS`. See the [API README](../services/api/README.md#3-run-the-migration).
2. **Make a signing key** and put it in `services/api/.env` with `VELORAUG_MEDIA_GATEWAY_URL`. See [playback](../services/api/README.md#playback).
3. **Deploy the Worker:** `npx wrangler login`, `npx wrangler secret put PLAYBACK_SIGNING_KEY` and `npm run deploy`, in `services/media_gateway/`. See [deploy it](../services/media_gateway/README.md#deploy-it-step-8e).
4. **Watch *The Matrix*'s test clip** on the web and one Android phone, and seek to the middle and back on each. **ExoPlayer's seeking hasn't been tried yet.**
5. **Upload a real film** you have the right to use, and watch each quality to keep or change the bitrates.
6. **Try the ways in that must fail** against the deployed Worker: the bucket without credentials, no grant, a changed grant, an expired one.

## Things to know

- **A playback address works for anyone holding it** until it expires, up to 6 hours. Accepted for the pilot. See the plan's [risks](step-08a-playback-plan.md#risks).
- **`wrangler dev` prints every address, grant included,** to its terminal. The deployed Worker logs nothing of its own.
- **Stopping `wrangler dev` other than with `Ctrl+C`** can leave `workerd.exe` processes answering on port 8787 with old settings. This happened during these checks. Close them in Task Manager.
- **npm 11 skips `workerd`'s install script** unless approved. Wrangler runs without it.
- The Worker's tests use Node's own test runner and type stripping, so its only dependency is Wrangler.
