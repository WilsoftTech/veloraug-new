"""The rating backfill script: pacing without a database, and what it picks
and saves on a real Postgres. TMDB is replaced by a fake."""

import subprocess
import sys
from dataclasses import replace
from datetime import timedelta

import psycopg
import pytest

from app.catalogue import REFRESH_AFTER
from app.tmdb import TmdbNotFound, TmdbRefused, TmdbUnavailable
from scripts.backfill_ratings import (
    MAX_TRIES,
    MAX_WAIT_SECONDS,
    Pacer,
    backfill,
    pending,
)
from tests.db_support import API_DIR, add_movie, delete_editions, needs_database
from tests.test_catalogue import details, new_id


class FakeTime:
    """A clock that only moves when something sleeps."""

    def __init__(self) -> None:
        self.now = 100.0
        self.sleeps: list[float] = []

    def clock(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(round(seconds, 6))
        self.now += seconds


def pacer(rate: float = 4.0) -> tuple[Pacer, FakeTime]:
    time = FakeTime()
    return Pacer(rate, clock=time.clock, sleep=time.sleep), time


# --- Needs no database -------------------------------------------------------


def test_the_script_explains_itself_without_a_database():
    result = subprocess.run(
        [sys.executable, "scripts/backfill_ratings.py", "--help"],
        cwd=API_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )

    assert result.returncode == 0, result.stderr
    assert "--refresh" in result.stdout
    assert "--dry-run" in result.stdout


def test_requests_are_spaced_by_the_rate():
    pace, time = pacer(4.0)

    for _ in range(3):
        pace.wait()

    # The first goes at once; the others wait a quarter second each.
    assert time.sleeps == [0.25, 0.25]


def test_time_already_spent_counts_towards_the_gap():
    pace, time = pacer(2.0)
    pace.wait()
    time.now += 0.2

    pace.wait()

    assert time.sleeps == [0.3]


def test_a_pause_tmdb_asked_for_holds_back_the_next_request():
    pace, time = pacer(4.0)
    pace.wait()
    pace.hold(5)

    pace.wait()
    pace.wait()

    # The pause, then the usual gap after it.
    assert time.sleeps == [5, 0.25]


@pytest.mark.parametrize("rate", [0, -1, 21])
def test_a_strange_rate_is_refused(rate):
    with pytest.raises(ValueError, match="rate"):
        Pacer(rate)


# --- On a database -----------------------------------------------------------


@pytest.fixture
def owner(owner_url, app_url):
    with psycopg.connect(owner_url) as conn:
        delete_editions(conn)
        conn.commit()
        yield conn
        conn.rollback()
        delete_editions(conn)
        conn.commit()


def asked(owner, tmdb_id, days_ago: float | None) -> None:
    """Marks a source's rating as last asked for days_ago, or never."""
    owner.execute(
        "update public.sources set rating_updated_at = now() - %s where tmdb_id = %s",
        (None if days_ago is None else timedelta(days=days_ago), tmdb_id),
    )


def rating_of(owner, tmdb_id):
    return owner.execute(
        "select tmdb_rating::float8, tmdb_vote_count from public.sources "
        "where tmdb_id = %s",
        (tmdb_id,),
    ).fetchone()


@needs_database
def test_never_asked_sources_are_picked_whatever_the_copys_age(owner):
    never, recent, old = new_id(), new_id(), new_id()
    for tmdb_id in (never, recent, old):
        add_movie(owner, details(tmdb_id))
    asked(owner, recent, 1)
    asked(owner, old, REFRESH_AFTER.days + 1)

    assert pending(owner, refresh=False) == [("movie", never)]
    # With --refresh, old ratings too, never-asked first. Recent ones never.
    assert pending(owner, refresh=True) == [("movie", never), ("movie", old)]
    assert pending(owner, refresh=True, limit=1) == [("movie", never)]


@needs_database
def test_typed_in_details_are_never_picked(owner):
    owner.execute(
        "insert into public.sources (kind, title, details_from) "
        "values ('movie', 'Typed in', 'manual')"
    )

    assert pending(owner, refresh=True) == []


@needs_database
def test_backfill_saves_each_rating_and_commits_as_it_goes(owner, owner_url):
    rated, unrated = new_id(), new_id()
    add_movie(owner, details(rated))
    add_movie(owner, details(unrated))
    owner.commit()
    pace, time = pacer()
    lines: list[str] = []

    def fetch(kind, tmdb_id):
        if tmdb_id == rated:
            return replace(details(tmdb_id), rating=7.4, vote_count=321)
        return details(tmdb_id)

    result = backfill(
        owner,
        [("movie", rated), ("movie", unrated)],
        fetch,
        pace,
        report=lines.append,
    )

    assert (result.saved, result.rated, result.failed) == (2, 1, [])
    assert time.sleeps == [0.25]
    assert lines == [
        f"movie {rated}: 7.4 from 321 votes",
        f"movie {unrated}: no rating on TMDB",
    ]
    # Committed: another connection sees both.
    with psycopg.connect(owner_url) as other:
        assert rating_of(other, rated) == (7.4, 321)
        assert other.execute(
            "select count(*) from public.sources "
            "where tmdb_id in (%s, %s) and rating_updated_at is not null",
            (rated, unrated),
        ).fetchone() == (2,)
    assert pending(owner, refresh=False) == []


@needs_database
def test_backfill_waits_when_tmdb_asks_then_tries_again(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))
    pace, time = pacer()
    answers = [TmdbUnavailable("TMDB asked us to slow down", retry_after=5)]

    def fetch(kind, tmdb_id):
        if answers:
            raise answers.pop()
        return replace(details(tmdb_id), rating=6.0, vote_count=50)

    result = backfill(owner, [("movie", tmdb_id)], fetch, pace, report=lambda _: None)

    assert result.saved == 1
    assert 5 in time.sleeps
    assert rating_of(owner, tmdb_id) == (6.0, 50)


@needs_database
def test_a_long_retry_after_is_capped(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))
    pace, time = pacer()

    def fetch(kind, tmdb_id):
        raise TmdbUnavailable("TMDB asked us to slow down", retry_after=3600)

    result = backfill(owner, [("movie", tmdb_id)], fetch, pace, report=lambda _: None)

    assert time.sleeps.count(MAX_WAIT_SECONDS) == MAX_TRIES - 1
    assert result.saved == 0
    assert result.failed == [f"movie {tmdb_id}: TMDB asked us to slow down"]


@needs_database
def test_one_failure_doesnt_stop_the_others(owner):
    missing, fine = new_id(), new_id()
    add_movie(owner, details(missing))
    add_movie(owner, details(fine))
    pace, _ = pacer()

    def fetch(kind, tmdb_id):
        if tmdb_id == missing:
            raise TmdbNotFound(f"TMDB has no movie {tmdb_id}")
        return details(tmdb_id)

    result = backfill(
        owner,
        [("movie", missing), ("movie", fine)],
        fetch,
        pace,
        report=lambda _: None,
    )

    assert result.saved == 1
    assert result.failed == [f"movie {missing}: TMDB has no movie {missing}"]


@needs_database
def test_a_refused_token_stops_the_backfill(owner):
    first, second = new_id(), new_id()
    add_movie(owner, details(first))
    add_movie(owner, details(second))
    pace, _ = pacer()
    fetched: list[int] = []

    def fetch(kind, tmdb_id):
        fetched.append(tmdb_id)
        raise TmdbRefused("TMDB refused the token")

    with pytest.raises(TmdbRefused):
        backfill(
            owner,
            [("movie", first), ("movie", second)],
            fetch,
            pace,
            report=lambda _: None,
        )

    assert fetched == [first]


@needs_database
def test_a_pause_asked_for_on_the_last_try_holds_back_the_next_title(owner):
    first, second = new_id(), new_id()
    add_movie(owner, details(first))
    add_movie(owner, details(second))
    pace, time = pacer()

    def fetch(kind, tmdb_id):
        if tmdb_id == first:
            raise TmdbUnavailable("TMDB asked us to slow down", retry_after=5)
        return details(tmdb_id)

    result = backfill(
        owner,
        [("movie", first), ("movie", second)],
        fetch,
        pace,
        report=lambda _: None,
    )

    # A 5-second pause before each of the first title's retries, and one
    # more before the second title, though the first had no tries left.
    assert time.sleeps == [5] * MAX_TRIES
    assert result.saved == 1
    assert result.failed == [f"movie {first}: TMDB asked us to slow down"]
