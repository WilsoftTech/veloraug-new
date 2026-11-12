"""The owner's catalogue script and migration 0002, on a real Postgres.

TMDB is replaced by a fake. Skipped without a local test Postgres: see
tests/db_support.py.
"""

import subprocess
import sys
import uuid
from datetime import UTC, date, datetime, timedelta

import psycopg
import pytest

from app.tmdb import MovieDetails, TmdbNotFound, TmdbRefused, TmdbUnavailable
from scripts import catalogue
from scripts.catalogue import (
    DELETE_AFTER,
    REFRESH_AFTER,
    CatalogueError,
    Movie,
    add_movie,
    describe_movie,
    find_movie,
    list_movies,
    purge_tmdb,
    refresh,
    set_published,
)
from scripts.check_database import check_catalogue
from tests.db_support import API_DIR, needs_database, owner_query


def details(tmdb_id: int, title: str = "A movie") -> MovieDetails:
    return MovieDetails(
        tmdb_id=tmdb_id,
        title=title,
        original_title=title,
        overview="An overview.",
        release_date=date(2024, 5, 1),
        runtime_minutes=101,
        genres=("Drama", "Comedy"),
        poster_path="/poster.jpg",
        backdrop_path="/backdrop.jpg",
    )


# Each test works in its own transaction, rolled back at the end, with TMDB
# IDs no other test uses.
@pytest.fixture
def owner(owner_url, app_url):
    with psycopg.connect(owner_url) as conn:
        yield conn
        conn.rollback()


def new_id() -> int:
    return 1_000_000 + uuid.uuid4().int % 1_000_000_000


def as_app(app_url, query, params=()):
    with psycopg.connect(app_url) as conn:
        return conn.execute(query, params).fetchall()


# --- Needs no database -------------------------------------------------------


def test_the_script_explains_itself_without_a_database():
    result = subprocess.run(
        [sys.executable, "scripts/catalogue.py", "--help"],
        cwd=API_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )

    assert result.returncode == 0
    for command in ("add", "publish", "unpublish", "list", "refresh", "purge-tmdb"):
        assert command in result.stdout


def test_add_without_a_token_stops_before_asking_for_the_database(monkeypatch, capsys):
    # conftest.py has already cleared the environment and hidden .env.
    def no_database():
        raise AssertionError("asked for the database")

    monkeypatch.setattr(catalogue, "connect", no_database)
    monkeypatch.setattr(sys, "argv", ["catalogue.py", "add", "550"])

    assert catalogue.main() == 1
    assert "VELORAUG_TMDB_READ_ACCESS_TOKEN isn't set" in capsys.readouterr().err


@pytest.mark.parametrize(
    ("answer", "expected"),
    [("yes", True), (" YES ", True), ("﻿yes", True), ("y", False), ("", False)],
)
def test_only_the_whole_word_counts_as_yes(monkeypatch, answer, expected):
    monkeypatch.setattr("builtins.input", lambda prompt: answer)

    assert catalogue.typed("Add it?", "yes") is expected


def test_no_input_at_all_counts_as_no(monkeypatch):
    def closed(prompt):
        raise EOFError

    monkeypatch.setattr("builtins.input", closed)

    assert catalogue.typed("Add it?", "yes") is False


def test_connection_errors_never_show_the_password():
    url = "postgresql://owner:S3cret%2Fpw@ep-x.neon.tech/neondb?bogus=1"
    error = psycopg.ProgrammingError(
        'invalid URI query parameter: "bogus"\nnear S3cret%2Fpw and S3cret/pw'
    )

    message = catalogue.safe_message(error, url)

    assert "S3cret" not in message
    assert message == "near <hidden> and <hidden>"


def test_a_failure_after_connecting_is_explained_without_its_password(
    monkeypatch, capsys
):
    url = "postgresql://owner:S3cret%2Fpw@ep-x.neon.tech/neondb"
    monkeypatch.setattr(catalogue, "_url", url)

    def fails(args):
        raise psycopg.OperationalError(
            "server closed the connection unexpectedly\n"
            "\tThis probably means the server terminated abnormally S3cret/pw"
        )

    monkeypatch.setattr(catalogue, "run", fails)
    monkeypatch.setattr(sys, "argv", ["catalogue.py", "unpublish", "550"])

    assert catalogue.main() == 1

    err = capsys.readouterr().err
    assert "S3cret" not in err
    assert err.strip() == (
        "Failed, nothing saved. OperationalError: server closed the connection "
        "unexpectedly This probably means the server terminated abnormally "
        "<hidden>"
    )


def test_a_malformed_string_is_explained_without_its_password(monkeypatch, capsys):
    monkeypatch.setenv(
        "VELORAUG_MIGRATION_DATABASE_URL",
        "postgresql://owner:S3cret@127.0.0.1:1/db?not_an_option=1",
    )
    monkeypatch.setattr(sys, "argv", ["catalogue.py", "list"])

    assert catalogue.main() == 1
    err = capsys.readouterr().err
    assert "Couldn't connect" in err
    assert "not_an_option" in err
    assert "S3cret" not in err


def test_counts_read_naturally():
    assert catalogue.plural(1, "movie", "movies") == "1 movie"
    assert catalogue.plural(0, "movie", "movies") == "0 movies"


def test_a_movie_is_described_on_one_line():
    movie_id = uuid.uuid4()
    now = datetime(2026, 11, 10, tzinfo=UTC)
    line = describe_movie(
        Movie(movie_id, 550, True, "Fight Club", 1999, now - timedelta(days=3)), now
    )

    assert line == (
        f"Fight Club (1999)  TMDB 550  published  fetched 3 days ago  id {movie_id}"
    )


# --- On the test database ----------------------------------------------------


@needs_database
def test_the_api_role_sees_published_movies_only(owner, app_url):
    hidden, shown = new_id(), new_id()
    add_movie(owner, details(hidden, "Hidden"))
    add_movie(owner, details(shown, "Shown"))
    set_published(owner, str(shown), True)
    owner.commit()
    try:
        seen = as_app(
            app_url,
            "select m.tmdb_id, d.title from public.movies m "
            "join public.tmdb_movie_details d using (tmdb_id) "
            "where m.tmdb_id in (%s, %s)",
            (hidden, shown),
        )
        assert seen == [(shown, "Shown")]
        assert as_app(
            app_url,
            "select count(*) from public.tmdb_movie_details where tmdb_id = %s",
            (hidden,),
        ) == [(0,)]
    finally:
        owner.execute(
            "delete from public.movies where tmdb_id in (%s, %s)", (hidden, shown)
        )
        owner.commit()


@needs_database
def test_every_catalogue_check_passes_with_hidden_and_published_movies(owner, app_url):
    hidden, shown = new_id(), new_id()
    add_movie(owner, details(hidden))
    add_movie(owner, details(shown))
    set_published(owner, str(shown), True)
    owner.commit()
    try:
        with psycopg.connect(app_url, autocommit=True) as conn:
            results = check_catalogue(conn)
        assert [r.name for r in results if not r.passed] == []
        assert len(results) == 5
    finally:
        owner.execute(
            "delete from public.movies where tmdb_id in (%s, %s)", (hidden, shown)
        )
        owner.commit()


@needs_database
def test_the_api_role_can_refresh_a_published_copy_but_not_a_hidden_one(owner, app_url):
    hidden, shown = new_id(), new_id()
    add_movie(owner, details(hidden))
    add_movie(owner, details(shown))
    set_published(owner, str(shown), True)
    owner.commit()
    try:
        with psycopg.connect(app_url) as conn:
            changed = conn.execute(
                "update public.tmdb_movie_details set title = 'New' "
                "where tmdb_id in (%s, %s)",
                (hidden, shown),
            ).rowcount
            conn.rollback()
        assert changed == 1
    finally:
        owner.execute(
            "delete from public.movies where tmdb_id in (%s, %s)", (hidden, shown)
        )
        owner.commit()


@needs_database
def test_add_publish_and_unpublish(owner):
    tmdb_id = new_id()

    movie_id = add_movie(owner, details(tmdb_id, "Mine"))
    movie = find_movie(owner, str(tmdb_id))
    assert (movie.id, movie.published, movie.title, movie.year) == (
        movie_id,
        False,
        "Mine",
        2024,
    )

    published = set_published(owner, str(movie_id), True)
    assert published.published is True
    first = owner.execute(
        "select published_at from public.movies where id = %s", (movie_id,)
    ).fetchone()[0]
    assert first is not None
    # Publishing again keeps the first date.
    set_published(owner, str(tmdb_id), True)
    assert (
        owner.execute(
            "select published_at from public.movies where id = %s", (movie_id,)
        ).fetchone()[0]
        == first
    )

    hidden = set_published(owner, str(tmdb_id), False)
    assert hidden.published is False
    assert owner.execute(
        "select published_at from public.movies where id = %s", (movie_id,)
    ).fetchone() == (None,)


@needs_database
def test_mistakes_are_explained(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))

    with pytest.raises(CatalogueError, match="already added"):
        add_movie(owner, details(tmdb_id))
    with pytest.raises(CatalogueError, match="No movie"):
        set_published(owner, str(new_id()), True)
    with pytest.raises(CatalogueError, match="isn't a TMDB ID"):
        find_movie(owner, "fight-club")
    with pytest.raises(CatalogueError, match="isn't a TMDB ID"):
        find_movie(owner, "-5")


@needs_database
def test_a_movie_without_details_cant_be_published(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))
    owner.execute(
        "delete from public.tmdb_movie_details where tmdb_id = %s", (tmdb_id,)
    )

    with pytest.raises(CatalogueError, match="no details"):
        set_published(owner, str(tmdb_id), True)


@needs_database
def test_published_and_published_at_always_agree(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))

    with pytest.raises(psycopg.errors.CheckViolation):
        owner.execute(
            "update public.movies set published = true where tmdb_id = %s", (tmdb_id,)
        )


@needs_database
def test_list_shows_published_first(owner):
    first, second = new_id(), new_id()
    add_movie(owner, details(first, "Hidden one"))
    add_movie(owner, details(second, "Published one"))
    set_published(owner, str(second), True)

    titles = [m.title for m in list_movies(owner) if m.tmdb_id in (first, second)]

    assert titles == ["Published one", "Hidden one"]


def age(owner, tmdb_id, days):
    owner.execute(
        "update public.tmdb_movie_details set fetched_at = now() - %s "
        "where tmdb_id = %s",
        (timedelta(days=days), tmdb_id),
    )


def fetched_at(owner, tmdb_id):
    row = owner.execute(
        "select fetched_at from public.tmdb_movie_details where tmdb_id = %s",
        (tmdb_id,),
    ).fetchone()
    return row[0] if row else None


@needs_database
def test_refresh_fetches_only_old_copies(owner):
    # Other tests' movies are rolled back, but committed ones from a failed
    # run could remain. Only these three are asserted on.
    fresh, old, missing = new_id(), new_id(), new_id()
    for tmdb_id in (fresh, old, missing):
        add_movie(owner, details(tmdb_id))
    age(owner, fresh, 1)
    age(owner, old, REFRESH_AFTER.days + 1)
    owner.execute(
        "delete from public.tmdb_movie_details where tmdb_id = %s", (missing,)
    )
    fetched: list[int] = []

    def fetch(tmdb_id):
        fetched.append(tmdb_id)
        return details(tmdb_id, f"New {tmdb_id}")

    refresh(owner, fetch)

    assert fresh not in fetched
    assert old in fetched and missing in fetched
    assert find_movie(owner, str(old)).title == f"New {old}"
    assert find_movie(owner, str(missing)).title == f"New {missing}"
    assert find_movie(owner, str(fresh)).title == "A movie"


@needs_database
def test_a_failed_refresh_keeps_a_copy_until_180_days_then_deletes_it(owner):
    young, expired = new_id(), new_id()
    add_movie(owner, details(young))
    add_movie(owner, details(expired))
    age(owner, young, 30)
    age(owner, expired, DELETE_AFTER.days)

    def fetch(tmdb_id):
        if tmdb_id == young:
            raise TmdbUnavailable("TMDB answered 503")
        if tmdb_id == expired:
            raise TmdbNotFound(f"TMDB has no movie {tmdb_id}")
        return details(tmdb_id)

    result = refresh(owner, fetch)

    assert fetched_at(owner, young) is not None
    assert fetched_at(owner, expired) is None
    assert f"{young}: TMDB answered 503" in result.failed
    assert f"{expired}: TMDB has no movie {expired}" in result.failed
    assert result.deleted >= 1


@needs_database
def test_a_refused_token_stops_the_refresh(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))
    age(owner, tmdb_id, 30)

    def fetch(tmdb_id):
        raise TmdbRefused("TMDB refused the token")

    with pytest.raises(TmdbRefused):
        refresh(owner, fetch)


@needs_database
def test_purge_deletes_every_copy_and_hides_every_movie(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))
    set_published(owner, str(tmdb_id), True)

    purge_tmdb(owner)

    assert (
        owner.execute("select count(*) from public.tmdb_movie_details").fetchone()[0]
        == 0
    )
    assert owner.execute(
        "select count(*) from public.movies where published"
    ).fetchone() == (0,)
    assert find_movie(owner, str(tmdb_id)).title is None


@needs_database
def test_removing_a_movie_removes_its_copy(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))

    owner.execute("delete from public.movies where tmdb_id = %s", (tmdb_id,))

    assert fetched_at(owner, tmdb_id) is None


@needs_database
def test_the_owner_sees_the_migration(owner_url, app_url):
    assert owner_query(
        owner_url,
        "select to_regclass('public.movies') is not null, "
        "to_regclass('public.tmdb_movie_details') is not null",
    ) == [(True, True)]
