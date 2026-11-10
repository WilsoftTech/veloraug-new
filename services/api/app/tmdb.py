"""TMDB's movie details, fetched with the v4 read access token.

The token goes in the Authorization header, never the address, so it can't
reach a log line through a URL. Errors carry a status code or an exception
type only: no token, response body or TMDB message.

See docs/step-06a-catalogue-plan.md. TMDB's terms limit how long its data may
be kept, which the callers enforce.
"""

from dataclasses import dataclass
from datetime import date
from types import TracebackType
from typing import Any, Self

import httpx2

API_BASE = "https://api.themoviedb.org/3"
LANGUAGE = "en-US"
TIMEOUT_SECONDS = 10.0


class TmdbError(Exception):
    """TMDB couldn't give the details. The message is safe to show."""


class TmdbNotFound(TmdbError):
    """TMDB has no movie with this ID."""


class TmdbRefused(TmdbError):
    """TMDB refused the token."""


class TmdbUnavailable(TmdbError):
    """TMDB timed out, failed, sent something unexpected, or asked us to wait."""

    def __init__(self, message: str, retry_after: float | None = None) -> None:
        super().__init__(message)
        self.retry_after = retry_after


@dataclass(frozen=True)
class MovieDetails:
    tmdb_id: int
    title: str
    original_title: str | None
    overview: str | None
    release_date: date | None
    runtime_minutes: int | None
    genres: tuple[str, ...]
    poster_path: str | None
    backdrop_path: str | None

    @property
    def year(self) -> int | None:
        return self.release_date.year if self.release_date else None


def _text(value: Any) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def _image_path(value: Any) -> str | None:
    # TMDB's paths look like /abc123.jpg. Anything else isn't used, so a
    # strange value can't become part of an image address.
    path = _text(value)
    if path and path.startswith("/") and "/" not in path[1:] and ".." not in path:
        return path
    return None


def _date(value: Any) -> date | None:
    try:
        return date.fromisoformat(value) if isinstance(value, str) else None
    except ValueError:
        return None


def parse_movie(data: Any, tmdb_id: int) -> MovieDetails:
    """MovieDetails from TMDB's /movie/{id} answer, or TmdbUnavailable."""
    if not isinstance(data, dict) or data.get("id") != tmdb_id:
        raise TmdbUnavailable("TMDB sent an answer for a different movie")
    title = _text(data.get("title"))
    if title is None:
        raise TmdbUnavailable("TMDB sent a movie with no title")
    runtime = data.get("runtime")
    genres = data.get("genres")
    return MovieDetails(
        tmdb_id=tmdb_id,
        title=title,
        original_title=_text(data.get("original_title")),
        overview=_text(data.get("overview")),
        release_date=_date(data.get("release_date")),
        # TMDB uses 0 for an unknown runtime.
        runtime_minutes=runtime if isinstance(runtime, int) and runtime > 0 else None,
        genres=tuple(
            name
            for genre in (genres if isinstance(genres, list) else [])
            if isinstance(genre, dict) and (name := _text(genre.get("name")))
        ),
        poster_path=_image_path(data.get("poster_path")),
        backdrop_path=_image_path(data.get("backdrop_path")),
    )


def _retry_after(response: httpx2.Response) -> float | None:
    try:
        return max(0.0, float(response.headers.get("Retry-After", "")))
    except ValueError:
        return None


class TmdbClient:
    def __init__(
        self,
        token: str,
        *,
        transport: httpx2.BaseTransport | None = None,
        timeout: float = TIMEOUT_SECONDS,
    ) -> None:
        if not token.strip():
            raise ValueError("The TMDB token is empty")
        self._client = httpx2.Client(
            base_url=API_BASE,
            headers={
                "Authorization": f"Bearer {token.strip()}",
                "Accept": "application/json",
            },
            timeout=timeout,
            transport=transport,
            follow_redirects=False,
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(
        self,
        kind: type[BaseException] | None,
        error: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self.close()

    def movie(self, tmdb_id: int) -> MovieDetails:
        if tmdb_id <= 0:
            raise ValueError("A TMDB ID is a positive number")
        try:
            response = self._client.get(
                f"/movie/{tmdb_id}", params={"language": LANGUAGE}
            )
        except httpx2.TimeoutException:
            raise TmdbUnavailable("TMDB didn't answer in time") from None
        except httpx2.HTTPError as error:
            raise TmdbUnavailable(
                f"Couldn't reach TMDB ({type(error).__name__})"
            ) from None

        status = response.status_code
        if status == 200:
            try:
                data = response.json()
            except ValueError:
                raise TmdbUnavailable("TMDB sent an answer that isn't JSON") from None
            return parse_movie(data, tmdb_id)
        if status == 404:
            raise TmdbNotFound(f"TMDB has no movie {tmdb_id}")
        if status == 401:
            raise TmdbRefused(
                "TMDB refused the token. Copy the API Read Access Token again"
            )
        if status == 429:
            raise TmdbUnavailable(
                "TMDB asked us to slow down", retry_after=_retry_after(response)
            )
        raise TmdbUnavailable(f"TMDB answered {status}")
