# API (placeholder)

The future FastAPI service, written in Python. It is the trusted part of the system: the app asks it to do things, and it checks whether each request is allowed.

Planned responsibilities:

- Verify users signed in through Supabase
- Fetch movie details from TMDB, keeping the TMDB key private
- Start and confirm Pesapal payments
- Decide who may watch what, and issue playback access

No code or dependencies exist yet. When Python work starts, this service gets its own virtual environment: a private folder of packages for this project only, kept out of Git.
