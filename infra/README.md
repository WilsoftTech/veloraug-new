# Infrastructure (placeholder)

Planned home for deployment configuration. Nothing here has been created or deployed.

| Planned item | Purpose |
| --- | --- |
| Docker Compose file | Runs the API, media worker and tusd on the Oracle server |
| Dockerfiles or build notes | Build the images for those services |
| Cloudflare Worker configuration | Protected media delivery |
| Cloudflare Pages notes | Hosting for the Flutter web build |
| `.env.example` | Variable names with fake values, created when variables first exist |

## Oracle images must support ARM64

The production server uses an ARM64 processor. This Windows machine's Docker engine reports `linux/amd64`, so an image built here by default will not be the right type for production.

Every production image must have an ARM64 build, including base images and our own. FFmpeg, tusd and any Python packages with compiled parts need checking too. An ARM64 image has not been built or run yet.
