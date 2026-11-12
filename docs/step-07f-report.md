# Step 7F report: end to end

Date: 12 November 2026. Branch: `feature/step-07-uploads`. This follows the [uploads plan](step-07a-uploads-plan.md#7f-end-to-end), and closes Milestone 7.

**Step 7F is complete, and so is Milestone 7.** Against the Neon development branch and the private `veloraug-dev` bucket:
- the owner granted keys and uploaded;
- a 720p copy replaced *The Matrix*'s 1080p original;
- a file that isn't a video was refused;
- a revoked key was refused;
- `remove-original` removed an original.

Nobody can watch yet: playback is Milestone 8.

## The runs

All on 12 November 2026, with tusd, the hooks and the worker in Docker on this PC.

| What | How | Result |
| --- | --- | --- |
| **A film, from upload to R2** | Step 7E: the owner granted a key for *The Matrix* and uploaded a 60-second 1080p test clip | Converted to 360p, 480p, 720p and 1080p in 52 s, and published as 50 objects. The original went to Infrequent Access. `ready` |
| **A better copy replaces it** | The owner granted a key and uploaded a 30-second 720p clip to the same film | Converted to 360p, 480p and 720p in 15 s, 0.51 s per second of film, and published as 23 objects. Then the 1080p original was "replaced by" the new one and "removed: 50 objects deleted" |
| The bucket afterwards | Listed by Claude, without printing keys | Only the 720p original's 23 objects, 29.2 MB |
| Neon afterwards | Read as the owner | The 720p original `ready` with 360p, 480p and 720p. The 1080p one `removed`, its qualities deleted. Exactly one `ready` original for the film |
| **A file that isn't a video** | Step 7D: 8 MB of random bytes, uploaded with a key in Step 7C | `refused`: "The file isn't a video VeloraUG can read." The file was deleted |
| **A revoked key** | The owner revoked the unused key from Step 7B. Claude then tried to upload with it | Refused before any data was sent: "This upload key doesn't work. It may be mistyped, already used, expired or revoked. Ask VeloraUG's owner for a new one." The hooks logged "upload refused: the key doesn't work". No progress file was left |
| **`remove-original`** | The owner typed `remove` for the refused original | It became `removing`, then the worker marked it `removed`, "0 objects deleted", since a refused file never reaches R2. Its reason was kept |
| **Keys after use** | `uploads 603` and `uploads 550` | Each used key `used`, the revoked one `revoked`, the unused 7D key still unused and expiring on 13 November |

**Not run on Neon:**
- **An expired key.** No key had expired yet. Expiry was checked against a throwaway database in [gate U1's setup](step-07c-report.md#other-checks-on-the-same-setup), where an expired key was refused with `403`. It is also covered by the tests from Step 7B.
- **The planned "refused file" upload with a fresh key** was skipped. A random file had already been refused on Neon in Step 7D, so it wasn't needed.

## Use of R2

| | Now |
| --- | --- |
| Objects in `veloraug-dev` | 23, all for the 720p test clip |
| Standard storage | The 3 qualities of a 30-second clip, about 20 MB |
| Infrequent Access | The 9.2 MB 720p original. The 1080p original, 97.9 MB, was deleted, but Infrequent Access bills it for 30 days from its upload |
| Cost | Within the free allowance for Standard. Infrequent Access has no free allowance: about 107 MB for a month is a small fraction of a cent |

## Real sizes

| Clip | Original | Qualities |
| --- | --- | --- |
| 60 s, 1920×1080, H.264 + AAC, a test pattern | 97.9 MB | 360p 6.7 MB, 480p 11.2 MB, 720p 21.7 MB, 1080p 38.3 MB: 77.9 MB, about **9.3 GB for 2 hours** |
| 30 s, 1280×720, H.264 + AAC, a test pattern | 9.2 MB | 360p, 480p, 720p: about 20 MB in all |

These match the plan's estimate of 9.4 GB for a 2-hour film in all four qualities.

## Acceptance criteria

| Criterion | State |
| --- | --- |
| The owner grants a key and uploads a 1080p clip, sees it `ready` with four qualities, then replaces it with a 720p clip and sees three | **Met** |
| A refused file, an expired key and a revoked key behave as described | **Met**: refused and revoked on Neon. Expired on a throwaway database, and in the tests |
| The report records R2 use and the real sizes of the test files | **Met**. See above |

## What Milestone 7 leaves for later

| Item | When |
| --- | --- |
| **Seeking** in real players, hls.js on the web and ExoPlayer on Android. FFmpeg's own HLS reader can't jump into the middle of fMP4 chunks, though the chunks are sound | Milestone 8 |
| **Watching a real film**, to check the bitrates by eye. Only test patterns were looked at | Milestone 8, with the player |
| What the API gives the player: the API's role can't read originals or qualities yet | Milestone 8 |
| Trusted uploaders outside this PC, over HTTPS | Milestone 10 |
| Conversion speed on the Oracle server's 4 ARM cores, and an ARM64 worker image | Milestone 10 |
| The worker's image is 888 MB, mostly FFmpeg's libraries | Milestone 10, if size matters there |
| Running more than one worker needs leases on originals | When one isn't enough |
| A publish that fails 3 times is `failed`, with no command to try again | When it first happens |
| Telegram as a source of originals | A later milestone |
| Storage cost at about $20 a month for 100 films | On the [pre-launch check](roadmap.md#check-before-launch) |

## The test films stay

*The Matrix* keeps its 720p test original, `ready` in R2, for playback tests in Milestone 8. The test clips stay in `local-media/`, which Git ignores. tusd, the hooks and the worker are still running. To stop them:

```powershell
cd C:\Users\Wilsoft\veloraug\infra
docker compose -f compose.local.yaml --profile uploads stop media-hooks tusd media-worker
```
