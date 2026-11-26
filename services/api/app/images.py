"""Image addresses: TMDB's for TMDB paths, the media gateway's for images
admins uploaded (Step 9C). Anything else gives no address, so a strange
path can't become part of one.
"""

import re
from dataclasses import dataclass

from app.tmdb import DEFAULT_IMAGES, ImageConfig

_TMDB = re.compile(r"^/[A-Za-z0-9_-]{1,100}\.(jpg|jpeg|png)$")
_UPLOADED = re.compile(
    r"^(posters|vjs)/[0-9a-f-]{36}/[A-Za-z0-9_-]{16,43}\.(jpg|png|webp)$"
)


@dataclass(frozen=True)
class ImageUrls:
    tmdb: ImageConfig = DEFAULT_IMAGES
    # The media gateway's address, or None when playback isn't set up.
    gateway: str | None = None

    def _uploaded(self, path: str) -> str | None:
        if self.gateway and _UPLOADED.match(path):
            return f"{self.gateway.rstrip('/')}/i/{path}"
        return None

    def poster(self, path: str | None) -> str | None:
        if not path:
            return None
        if _TMDB.match(path):
            return self.tmdb.poster_url(path)
        return self._uploaded(path)

    def backdrop(self, path: str | None) -> str | None:
        if not path:
            return None
        if _TMDB.match(path):
            return self.tmdb.backdrop_url(path)
        # One an admin uploaded for the edition (Step 13H).
        return self._uploaded(path)

    def hero_backdrop(self, path: str | None) -> str | None:
        if not path:
            return None
        if _TMDB.match(path):
            return self.tmdb.hero_backdrop_url(path)
        return self._uploaded(path)

    def photo(self, path: str | None) -> str | None:
        return self._uploaded(path) if path else None
