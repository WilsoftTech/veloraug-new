# Media gateway (placeholder)

The future Cloudflare Worker, which delivers video to viewers. It sits in front of private R2 storage, checks that a viewer has access, and only then serves the video. Not to be confused with `services/worker/`, which processes movies in the background.

No code or Node dependencies exist yet. How the Worker checks a viewer's access is an open design task: see [open design tasks](../../docs/architecture.md#open-design-tasks).
