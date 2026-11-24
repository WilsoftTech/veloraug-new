# Media gateway

The Cloudflare Worker that delivers video to viewers. It sits in front of the private R2 bucket, checks each request's playback grant, and only then serves the file. Not to be confused with the media worker in [`services/api/app/media_worker.py`](../api/app/media_worker.py), which converts movies in the background.

Planned in the [playback plan](../../docs/step-08a-playback-plan.md).

```text
app --POST /api/v1/movies/{id}/playback--> API: checks the viewer, signs a grant
app --GET /v1/<grant>/master.m3u8--> this Worker: checks the grant --> private R2
player --GET /v1/<grant>/720p/seg_00042.m4s--> the same, for every chunk
```

## What it serves

| Address | From R2 |
| --- | --- |
| `/v1/<grant>/master.m3u8` | `movies/<movie>/<original>/master.m3u8` |
| `/v1/<grant>/<360p…1080p>/index.m3u8`, `init*.mp4`, `seg_<n>.m4s` | the same under `movies/<movie>/<original>/` |
| `/v1/<grant>/<360p…1080p>/download.mp4?name=<file name>` | the same. A quality's whole video as one file, sent as an attachment named by `?name=`, made safe, so a browser saves it. [Downloads](../../docs/step-12a-downloads.md) |

The movie and original come from the grant, never from the address, so a grant opens one movie and nothing else. Originals are never served. Any other address is `404`.

| Answer | When |
| --- | --- |
| `200`, or `206` for a range | A good grant and an existing file |
| `304` | The player already has this version |
| `403 Not allowed.` | The grant is missing its signature, changed, signed with another key or expired, or the request came from a web origin not in `ALLOWED_ORIGINS`. The same words for all |
| `404 Not found.` | Not an address above, or not in R2 |
| `503` | No signing key, or one under 32 characters |

From Step 9C a "movie" here is a playable item, a movie edition or an episode, and R2 still keeps it under `movies/`, so nothing published before moved.

**Uploaded images, Step 9C.** Admins' posters and VJ photos:

| Address | Does |
| --- | --- |
| `PUT /i/<upload grant>` | Stores one image, from an admin's browser. The API signs the upload grant for one path and type, for 10 minutes, with the same key but its own purpose, so it can never pass for a playback grant. JPEG, PNG or WebP, at most 2 MB, and its first bytes must match its type. `201` with its path; `403`, `413` or `415` otherwise |
| `GET /i/posters/<edition>/<name>`, `GET /i/vjs/<VJ>/<name>` | The image, to anyone, cached for a year: each upload gets a new random name. Nothing else under `/i/` is served |

The playlists name their files relative to themselves, so the grant in the path carries over to every playlist and chunk, in hls.js and ExoPlayer alike. Answers are `Cache-Control: private`, so a shared cache never keeps someone's grant. Nothing here logs an address. The local `wrangler dev` does print each one, grant included, to its own terminal.

## Playback sessions (Milestone 10)

With passes required, the API's grants carry `"s"`, a random playback-session ID. The Worker serves such a grant only while the API says its session is live: `GET <API_URL>/api/v1/gateway/sessions/<s>` with `X-Velora-Gateway: <expires>.<HMAC-SHA256 of "veloraug-gateway-v1." + s + "." + expires>`, signed with the same `PLAYBACK_SIGNING_KEY`. The answer is kept for 30 seconds in the isolate. If the API can't be reached, a session seen live within 2 minutes carries on; otherwise `503`. A stopped session, a removed device or a pass that has ended or been reversed gets `403` within about 30 seconds. Grants without `"s"` (admins, and every grant while passes are off) are served as before, without asking. See `src/sessions.ts`.

**Deploy order:** this Worker accepts today's grants, and an older Worker ignores `"s"`, so either can be deployed first. Revocation only takes effect once this Worker runs with `API_URL`. The development Worker's `API_URL` is `http://127.0.0.1:8000`, which a deployed `workers.dev` Worker can't reach: on the deployed development Worker, set it to an address the Worker can reach before testing sessions there.

## Files

| File | Job |
| --- | --- |
| `src/index.ts` | The Worker: matches addresses, checks grants, reads R2, CORS and ranges |
| `src/grant.ts` | Checks a grant's signature and expiry, with Web Crypto |
| `src/images.ts` | Checks upload grants, and that an uploaded file is the image it claims to be |
| `test/` | Tests, run by Node's own test runner. `grant-vector.json` is shared with the API's tests |
| `wrangler.jsonc` | The Worker's name, R2 binding and allowed web origins. Nothing secret |
| `.dev.vars.example` | The template for `.dev.vars`, the Git-ignored local secret |
| `package.json`, `package-lock.json` | Wrangler, pinned, as the only dependency. Nothing runs in the Worker but this code |

## Settings

| Name | Where | Meaning |
| --- | --- | --- |
| `PLAYBACK_SIGNING_KEY` | **Secret.** `.dev.vars` locally, a Worker secret on Cloudflare | Exactly the API's `VELORAUG_PLAYBACK_SIGNING_KEY` |
| `ALLOWED_ORIGINS` | `vars` in `wrangler.jsonc` | Web app origins allowed to read video, separated by commas. Requests with no `Origin`, as from ExoPlayer, are checked by grant only |
| `API_URL` | `vars` in `wrangler.jsonc` | Milestone 10. The API's origin, asked whether a grant's playback session is still live. Without it, a grant that names a session gets `503`; grants without one are served as before |
| `MEDIA` | `r2_buckets` in `wrangler.jsonc` | The bucket, `veloraug-dev` |

## Setup

Needs Node 24 or later.

```powershell
cd C:\Users\Wilsoft\veloraug\services\media_gateway
npm ci
npm test
```

npm 11 may say it skipped `workerd`'s install script. Wrangler still runs without it.

## Run it locally

```powershell
Copy-Item .dev.vars.example .dev.vars
# Put the same key as services/api/.env's VELORAUG_PLAYBACK_SIGNING_KEY in .dev.vars
npm run dev
```

It answers on `http://127.0.0.1:8787` only. **Locally, R2 is a copy in `.wrangler/state`, which starts empty**, so the Worker never touches the real bucket. To put a converted film in it, for a movie and original that exist in your database:

```powershell
$prefix = "movies/<movie id>/<original id>"
Get-ChildItem -Recurse -File <folder of converted HLS> | ForEach-Object {
  $rel = $_.FullName.Substring((Resolve-Path <folder of converted HLS>).Path.Length + 1).Replace('\', '/')
  $type = @{ '.m3u8' = 'application/vnd.apple.mpegurl'; '.m4s' = 'video/iso.segment'; '.mp4' = 'video/mp4' }[$_.Extension]
  npx wrangler r2 object put "veloraug-dev/$prefix/$rel" --file $_.FullName --content-type $type --local
}
```

**Stopping it:** press `Ctrl+C` in its terminal. Stopping it any other way can leave `workerd.exe` running and still answering on port 8787, with old settings. Close those in Task Manager.

## Deploy it (Step 8E)

Only the owner does this, with the Cloudflare account that owns `veloraug-dev`:

```powershell
npx wrangler login
npx wrangler secret put PLAYBACK_SIGNING_KEY
npm run deploy
```

`wrangler secret put` asks for the value: paste the same key as the API's. The deploy prints the Worker's `workers.dev` address. Put it in the API's `VELORAUG_MEDIA_GATEWAY_URL` and the app's `MEDIA_BASE_URL`, and add the web app's real origin to `ALLOWED_ORIGINS` when it has one.

## Cost

About 1,200 requests per two-hour viewing, one per chunk. Workers Free allows 100,000 a day, about 80 viewings. See [cost](../../docs/step-08a-playback-plan.md#cost).
