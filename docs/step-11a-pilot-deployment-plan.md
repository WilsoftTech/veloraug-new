# Step 11A plan: pilot deployment

Date: 19 November 2026. This plans Milestone 11 in the [roadmap](roadmap.md): VeloraUG running without this PC, for a limited pilot. **Approved by the owner on 20 November 2026, with every recommendation accepted** (see [the owner's decisions](#owner-decisions)). Nothing in it is built yet.

Facts about Oracle, Cloudflare and Neon below are from earlier plans and general knowledge of their free tiers, **not checked on this date**. Each is marked *to confirm*, and is checked in the step that relies on it.

## Why this milestone exists

Today everything except the video runs on the owner's PC: the API, sign-in checks, payments, uploads and converting. When the PC is off, nobody can start a film. Uploading is also limited by the home connection: each film sends about 2.6 GB of qualities to R2.

After Milestone 11:
- **Viewers can watch at any hour**, from anywhere, with the PC off.
- **Admins can upload from any computer.** The server converts, and sends the qualities to R2 over a data-centre connection. The home connection carries only the original, about 1.5 GB, once.
- **Pesapal's notifications reach the API**, because it has a public address.

## Summary

- **One Oracle Cloud ARM server, on Always Free**, in Frankfurt next to Neon: the API, the upload hooks, tusd and the media worker, in Docker Compose. *To confirm:* Always Free includes up to 4 ARM cores, 24 GB of memory and 200 GB of disk.
- **No open ports on the server.** A **Cloudflare Tunnel** carries `api.` and `upload.` to it over HTTPS. Only SSH is open, with a key, from the owner.
- **A domain of the owner's own**, on Cloudflare, for every public address:

  | Address | What serves it |
  | --- | --- |
  | `app.<domain>` | The Flutter web app, on Cloudflare Pages |
  | `auth.<domain>` | The sign-in pages, on Cloudflare Pages |
  | `api.<domain>` | The API, through the tunnel |
  | `upload.<domain>` | tusd, through the tunnel |
  | `media.<domain>` | The media gateway Worker, with a production bucket |

- **Production is separate from development:** Neon's default branch, its own Neon Auth, R2 bucket, Worker, signing key and Pesapal settings. The development branch and this PC carry on as they are, for testing.
- **Images are built on the server itself,** which is ARM64. That avoids building ARM64 images on this AMD64 PC.
- **The pilot starts with invited viewers and passes off.** Live payments come once the [launch checks](roadmap.md#check-before-launch) are done.

## Implementation sequence

| Step | Scope | Finished when |
| --- | --- | --- |
| **11A**, this step | This plan | The owner approves it, with [the decisions](#owner-decisions) |
| **11B** | The server: the owner creates the Oracle account and server, guided step by step. Hardening, Docker, and the repository. The images built there, and the API's tests run there | [Gates P1 to P3](#gates) pass |
| **11C** | `infra/compose.prod.yaml`, production settings, the Cloudflare Tunnel, and a deploy script. Written on this PC, then run on the server | [11C criteria](#11c-server-and-tunnel) pass |
| **11D** | Cloudflare: the domain, the production R2 bucket, the Worker on `media.`, and the web app and sign-in pages on Pages | [11D criteria](#11d-cloudflare) pass |
| **11E** | Neon production: migrations `0001` to `0006` on the default branch, the three roles, Neon Auth with production clients, Allow Localhost off, a sender domain and SMTP, and the first admin | [Gate P4](#gates) passes |
| **11F** | Content: the films published on development copied to production, files and rows | [11F criteria](#11f-content) pass |
| **11G** | Android: the production app ID, a release signing key, App Links on `auth.`, and a release build | [Gate P5](#gates) passes |
| **11H** | The pilot: invited viewers for 30 days, uptime checks, and costs measured | [Gate P6](#gates) recorded |

11B, 11E and 11G need the owner at the keyboard: accounts, keys and passwords are theirs. 11C, 11D and 11F are mostly written here first.

Not in Milestone 11: more than one server; automatic scaling; a CDN cache in front of the Worker; Pesapal live payments, which wait for the launch checks; the Google Play Store listing; Telegram as a source; monitoring beyond uptime checks and logs.

## Decisions

| # | Decision | Why |
| --- | --- | --- |
| 1 | **Oracle Always Free, one ARM server** (VM.Standard.A1.Flex, 4 cores, 24 GB), Ubuntu 24.04, in **Frankfurt** (`eu-frankfurt-1`) | In the architecture since Milestone 1. Next to Neon, so each query is a short trip. Free within its limits |
| 2 | **Upgrade the Oracle account to Pay As You Go**, staying within the free limits | *To confirm:* Oracle can reclaim idle Always Free servers, and PAYG accounts are exempt. PAYG also makes ARM capacity easier to get. It needs a card, but costs nothing within the limits. A budget alert at $1 catches mistakes |
| 3 | **A Cloudflare Tunnel** (`cloudflared` in Compose) for `api.` and `upload.`. **No inbound ports** but SSH | HTTPS certificates, DDoS protection and hiding the server's address, at no cost. No firewall rules to get wrong |
| 4 | **SSH by key only**, no passwords, no root login. Automatic security updates. The Oracle firewall allows SSH only | The usual minimum for a server on the internet |
| 5 | **Build images on the server**: `git pull`, then `docker compose build` | It's ARM64, so images are native. No registry or cross-building needed for one server. A registry can follow if there are more servers |
| 6 | **`infra/compose.prod.yaml`**, separate from the local file: restart always, log rotation, no published ports, secrets in `/opt/veloraug/env/*.env` readable only by the deploy account | As [`infra/README.md`](../infra/README.md) requires |
| 7 | **Production settings:** `VELORAUG_ENVIRONMENT=production`, exact origins (`https://app.<domain>`), `/docs` off, passes off at first | Production already refuses to start without sign-in, the database and playback |
| 8 | **tus chunks stay at 50 MB** | *To confirm:* Cloudflare's free plan refuses request bodies over 100 MB, through the tunnel too. 50 MB chunks fit, and resuming works as now |
| 9 | **Production has its own of everything:** Neon default branch and Auth, R2 bucket `veloraug`, Worker `veloraug-media`, signing key, upload key secrets, Pesapal IPN registration | A test on development can never touch viewers or their payments. As planned since Milestone 5 |
| 10 | **Neon's default branch for production**, created empty in Milestone 5 for this. Neon's Free plan first, measured over the pilot | Decision 1 of the Neon plan. *To confirm:* whether the API's connection pool stops the database scaling to zero, which decides between Free and Launch |
| 11 | **Production sign-in:** Neon Auth on the default branch, sign-in pages on `auth.<domain>`, OAuth clients for `https://app.<domain>` and Android, **Allow Localhost off**, and **custom SMTP from a sender address on the domain** | Required before real users, per the Neon plan: Neon's shared email isn't for production |
| 12 | **Films move from development to production by copying**, not by uploading again: an owner command copies a published edition's rows, and server-side copies its R2 files from `veloraug-dev` to `veloraug` | Each film took hours to upload and convert. Copying inside R2 takes minutes and needs no home upload. Test editions and test payments stay behind |
| 13 | **The media worker runs on the server**, converting at the same settings as now | Uploads no longer depend on the PC. *Gate P3* measures how fast 4 ARM cores convert |
| 14 | **Uploads queue on the server's disk**, at most 150 GB, with a warning in the admin screens when free space falls below 20 GB | The free tier's disk is 200 GB in total. At about 1.5 GB per original plus 3 GB while converting, about 40 films can wait |
| 15 | **The pilot starts with passes off,** for invited viewers. Sandbox payments are checked end to end there, with Pesapal's notifications now arriving. Live payments follow the launch checks | No money is taken before the rights and TMDB terms are settled |
| 16 | **Uptime checks** on `api.` and `media.` every 5 minutes, emailing the owner. Logs stay on the server for 14 days | Enough to know when the pilot is down. A free uptime service does this |
| 17 | **Deploying is one script**, `infra/deploy.sh`, run by the owner over SSH: pull, build, migrate check, restart, health check | Repeatable, and a failed health check says so at once. Automatic deployment from GitHub can follow |
| 18 | **Backups:** Neon's own point-in-time restore for the database. R2 holds every published file. The `.env` files are kept in the owner's password manager | The server holds nothing that can't be rebuilt from Git, the `.env` files and R2 |

### Routes ruled out

| Route | Why not |
| --- | --- |
| Opening ports 80 and 443 with Caddy or nginx | Works, but exposes the server's address, and certificates and firewall rules become ours to maintain. The tunnel does both |
| Building ARM64 images on this PC under emulation | Slow, and FFmpeg under emulation can't be timed. The server builds natively |
| GitHub Actions ARM64 runners | *To confirm:* free for public repositories, not private ones. Not needed for one server |
| Promoting the development branch to production | It holds test films, test accounts and test payments, and Allow Localhost is on there |
| Uploading every film again on production | Hours per film over the home connection. Copying in R2 avoids it |
| A second server for converting | Not needed at pilot scale. Measured in P3 and the pilot |
| Keeping everything on this PC behind a tunnel | Viewers would depend on the PC and home power and internet. The point of this milestone is to stop that |

## Owner decisions

On 20 November 2026 the owner accepted every recommendation below. So:
- **D1:** `veloraug.com` through Cloudflare Registrar. On 20 November it had no DNS records, so it looked unregistered, but that's only confirmed when it's bought. If it's taken, the owner picks another `.com`, and D5 follows the new name.
- **D2:** Oracle Pay As You Go, with a $1 budget alert.
- **D3:** the films are copied from development.
- **D4:** 10 to 30 invited viewers for 30 days, with passes off.
- **D5:** the app ID is `com.veloraug.app`.
- **D6:** a direct APK.
- **D7:** Brevo or Resend, chosen at 11E by whichever free tier fits then.

| # | Question | Recommendation |
| --- | --- | --- |
| D1 | **Which domain?** It appears in every address, in sign-in, and in the Android app ID | A `.com` such as `veloraug.com`, bought through Cloudflare Registrar at cost, about $10 a year. A `.ug` domain is possible but costs more, and can't be bought through Cloudflare |
| D2 | **Oracle account**: do you have one, and will you upgrade it to Pay As You Go? | Yes to PAYG (decision 2), with a $1 budget alert |
| D3 | **Production content:** copy the films from development (decision 12), or start empty? | Copy |
| D4 | **The pilot's viewers:** how many, and who? | 10 to 30 invited people, for 30 days, passes off |
| D5 | **The Android app ID**, which can never change once published | From the domain, such as `com.veloraug.app` |
| D6 | **Android distribution for the pilot:** an APK sent directly, or Google Play internal testing? | Direct APK for the pilot. Play needs a $25 developer account and a review, and can follow |
| D7 | **Email for sign-in codes:** which SMTP provider? | One with a free tier and a sender on the domain, such as Brevo or Resend. The owner signs up, and the credentials go in the Neon Console only |

## 1. The server (11B, 11C)

```text
Oracle A1 server, Frankfurt, Ubuntu 24.04 ARM64
  /opt/veloraug/repo       the Git checkout
  /opt/veloraug/env/       api.env, media.env, r2.env, tunnel.env: mode 600, not in Git
  /opt/veloraug/uploads    tusd's files, up to 150 GB
  /opt/veloraug/output     converting
  Docker Compose (infra/compose.prod.yaml):
    api           FastAPI, port 8000 on the internal network only
    media-hooks   tusd's hooks
    tusd          port 1080 on the internal network only
    media-worker  FFmpeg, publishes to the production bucket
    cloudflared   the tunnel: api.<domain> -> api:8000, upload.<domain> -> tusd:1080
```

## 2. Cloudflare (11D)

- **DNS** for the domain on Cloudflare.
- **R2 bucket `veloraug`**, private, with its own S3 keys for the media worker only.
- **Worker `veloraug-media`** on `media.<domain>`, bound to `veloraug`, with the production signing key as a secret.
- **Pages project for the web app,** built with production `--dart-define`s: the API, media, upload and sign-in addresses. Served on `app.<domain>`.
- **Pages project for the sign-in pages** on `auth.<domain>`, serving `assetlinks.json` with the production app ID and release certificate.
- **One rate-limiting rule** on `api.<domain>/api/v1/passes/*`. *To confirm:* the free plan includes one.

## 3. Neon (11E)

Run on the default branch by the owner, as before: migrations `0001` to `0006`, `create_app_role.py` for the app, editor and media roles, and `check_database.py`. Then Neon Auth: trusted domains `app.` and `auth.`, OAuth clients for web and Android, Allow Localhost off, custom SMTP, and the first admin with the owner's command.

## 4. Content (11F)

A new owner command, `copy-to-production`, reads published editions on development and, for each one:
1. copies its source, VJ, language, edition and item rows to production with the same IDs;
2. server-side copies its R2 folder `movies/<item>/<original>/` from `veloraug-dev` to `veloraug`;
3. adds the original's row as `ready`, with its qualities;
4. checks every object's size in the production bucket.

It skips test editions, and editions already on production, so it can be run again safely.

## 5. Android (11G)

Production app ID (D5), a release signing key kept outside the repository with a backup, the release certificate's fingerprint in production `assetlinks.json`, and production settings in a `dart_defines.prod.json` that holds only public values.

## Gates

| Gate | Question | Pass | If it fails |
| --- | --- | --- | --- |
| P1 | Can the owner get an A1 server in Frankfurt? | A running server with 4 cores and 24 GB | Try other availability domains, then a smaller shape (2 cores, 12 GB). Then the owner decides on another region or provider |
| P2 | Do the images build and the API's tests pass on ARM64? | All of them, on the server | Fix per package. FFmpeg and tusd have ARM64 builds; *to confirm* |
| P3 | How fast does the server convert a real film? | Recorded: seconds per second of film, for one of the VJ films | Under 1.5: fine. Slower: the owner decides between waiting and a faster shape |
| P4 | Does production sign-in work on `app.` and a phone, with email codes from the sender domain? | Yes, in Chrome and on one phone | As in Milestone 5: stop and decide |
| P5 | Does the release app sign in and play on a phone? | Yes, with App Links verified | Check the fingerprint in `assetlinks.json` |
| P6 | What does the pilot cost per month? | Recorded for 30 days, against the $20 target | The owner decides what to change: see [Cost](#cost) |

## Acceptance criteria

### 11C server and tunnel

- Only SSH answers on the server's public address; a port scan finds nothing else.
- `https://api.<domain>/health` answers through the tunnel; `/docs` doesn't.
- An upload of a 3 GB file from the admin screens resumes after the browser loses its connection, through the tunnel.
- Restarting the server brings every service back by itself.
- `deploy.sh` deploys a change and reports the health check.

### 11D Cloudflare

- `app.`, `auth.`, `api.`, `upload.` and `media.` answer over HTTPS.
- `media.` refuses a request without a grant, and serves a production grant's playlist.
- `veloraug` has no public access and no `r2.dev` address.

### 11F content

- Every published development film is on production with the same IDs, plays on `app.`, and shows its VJ, poster and qualities.
- No test edition or test payment is on production.
- Running the command again copies nothing twice.

### 11H pilot

- 30 days with the invited viewers. Uptime, problems reported, and every cost recorded.
- One Pesapal sandbox pass bought on production, confirmed by a notification that reached the API.

## Cost

Expected monthly costs for the pilot. *Not measured:* P6 measures them.

| Item | Expected |
| --- | --- |
| Oracle A1 server | $0 within Always Free |
| Cloudflare: DNS, Tunnel, Pages | $0 |
| Cloudflare Workers | $0 under 100,000 requests a day, about 100 films watched a day; then $5 a month. *To confirm* |
| R2 | About $0.04 per film per month at today's settings, plus $0.015 per GB for the development bucket while it's kept |
| Neon | $0 on Free if it scales to zero, otherwise a few dollars on Launch |
| Domain | About $10 a year |
| SMTP | $0 on a free tier at pilot volumes |
| **Total** | **About $0 to $10 a month**, mostly R2 and Neon |

## Risks

| Risk | What happens |
| --- | --- |
| **No ARM capacity at Oracle** | Common in busy regions. PAYG helps. Gate P1 decides |
| **Oracle reclaims or suspends the server** | *To confirm:* PAYG accounts are exempt from idle reclaiming. Everything can be rebuilt from Git, the `.env` files and R2 in about an hour, using the deploy script |
| **One server is a single point of failure** | Video keeps working for anyone holding a grant, from Cloudflare. New grants, sign-in checks and uploads stop until it's back. Accepted for a pilot |
| **Content complaints** | Cloudflare, Oracle and Pesapal can all close accounts over copyright complaints. The [launch checks](roadmap.md#check-before-launch) come before any public launch |
| **Cloudflare's 100 MB request limit** | tus chunks are 50 MB. Gate 11C's 3 GB upload checks it |
| **The server's disk fills** | Decision 14's limit and warning. Originals are deleted once published, as now |
| **A secret on the server leaks** | Each production secret is separate from development's and can be changed alone: the signing key ends every grant, as designed |

## What I need from the owner to start 11B

The plan is approved and D1 to D7 are answered. What's left is the owner's own setup, done together, with the owner typing every password and key:
1. Buy the domain (D1) in the Cloudflare dashboard.
2. Create the Oracle account in Frankfurt, upgrade it to Pay As You Go, and set the $1 budget alert (D2).
3. Create an SSH key on this PC for the server.
