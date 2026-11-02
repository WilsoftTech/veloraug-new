# Media worker (placeholder)

The future background processor for movies. Not to be confused with the Cloudflare Worker in [`services/media_gateway/`](../media_gateway/README.md), which delivers video to viewers.

Planned flow:

1. tusd receives an upload. If the connection drops, the upload resumes instead of restarting.
2. FFprobe inspects the file: length, resolution and audio tracks.
3. FFmpeg converts it to HLS, which is many small video chunks plus a playlist.
4. The HLS output is published to private Cloudflare R2 storage.
5. Optionally, the original file is archived to Telegram.

No code exists yet. Uploaded and generated media must never be committed. Keep local test media in a `local-media/` folder. Write generated files to `services/worker/uploads/` for received uploads and `services/worker/transcoding/` for FFmpeg output. Git ignores all three. Who may upload is an [open design task](../../docs/architecture.md#open-design-tasks).
