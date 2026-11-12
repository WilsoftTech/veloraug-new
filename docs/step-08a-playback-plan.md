# Step 8A plan: protected playback

Date: 12 November 2026. This plans Milestone 8 in the [roadmap](roadmap.md). It settles the last [open design task](architecture.md#open-design-tasks): what the API grants, how the Worker checks it on every chunk, and when it expires. **Steps 8B to 8D are built and checked on this PC;** see the [report](step-08-report.md). Step 8E needs the owner.

Facts about Workers, R2 and hls.js come from the [pages listed at the end](#sources), as read on this date.

## Summary

- **Any signed-in viewer may watch any published film that has a `ready` original.** Payments are Milestone 9, which adds one check to the same grant, so nothing here changes then. Signed-out viewers see **Sign in to watch**.
- **The API grants a viewing; the Worker checks it.** The app asks the API, with its access token, for a viewing of one film. The API checks the token, that the film is published, and that it is ready, then returns a **playback address** that works for **6 hours**.
- **The grant is in the address's path.** `https://<gateway>/v1/<grant>/master.m3u8`. HLS playlists name their files relative to themselves, so every playlist and chunk the player fetches carries the grant, in hls.js and ExoPlayer alike, without rewriting a playlist.
- **A grant is signed with a secret the API and the Worker share** (HMAC-SHA256). The Worker needs no database and makes no request to the API per chunk: it checks the signature and the time, and serves from private R2. It works out the R2 path from the grant, so a grant for one film can't fetch another.
- **The web app plays with hls.js, Android with ExoPlayer** (through Flutter's `video_player`). Both were named in the [Step 7F report](step-07f-report.md#what-milestone-7-leaves-for-later).
- **R2 stays private.** No public bucket, no `r2.dev` address, no presigned R2 links. Only the Worker reads it, through a binding.

## Implementation sequence

| Step | Scope | Finished when |
| --- | --- | --- |
| **8A**, this step | This plan | The owner approves it. **Not yet approved:** written and built on 12 November 2026 at the owner's request to implement Milestone 8 |
| **8B** | Migration `0004`, so the API can see which films are ready. The grant route `POST /api/v1/movies/{id}/playback`. `playable` on a film's details | [8B criteria](#8b-api) pass |
| **8C** | The Worker in `services/media_gateway/`: checks grants and serves HLS from R2, with tests and a local run | [8C criteria](#8c-worker) pass |
| **8D** | The player in the app: hls.js on the web, ExoPlayer on Android, and an expired grant renewed without losing the place | [8D criteria](#8d-player) pass |
| **8E** | On Neon and Cloudflare: the migration, the Worker deployed with the real bucket, playback on web and one phone, seeking, a real film's bitrates, and access without a grant refused | [8E criteria](#8e-end-to-end) pass |

Not in Milestone 8: payments (Milestone 9); offline downloads; DRM; limits on how many devices watch at once; resuming where a viewer left off in an earlier session; subtitles; Chromecast; a custom domain for the Worker (Milestone 10).

## Decisions

| # | Decision | Why |
| --- | --- | --- |
| 1 | Who may watch: **any signed-in viewer**, any published film with a `ready` original | Payments come in Milestone 9. Requiring sign-in now means Milestone 9 only adds a payment check to the grant |
| 2 | The grant is **`<payload>.<signature>`**, both base64url. The payload is JSON: the movie's ID, the original's ID and the expiry time. The signature is HMAC-SHA256, with a 32-byte secret, over `veloraug-playback-v1.` followed by the payload | Small, standard, checked with Web Crypto in the Worker in well under a millisecond. The prefix means a signature made for anything else can never pass |
| 3 | The grant is in the **path**, `/v1/<grant>/<file>`, never the query string | Relative playlist entries keep the path, and drop the query. No playlist needs rewriting, and every chunk is checked |
| 4 | A grant lasts **6 hours** | Longer than any film plus pauses. When one runs out mid-film, the player asks for a new one and carries on from the same moment |
| 5 | The Worker serves only `master.m3u8` and `<quality>/index.m3u8`, `init_<n>.mp4`, `seg_<n>.m4s`, with qualities `360p` to `1080p`. Anything else is 404 | The exact files the media worker publishes. No path from the address reaches R2 unchecked, and originals are never served |
| 6 | No user ID in the grant | The address appears in browser history and logs. The grant names only VeloraUG's film IDs |
| 7 | One secret, `PLAYBACK_SIGNING_KEY`, in the API's `.env` and as an encrypted Worker secret. Changing it ends every grant at once, which is how a leak is handled | Simple. At worst viewers mid-film ask for a new grant, which the app does by itself |
| 8 | The Worker answers browsers only from the allowed web origins (CORS). Requests with no `Origin`, as ExoPlayer sends, are checked by grant only | hls.js fetches chunks with JavaScript, which needs CORS. CORS isn't security for apps outside a browser: the grant is |
| 9 | Range requests are passed to R2 | Players may ask for part of a file. R2 answers them directly |
| 10 | The app accepts a playback address only on the media gateway it was built for, `MEDIA_BASE_URL` | As for posters: a bad answer can't make the app load video from elsewhere |
| 11 | Locally, the Worker runs with `wrangler dev`, against R2 in Wrangler's local store, filled from a converted test clip. The real bucket is used only at 8E | Tests and local runs need no Cloudflare login and touch no real data |
| 12 | The Worker is deployed at 8E on its `workers.dev` address, as `veloraug-media-dev`, bound to `veloraug-dev` | The owner's Cloudflare account. A custom domain waits for Milestone 10 |

### Routes ruled out

| Route | Why not |
| --- | --- |
| A public bucket, or a public `r2.dev` address | Anyone with an address could watch forever. The [architecture](architecture.md) requires R2 to stay private |
| Presigned R2 addresses from the API | One address per file. The API would have to rewrite every playlist, and sign about 1,200 addresses per film |
| The grant in a query string | Lost on every relative playlist entry, so playlists would have to be rewritten |
| Cookies | The web app and the Worker are on different sites, where browsers increasingly block cookies. ExoPlayer would need them set by hand |
| The Worker asking the API, or Neon, about every chunk | About 1,200 calls per film, and playback would stop whenever the API is slow |
| A short grant, renewed every few minutes | More moving parts in both players, for a little less exposure of a leaked address. Kept as an option if leaks are seen |
| DRM | Needs licences and a licence server, and is far beyond a pilot |

## 1. Database

Migration `0004_playback` gives the API's role, `veloraug_app`, the least it needs: the ID, movie and state of **ready originals of published films**. Nothing else in `media_originals`, and nothing in `upload_keys` or `media_renditions`. The media role and the owner are unchanged.

## 2. The API

```text
POST /api/v1/movies/{id}/playback      Authorization: Bearer <access token>

200 {"playlist_url": "https://<gateway>/v1/<grant>/master.m3u8",
     "expires_at": "2026-11-12T22:00:00Z"}
401 Not signed in.           404 This movie isn't available.
409 This movie can't be watched yet.     503 busy, or playback isn't set up
```

- `GET /api/v1/movies/{id}` gains `"playable": true|false`, so the app can show **Watch** only when there is something to watch.
- New settings: `VELORAUG_PLAYBACK_SIGNING_KEY`, secret, at least 32 characters; and `VELORAUG_MEDIA_GATEWAY_URL`, the Worker's address. Without both, the grant answers 503. Production requires both.
- CORS allows `POST`.
- Grants aren't stored. The API logs only that a grant was made, with the film's ID.

## 3. The Worker

In `services/media_gateway/`: TypeScript, Wrangler 4, no runtime dependencies.

1. Match `/v1/<grant>/<file>` and the allowed file names. Otherwise **404**.
2. Check the signature and the expiry. Any failure is **403**, with the same words.
3. Read `movies/<movie>/<original>/<file>` from the R2 binding, passing `Range` and conditional headers. A missing object is **404**.
4. Answer with the object's type, `ETag`, `Accept-Ranges`, and `Cache-Control: private, max-age=3600`. CORS headers for allowed origins. `OPTIONS` and `HEAD` are handled.

Settings: `PLAYBACK_SIGNING_KEY` (secret; locally in `.dev.vars`) and `ALLOWED_ORIGINS` (not secret, in `wrangler.jsonc`).

A shared test vector, a fixed key, grant and expected signature, is checked by both the API's and the Worker's tests, so the two can't drift apart.

## 4. The app

- **Watch** on a film's details: enabled when `playable`. Signed out, it reads **Sign in to watch** and starts sign-in. Not ready, it stays **Coming soon**.
- A **player screen** asks the API for a grant, then plays. Web: a `<video>` element with hls.js 1.7.4 and the browser's own controls, kept in `web/` so no outside script is loaded. Android: `video_player`, which uses ExoPlayer, with play, pause, a seek bar and the time.
- If the Worker refuses a chunk because the grant has run out, the player asks for a new grant once, and starts again where it was.
- New public build setting: `MEDIA_BASE_URL`, default `http://127.0.0.1:8787`, the local Worker. Plain HTTP is allowed only for loopback, as for the API. On a phone, `adb reverse tcp:8787 tcp:8787`.

## Owner setup

### At 8E only

1. Run migration `0004` on the Neon development branch, as for `0003`.
2. Make a signing key: `python -c "import secrets; print(secrets.token_urlsafe(32))"`. Put it in `services/api/.env` as `VELORAUG_PLAYBACK_SIGNING_KEY`, and give it to the Worker with `npx wrangler secret put PLAYBACK_SIGNING_KEY`. Never in a message or a commit.
3. Sign Wrangler in to the Cloudflare account that owns `veloraug-dev` (`npx wrangler login`), and deploy (`npm run deploy`). Put the `workers.dev` address in `VELORAUG_MEDIA_GATEWAY_URL` and in the app's `MEDIA_BASE_URL`.

Nothing is needed from the owner for 8B to 8D.

## Acceptance criteria

### 8B API

- Migration `0004` runs on a local Postgres set up as Neon is. Database checks: `veloraug_app` sees a ready original of a published film, and nothing of an unpublished film's originals, of originals in any other state, of keys or of qualities.
- The grant route answers 200, 401, 404, 409 and 503 as described. A grant's signature verifies, and names the ready original.
- The shared test vector passes.

### 8C Worker

- Tests: a good grant serves each allowed file; a wrong signature, an expired grant, another film's path, an original's path, `..` and unknown files are refused; ranges answer 206; CORS answers allowed origins only.
- The shared test vector passes.
- Run locally with `wrangler dev` and a converted clip, FFmpeg plays the whole film through the Worker, and `curl` without a grant, with a bad one and with an expired one is refused.

### 8D player

- Widget tests for Watch signed in, signed out and not ready, and for the player's grant failures.
- The web build and a debug APK build.

### 8E end to end

- With the migration on Neon and the Worker on Cloudflare, *The Matrix*'s test clip plays on the web in Chrome and on one Android phone, and **seeking** to the middle and back works in both.
- **A real film**, which the owner has the right to use, is uploaded and watched at each quality, and the bitrates are kept or changed.
- **Direct access fails:** the bucket without credentials; the Worker without a grant, with a changed grant, with an expired grant, and with one film's grant for another film.
- An expired grant is renewed in the player without losing the place.

## Cost

Each chunk is one Worker request and one R2 read. A 2-hour film in 6-second chunks is about **1,200 requests per viewing**, plus a few for playlists.

| Plan | Requests | Viewings |
| --- | --- | --- |
| Workers Free | 100,000 a day | about 80 a day |
| Workers Paid, $5 a month | 10 million a month, then $0.30 a million | about 8,000 a month |

R2's free allowance is 10 million reads a month, so reads are free up to about 8,000 viewings, and egress is free. **For a pilot, the free plan is enough.** The paid plan becomes worth it at about 80 viewings a day. The 10 ms CPU limit on the free plan is far more than checking one signature takes.

## Risks

| Risk | What happens |
| --- | --- |
| **A playback address is shared** | Anyone with it can watch that film for up to 6 hours. Shorter grants, or limits per account, can come after the pilot if this is seen |
| A grant expires mid-film | The player renews it and carries on. Tested at 8D and 8E |
| Seeking misbehaves with fMP4 chunks | FFmpeg's own reader couldn't seek into them at 7D. Tested in both real players at 8E |
| The signing key leaks | Change it: every grant ends, and the app asks for new ones |
| hls.js needs a newer browser | hls.js needs Media Source Extensions, in every current desktop and Android browser. iPhones play HLS natively and aren't a target |

## Sources

Read on 12 November 2026:

- [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/): Free, 100,000 requests a day and 10 ms of CPU per request; Paid, $5 a month with 10 million requests, then $0.30 a million
- [R2 Workers API](https://developers.cloudflare.com/r2/api/workers/workers-api-reference/): `get(key, {range, onlyIf})` accepts the request's `Headers`; `R2Object.range`, `writeHttpMetadata` and `httpEtag`
- npm and pub.dev: Wrangler 4.154.0 (27 October 2026), hls.js 1.7.4 (28 October 2026), `video_player` 2.14.1 (2 October 2026)
