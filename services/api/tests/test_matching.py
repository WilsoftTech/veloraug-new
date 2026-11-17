"""Matching submitted titles to TMDB, suggesting VJ credits, and parsing
TMDB's search, poster and video answers. No database or network."""

import uuid

import httpx2
import pytest

from app.matching import KnownVj, clean_title, clear_match, normalize, suggest_credit
from app.tmdb import (
    SearchResult,
    TmdbClient,
    TmdbNotFound,
    TmdbUnavailable,
    parse_posters,
    parse_search,
    parse_series,
    parse_trailer,
)


def result(tmdb_id, title, year=None, original=None):
    return SearchResult(tmdb_id, title, original, year, None, None)


# --- Cleaning titles ---------------------------------------------------------


@pytest.mark.parametrize(
    ("submitted", "expected"),
    [
        ("Fast X", ("Fast X", None)),
        ("Fast.X.2023.VJ.Junior.Luganda.1080p.mp4", ("Fast X", 2023)),
        ("Fast X (2023) - VJ Ice P [HD] Translated", ("Fast X", 2023)),
        ("The Matrix Luganda Full Movie", ("The Matrix", None)),
        ("vj emmy - Kabaka s01 x265", ("Kabaka s01", None)),
        ("1917", ("1917", None)),
        ("VJ Junior", ("VJ Junior", None)),
    ],
)
def test_titles_lose_vj_names_and_file_words(submitted, expected):
    assert clean_title(submitted, ["VJ Ice P", "VJ Junior"]) == expected


def test_titles_compare_without_case_accents_punctuation_or_the():
    assert normalize("The Matrix") == normalize("matrix")
    assert normalize("Amélie!") == normalize("amelie")
    assert normalize("Spider-Man: No Way Home") == "spider man no way home"


# --- A clear match -----------------------------------------------------------


def test_exactly_one_same_title_is_clear():
    results = [result(1, "Fast X", 2023), result(2, "Fast Five", 2011)]

    assert clear_match(results, "fast x", None).tmdb_id == 1


def test_two_same_titles_need_the_year_or_the_admin():
    results = [result(1, "The Lion King", 1994), result(2, "The Lion King", 2019)]

    assert clear_match(results, "The Lion King", None) is None
    assert clear_match(results, "The Lion King", 2019).tmdb_id == 2
    assert clear_match(results, "The Lion King", 2005) is None


def test_the_original_title_counts_too():
    results = [result(7, "Crouching Tiger", 2000, original="Wo hu cang long")]

    assert clear_match(results, "wo hu cang long", 2000).tmdb_id == 7


def test_a_similar_title_is_not_clear():
    assert clear_match([result(1, "Fast X Part 2")], "Fast X", None) is None
    assert clear_match([], "Fast X", None) is None


# --- VJ credit suggestions ---------------------------------------------------

JUNIOR = KnownVj(uuid.UUID(int=1), "VJ Junior")
ICE_P = KnownVj(uuid.UUID(int=2), "VJ Ice P", ("icep",))
EMMY = KnownVj(uuid.UUID(int=3), "VJ Emmy")


def test_a_known_vj_in_the_file_name_is_suggested():
    found = suggest_credit(
        [("file name", "Fast.X.2023.VJ.Junior.Luganda.mp4")], [JUNIOR, ICE_P]
    )

    assert [(s.vj_id, s.name, s.found_in) for s in found] == [
        (JUNIOR.id, "VJ Junior", "file name")
    ]


def test_spellings_and_two_word_names_match():
    found = suggest_credit(
        [("file tags", "artist: VJ ICEP"), ("file name", "Kabaka_vj-ice-p_ep2.mkv")],
        [JUNIOR, ICE_P],
    )

    assert [s.vj_id for s in found] == [ICE_P.id]


def test_an_unknown_vj_is_offered_as_a_new_one():
    found = suggest_credit([("file name", "Fast X VJ Kevo.mp4")], [JUNIOR])

    assert [(s.vj_id, s.name) for s in found] == [(None, "VJ Kevo")]


def test_known_vjs_come_first_and_each_once():
    found = suggest_credit(
        [
            ("file name", "VJ Kevo VJ Emmy.mp4"),
            ("file tags", "comment: Translated by VJ Emmy"),
            ("submitted title", "Fast X VJ Emmy"),
        ],
        [EMMY],
    )

    assert [(s.vj_id, s.found_in) for s in found] == [
        (EMMY.id, "file name"),
        (None, "file name"),
    ]


def test_a_spelling_without_vj_is_found_in_tags():
    found = suggest_credit([("file tags", "artist: IceP Uganda")], [ICE_P])

    assert [s.vj_id for s in found] == [ICE_P.id]


def test_nothing_is_suggested_without_a_name():
    assert suggest_credit([("file name", None), ("file tags", "x264")], [JUNIOR]) == []


# --- TMDB's answers ----------------------------------------------------------


def test_search_results_keep_tmdbs_order_and_skip_bad_entries():
    data = {
        "results": [
            {
                "id": 2,
                "title": "Fast X",
                "release_date": "2023-05-17",
                "poster_path": "/a.jpg",
            },
            {"id": "x", "title": "Bad"},
            {"id": 3},
            {"id": 4, "title": "Fast Five", "release_date": "", "poster_path": "../x"},
        ]
    }

    found = parse_search(data, "movie")

    assert [(r.tmdb_id, r.title, r.year, r.poster_path) for r in found] == [
        (2, "Fast X", 2023, "/a.jpg"),
        (4, "Fast Five", None, None),
    ]


def test_series_search_and_details_use_names_and_air_dates():
    data = {"results": [{"id": 9, "name": "Kabaka", "first_air_date": "2021-03-01"}]}

    assert [(r.title, r.year) for r in parse_search(data, "series")] == [
        ("Kabaka", 2021)
    ]
    details = parse_series(
        {
            "id": 9,
            "name": "Kabaka",
            "original_name": "Kabaka",
            "first_air_date": "2021-03-01",
            "episode_run_time": [42],
            "genres": [{"name": "Drama"}],
            "poster_path": "/k.jpg",
        },
        9,
    )
    assert (details.title, details.year, details.runtime_minutes) == (
        "Kabaka",
        2021,
        42,
    )
    with pytest.raises(TmdbUnavailable):
        parse_series({"id": 8, "name": "Other"}, 9)


def test_only_english_or_textless_posters_are_offered():
    data = {
        "posters": [
            {"file_path": "/en.jpg", "iso_639_1": "en"},
            {"file_path": "/fr.jpg", "iso_639_1": "fr"},
            {"file_path": "/none.jpg", "iso_639_1": None},
            {"file_path": "/en.jpg", "iso_639_1": "en"},
            {"file_path": "bad", "iso_639_1": "en"},
        ]
    }

    assert parse_posters(data) == ["/en.jpg", "/none.jpg"]


def test_the_newest_official_youtube_trailer_is_chosen():
    data = {
        "results": [
            {
                "site": "YouTube",
                "type": "Trailer",
                "official": True,
                "key": "old",
                "published_at": "2023-01-01",
            },
            {
                "site": "YouTube",
                "type": "Trailer",
                "official": True,
                "key": "new",
                "published_at": "2023-04-01",
            },
            {
                "site": "YouTube",
                "type": "Teaser",
                "official": True,
                "key": "teaser",
                "published_at": "2023-06-01",
            },
            {
                "site": "Vimeo",
                "type": "Trailer",
                "official": True,
                "key": "vimeo",
                "published_at": "2023-07-01",
            },
            {
                "site": "YouTube",
                "type": "Trailer",
                "official": False,
                "key": "fan",
                "published_at": "2023-08-01",
            },
            {
                "site": "YouTube",
                "type": "Trailer",
                "official": True,
                "key": "bad key!",
                "published_at": "2023-09-01",
            },
        ]
    }

    assert parse_trailer(data) == "new"
    assert parse_trailer({"results": []}) is None


def test_the_client_searches_with_the_year_and_names_series():
    seen = []

    def handle(request):
        seen.append((request.url.path, dict(request.url.params)))
        if request.url.path.endswith("/tv/5"):
            return httpx2.Response(404)
        return httpx2.Response(200, json={"results": []})

    with TmdbClient("token", transport=httpx2.MockTransport(handle)) as client:
        client.search("movie", "Fast X", 2023)
        client.search("series", "Kabaka", 2021)
        with pytest.raises(TmdbNotFound, match="no series 5"):
            client.series(5)

    assert seen[0] == (
        "/3/search/movie",
        {
            "query": "Fast X",
            "language": "en-US",
            "include_adult": "false",
            "year": "2023",
        },
    )
    assert seen[1][0] == "/3/search/tv"
    assert seen[1][1]["first_air_date_year"] == "2021"
