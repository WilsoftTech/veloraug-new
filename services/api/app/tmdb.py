"""TMDB's movie details, fetched with the v4 read access token.

The token goes in the Authorization header, never the address, so it can't
reach a log line through a URL. Errors carry a status code or an exception
type only: no token, response body or TMDB message.

See docs/step-06a-catalogue-plan.md. TMDB's terms limit how long its data may
be kept, which the callers enforce.
"""

import re
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
    # TMDB's audience score out of 10, one decimal, and how many votes it is
    # from. Both None when nobody has voted or the values are strange.
    rating: float | None = None
    vote_count: int | None = None

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


# The largest count public.sources.tmdb_vote_count (a Postgres integer) holds.
MAX_VOTE_COUNT = 2**31 - 1


def _rating(data: dict) -> tuple[float | None, int | None]:
    """TMDB's vote_average and vote_count, or (None, None). TMDB sends 0.0
    for a title nobody has rated, which isn't a score of 0."""
    average, count = data.get("vote_average"), data.get("vote_count")
    if (
        isinstance(average, bool)
        or isinstance(count, bool)
        or not isinstance(average, int | float)
        or not isinstance(count, int)
        or not 0 < count <= MAX_VOTE_COUNT
        or not 0 <= average <= 10
    ):
        return None, None
    return round(float(average), 1), count


def parse_movie(data: Any, tmdb_id: int) -> MovieDetails:
    """MovieDetails from TMDB's /movie/{id} answer, or TmdbUnavailable."""
    if not isinstance(data, dict) or data.get("id") != tmdb_id:
        raise TmdbUnavailable("TMDB sent an answer for a different movie")
    title = _text(data.get("title"))
    if title is None:
        raise TmdbUnavailable("TMDB sent a movie with no title")
    runtime = data.get("runtime")
    genres = data.get("genres")
    rating, votes = _rating(data)
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
        rating=rating,
        vote_count=votes,
    )


def parse_series(data: Any, tmdb_id: int) -> MovieDetails:
    """A series' details from TMDB's /tv/{id} answer, in the same shape as a
    movie's: its name as the title, and its first air date as the date."""
    if not isinstance(data, dict) or data.get("id") != tmdb_id:
        raise TmdbUnavailable("TMDB sent an answer for a different series")
    title = _text(data.get("name"))
    if title is None:
        raise TmdbUnavailable("TMDB sent a series with no name")
    runtimes = data.get("episode_run_time")
    runtime = runtimes[0] if isinstance(runtimes, list) and runtimes else None
    genres = data.get("genres")
    rating, votes = _rating(data)
    return MovieDetails(
        tmdb_id=tmdb_id,
        title=title,
        original_title=_text(data.get("original_name")),
        overview=_text(data.get("overview")),
        release_date=_date(data.get("first_air_date")),
        runtime_minutes=runtime if isinstance(runtime, int) and runtime > 0 else None,
        genres=tuple(
            name
            for genre in (genres if isinstance(genres, list) else [])
            if isinstance(genre, dict) and (name := _text(genre.get("name")))
        ),
        poster_path=_image_path(data.get("poster_path")),
        backdrop_path=_image_path(data.get("backdrop_path")),
        rating=rating,
        vote_count=votes,
    )


@dataclass(frozen=True)
class SearchResult:
    """One title TMDB found for a search, movie or series alike."""

    tmdb_id: int
    title: str
    original_title: str | None
    year: int | None
    overview: str | None
    poster_path: str | None


MAX_RESULTS = 20


def parse_search(data: Any, kind: str) -> list[SearchResult]:
    """TMDB's /search/movie or /search/tv answer, first page, in TMDB's
    order. Results without an ID or title are left out."""
    results = data.get("results") if isinstance(data, dict) else None
    if not isinstance(results, list):
        raise TmdbUnavailable("TMDB sent a search answer without results")
    title_key, original_key, date_key = (
        ("title", "original_title", "release_date")
        if kind == "movie"
        else ("name", "original_name", "first_air_date")
    )
    found = []
    for item in results:
        if not isinstance(item, dict):
            continue
        tmdb_id = item.get("id")
        title = _text(item.get(title_key))
        if not isinstance(tmdb_id, int) or tmdb_id <= 0 or title is None:
            continue
        when = _date(item.get(date_key))
        found.append(
            SearchResult(
                tmdb_id=tmdb_id,
                title=title[:500],
                original_title=(_text(item.get(original_key)) or "")[:500] or None,
                year=when.year if when else None,
                overview=(_text(item.get("overview")) or "")[:5000] or None,
                poster_path=_image_path(item.get("poster_path")),
            )
        )
        if len(found) == MAX_RESULTS:
            break
    return found


def parse_posters(data: Any) -> list[str]:
    """Poster paths from TMDB's /images answer that are eligible: in English
    or with no text. In TMDB's order, best first, at most MAX_RESULTS."""
    posters = data.get("posters") if isinstance(data, dict) else None
    paths: list[str] = []
    for poster in posters if isinstance(posters, list) else []:
        if not isinstance(poster, dict) or poster.get("iso_639_1") not in ("en", None):
            continue
        path = _image_path(poster.get("file_path"))
        if path and path not in paths:
            paths.append(path)
        if len(paths) == MAX_RESULTS:
            break
    return paths


_TRAILER_KEY = re.compile(r"^[A-Za-z0-9_-]{1,20}$")


def parse_trailer(data: Any) -> str | None:
    """The YouTube key of the newest official trailer in TMDB's /videos
    answer, or None."""
    results = data.get("results") if isinstance(data, dict) else None
    trailers = [
        video
        for video in (results if isinstance(results, list) else [])
        if isinstance(video, dict)
        and video.get("site") == "YouTube"
        and video.get("type") == "Trailer"
        and video.get("official") is True
        and isinstance(video.get("key"), str)
        and _TRAILER_KEY.match(video["key"])
    ]
    trailers.sort(key=lambda video: str(video.get("published_at") or ""), reverse=True)
    return trailers[0]["key"] if trailers else None


@dataclass(frozen=True)
class ImageConfig:
    """How to build an image address: base + size + path."""

    base_url: str = "https://image.tmdb.org/t/p/"
    poster_size: str = "w342"
    backdrop_size: str = "w780"
    # Home's hero spans a desktop screen, where w780 looks soft.
    hero_backdrop_size: str = "w1280"

    def poster_url(self, path: str | None) -> str | None:
        return f"{self.base_url}{self.poster_size}{path}" if path else None

    def backdrop_url(self, path: str | None) -> str | None:
        return f"{self.base_url}{self.backdrop_size}{path}" if path else None

    def hero_backdrop_url(self, path: str | None) -> str | None:
        return f"{self.base_url}{self.hero_backdrop_size}{path}" if path else None


DEFAULT_IMAGES = ImageConfig()


def _size(sizes: Any, wanted: str) -> str:
    """The wanted size if TMDB offers it, else the closest wider one, else
    the default's."""
    if not isinstance(sizes, list):
        return wanted
    offered = [
        s for s in sizes if isinstance(s, str) and s[:1] == "w" and s[1:].isdigit()
    ]
    if wanted in offered:
        return wanted
    width = int(wanted[1:])
    wider = sorted((int(s[1:]), s) for s in offered if int(s[1:]) >= width)
    return wider[0][1] if wider else wanted


def parse_image_config(data: Any) -> ImageConfig:
    """ImageConfig from TMDB's /configuration answer. Anything unexpected
    keeps the default, so a strange answer can't break image addresses."""
    images = data.get("images") if isinstance(data, dict) else None
    if not isinstance(images, dict):
        return DEFAULT_IMAGES
    base = images.get("secure_base_url")
    if not (
        isinstance(base, str)
        and base.startswith("https://image.tmdb.org/")
        and base.endswith("/")
    ):
        base = DEFAULT_IMAGES.base_url
    return ImageConfig(
        base_url=base,
        poster_size=_size(images.get("poster_sizes"), DEFAULT_IMAGES.poster_size),
        backdrop_size=_size(images.get("backdrop_sizes"), DEFAULT_IMAGES.backdrop_size),
        hero_backdrop_size=_size(
            images.get("backdrop_sizes"), DEFAULT_IMAGES.hero_backdrop_size
        ),
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
        data = self._get_json(f"/movie/{tmdb_id}", {"language": LANGUAGE}, tmdb_id)
        return parse_movie(data, tmdb_id)

    def series(self, tmdb_id: int) -> MovieDetails:
        if tmdb_id <= 0:
            raise ValueError("A TMDB ID is a positive number")
        data = self._get_json(f"/tv/{tmdb_id}", {"language": LANGUAGE}, tmdb_id, "tv")
        return parse_series(data, tmdb_id)

    def details(self, kind: str, tmdb_id: int) -> MovieDetails:
        """A movie's or a series' details."""
        return self.movie(tmdb_id) if kind == "movie" else self.series(tmdb_id)

    def search(
        self, kind: str, query: str, year: int | None = None
    ) -> list[SearchResult]:
        """TMDB's first page of results for a title. `kind` is movie or
        series. The year, if given, narrows the search."""
        path = "/search/movie" if kind == "movie" else "/search/tv"
        params: dict = {"query": query, "language": LANGUAGE, "include_adult": "false"}
        if year is not None:
            params["year" if kind == "movie" else "first_air_date_year"] = year
        return parse_search(self._get_json(path, params, None), kind)

    def posters(self, kind: str, tmdb_id: int) -> list[str]:
        prefix = "/movie" if kind == "movie" else "/tv"
        data = self._get_json(
            f"{prefix}/{tmdb_id}/images",
            {"include_image_language": "en,null"},
            tmdb_id,
            prefix[1:],
        )
        return parse_posters(data)

    def trailer(self, kind: str, tmdb_id: int) -> str | None:
        prefix = "/movie" if kind == "movie" else "/tv"
        data = self._get_json(
            f"{prefix}/{tmdb_id}/videos", {"language": LANGUAGE}, tmdb_id, prefix[1:]
        )
        return parse_trailer(data)

    def image_config(self) -> ImageConfig:
        return parse_image_config(self._get_json("/configuration", {}, None))

    def _get_json(
        self, path: str, params: dict, tmdb_id: int | None, what: str = "movie"
    ) -> Any:
        try:
            response = self._client.get(path, params=params)
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
            return data
        if status == 404:
            if tmdb_id is None:
                raise TmdbUnavailable("TMDB answered 404")
            name = "series" if what == "tv" else "movie"
            raise TmdbNotFound(f"TMDB has no {name} {tmdb_id}")
        if status == 401:
            raise TmdbRefused(
                "TMDB refused the token. Copy the API Read Access Token again"
            )
        if status == 429:
            raise TmdbUnavailable(
                "TMDB asked us to slow down", retry_after=_retry_after(response)
            )
        raise TmdbUnavailable(f"TMDB answered {status}")
