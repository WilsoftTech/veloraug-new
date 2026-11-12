# Media worker (placeholder)

The future background processor for movies. Not to be confused with the Cloudflare Worker in [`services/media_gateway/`](../media_gateway/README.md), which delivers video to viewers.

Planned flow:

1. tusd receives an upload. If the connection drops, the upload resumes instead of restarting.
2. FFprobe inspects the file: length, resolution and audio tracks.
3. FFmpeg converts it to HLS, which is many small video chunks plus a playlist.
4. The HLS output is published to private Cloudflare R2 storage.
5. The original is kept in R2's Infrequent Access storage. Telegram may later be a source of originals.

Uploads arrive from Step 7C: tusd writes them to `services/worker/uploads/`, and the upload hooks, in [`services/api/app/media_hooks.py`](../api/app/media_hooks.py), record them. They share the API's code, image and tests, so they live there. See [uploads](../api/README.md#uploads). The worker itself arrived in Step 7D, in [`services/api/app/media_worker.py`](../api/app/media_worker.py), with its image built from `services/api/Dockerfile.worker`. See [convert uploads](../api/README.md#convert-uploads). Uploaded and generated media must never be committed. Keep local test media in a `local-media/` folder. Write generated files to `services/worker/uploads/` for received uploads and `services/worker/transcoding/` for FFmpeg's HLS output. Git ignores all three. Who may upload, and how, is settled in the [uploads plan](../../docs/step-07a-uploads-plan.md).
