"""The TMDB client, with TMDB replaced by a mock transport. No network."""

from datetime import date

import httpx2
import pytest

from app.tmdb import (
    DEFAULT_IMAGES,
    TmdbClient,
    TmdbNotFound,
    TmdbRefused,
    TmdbUnavailable,
    parse_image_config,
    parse_movie,
    parse_series,
)

TOKEN = "eyJ-test-token-SECRET"

FIGHT_CLUB = {
    "id": 550,
    "title": "Fight Club",
    "original_title": "Fight Club",
    "overview": "A ticking-time-bomb insomniac...",
    "release_date": "1999-10-15",
    "runtime": 139,
    "genres": [{"id": 18, "name": "Drama"}, {"id": 53, "name": "Thriller"}],
    "poster_path": "/pB8BM7pdSp6B6Ih7QZ4DrQ3PmJK.jpg",
    "backdrop_path": "/hZkgoQYus5vegHoetLkCJzb17zJ.jpg",
    "adult": False,
    "vote_average": 8.438,
    "vote_count": 30195,
}


def client_answering(handler) -> tuple[TmdbClient, list[httpx2.Request]]:
    requests: list[httpx2.Request] = []

    def record(request: httpx2.Request) -> httpx2.Response:
        requests.append(request)
        return handler(request)

    return TmdbClient(TOKEN, transport=httpx2.MockTransport(record)), requests


def test_a_movie_is_fetched_with_the_token_in_the_header_only():
    client, requests = client_answering(
        lambda request: httpx2.Response(200, json=FIGHT_CLUB)
    )

    movie = client.movie(550)

    assert movie.title == "Fight Club"
    assert movie.year == 1999
    assert movie.release_date == date(1999, 10, 15)
    assert movie.runtime_minutes == 139
    assert movie.genres == ("Drama", "Thriller")
    assert movie.poster_path == "/pB8BM7pdSp6B6Ih7QZ4DrQ3PmJK.jpg"
    assert movie.rating == 8.4
    assert movie.vote_count == 30195
    (request,) = requests
    assert str(request.url) == "https://api.themoviedb.org/3/movie/550?language=en-US"
    assert request.headers["Authorization"] == f"Bearer {TOKEN}"
    assert TOKEN not in str(request.url)


@pytest.mark.parametrize(
    ("status", "error", "text"),
    [
        (404, TmdbNotFound, "no movie 550"),
        (401, TmdbRefused, "refused the token"),
        (429, TmdbUnavailable, "slow down"),
        (500, TmdbUnavailable, "answered 500"),
        (503, TmdbUnavailable, "answered 503"),
        (302, TmdbUnavailable, "answered 302"),
    ],
)
def test_failures_are_typed_and_never_quote_the_token(status, error, text):
    body = {"status_message": f"echo {TOKEN}"}
    client, _ = client_answering(lambda request: httpx2.Response(status, json=body))

    with pytest.raises(error) as raised:
        client.movie(550)

    assert text in str(raised.value)
    assert TOKEN not in str(raised.value)
    assert raised.value.__cause__ is None


def test_retry_after_is_kept_on_429():
    client, _ = client_answering(
        lambda request: httpx2.Response(429, headers={"Retry-After": "3"})
    )

    with pytest.raises(TmdbUnavailable) as raised:
        client.movie(550)

    assert raised.value.retry_after == 3.0


def test_a_timeout_and_a_connection_failure_are_unavailable():
    def timeout(request):
        raise httpx2.ReadTimeout("slow", request=request)

    def refused(request):
        raise httpx2.ConnectError(f"no route {TOKEN}", request=request)

    for handler, text in ((timeout, "in time"), (refused, "ConnectError")):
        client, _ = client_answering(handler)
        with pytest.raises(TmdbUnavailable) as raised:
            client.movie(550)
        assert text in str(raised.value)
        assert TOKEN not in str(raised.value)


def test_an_answer_that_isnt_json_or_is_for_another_movie_is_refused():
    for response in (
        httpx2.Response(200, text="<html>"),
        httpx2.Response(200, json={**FIGHT_CLUB, "id": 551}),
        httpx2.Response(200, json=[FIGHT_CLUB]),
        httpx2.Response(200, json={**FIGHT_CLUB, "title": "  "}),
    ):
        client, _ = client_answering(lambda request, r=response: r)
        with pytest.raises(TmdbUnavailable):
            client.movie(550)


def test_missing_and_strange_fields_become_none():
    movie = parse_movie(
        {
            "id": 7,
            "title": " A title ",
            "original_title": "",
            "overview": None,
            "release_date": "",
            "runtime": 0,
            "genres": [{"name": "Drama"}, {"name": ""}, "Comedy", {"id": 1}],
            "poster_path": "https://evil.example/x.jpg",
            "backdrop_path": "/../x.jpg",
        },
        7,
    )

    assert movie.title == "A title"
    assert movie.original_title is None
    assert movie.overview is None
    assert movie.release_date is None
    assert movie.year is None
    assert movie.runtime_minutes is None
    assert movie.genres == ("Drama",)
    assert movie.poster_path is None
    assert movie.backdrop_path is None


def test_bad_ids_and_empty_tokens_are_refused_before_any_request():
    client, requests = client_answering(lambda request: httpx2.Response(200))
    with pytest.raises(ValueError):
        client.movie(0)
    assert requests == []
    with pytest.raises(ValueError):
        TmdbClient("  ")


# --- Image settings ----------------------------------------------------------


def test_image_settings_are_read_from_tmdb():
    client, requests = client_answering(
        lambda request: httpx2.Response(
            200,
            json={
                "images": {
                    "secure_base_url": "https://image.tmdb.org/t/p/",
                    "poster_sizes": ["w92", "w185", "w500", "original"],
                    "backdrop_sizes": ["w300", "w780", "original"],
                }
            },
        )
    )

    images = client.image_config()

    assert str(requests[0].url) == "https://api.themoviedb.org/3/configuration"
    # w342 isn't offered, so the next wider size is used.
    assert images.poster_url("/a.jpg") == "https://image.tmdb.org/t/p/w500/a.jpg"
    assert images.backdrop_url("/b.jpg") == "https://image.tmdb.org/t/p/w780/b.jpg"


@pytest.mark.parametrize(
    "answer",
    [
        [],
        {"images": None},
        {"images": {"secure_base_url": "http://image.tmdb.org/t/p/"}},
        {"images": {"secure_base_url": "https://evil.example/t/p/"}},
        {"images": {"poster_sizes": "w342", "backdrop_sizes": [1, None]}},
    ],
)
def test_strange_image_settings_keep_the_defaults(answer):
    images = parse_image_config(answer)

    assert images == DEFAULT_IMAGES
    assert images.poster_url("/a.jpg") == "https://image.tmdb.org/t/p/w342/a.jpg"
    assert images.poster_url(None) is None


def test_image_settings_failures_are_unavailable():
    client, _ = client_answering(lambda request: httpx2.Response(404))

    with pytest.raises(TmdbUnavailable):
        client.image_config()


# --- Ratings -----------------------------------------------------------------


def _with_votes(average, count) -> dict:
    return {**FIGHT_CLUB, "vote_average": average, "vote_count": count}


@pytest.mark.parametrize(
    ("average", "count", "rating", "votes"),
    [
        (7.25, 12, 7.2, 12),  # Python rounds half to even: 7.25 -> 7.2.
        (7.26, 12, 7.3, 12),
        (10, 3, 10.0, 3),
        (0.5, 1, 0.5, 1),
    ],
)
def test_the_rating_is_kept_to_one_decimal(average, count, rating, votes):
    movie = parse_movie(_with_votes(average, count), 550)

    assert movie.rating == rating
    assert movie.vote_count == votes


@pytest.mark.parametrize(
    ("average", "count"),
    [
        # TMDB's answer for a title nobody has rated: not a score of 0.
        (0.0, 0),
        (7.5, 0),
        (None, 10),
        (7.5, None),
        ("7.5", 10),
        (7.5, "10"),
        (True, 10),
        (7.5, True),
        (-1, 10),
        (10.1, 10),
        (float("nan"), 10),
        (7.5, -4),
        (7.5, 2.5),
    ],
)
def test_no_votes_or_strange_values_give_no_rating(average, count):
    movie = parse_movie(_with_votes(average, count), 550)

    assert movie.rating is None
    assert movie.vote_count is None


def test_a_movie_without_rating_fields_has_no_rating():
    data = {k: v for k, v in FIGHT_CLUB.items() if not k.startswith("vote_")}

    movie = parse_movie(data, 550)

    assert movie.rating is None
    assert movie.vote_count is None


def test_a_series_has_a_rating_too():
    series = parse_series(
        {"id": 1396, "name": "Breaking Bad", "vote_average": 8.9, "vote_count": 1500},
        1396,
    )

    assert series.rating == 8.9
    assert series.vote_count == 1500
