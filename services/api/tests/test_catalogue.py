"""The owner's catalogue script, editions, and migration 0005, on a real
Postgres.

TMDB is replaced by a fake. Skipped without a local test Postgres: see
tests/db_support.py.
"""

import os
import subprocess
import sys
import uuid
from datetime import UTC, date, datetime, timedelta

import psycopg
import pytest

from app import editions
from app.editions import EditionError, PublishRefused, create_draft
from app.tmdb import MovieDetails, TmdbNotFound, TmdbRefused, TmdbUnavailable
from scripts import catalogue
from scripts.catalogue import (
    DELETE_AFTER,
    REFRESH_AFTER,
    CatalogueError,
    Edition,
    add_admin,
    describe_edition,
    find_edition,
    list_admins,
    list_editions,
    purge_tmdb,
    refresh,
    remove_admin,
)
from scripts.check_database import check_catalogue
from tests.db_support import (
    API_DIR,
    add_movie,
    clear_admins,
    delete_editions,
    migrate,
    needs_database,
    set_published,
)


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
    for command in (
        "draft",
        "publish",
        "unpublish",
        "list",
        "refresh",
        "purge-tmdb",
        "admin",
        "delete-test-films",
    ):
        assert command in result.stdout


def test_refresh_without_a_token_stops_before_asking_for_the_database(
    monkeypatch, capsys
):
    # conftest.py has already cleared the environment and hidden .env.
    def no_database():
        raise AssertionError("asked for the database")

    monkeypatch.setattr(catalogue, "connect", no_database)
    monkeypatch.setattr(sys, "argv", ["catalogue.py", "refresh"])

    assert catalogue.main() == 1
    assert "VELORAUG_TMDB_READ_ACCESS_TOKEN isn't set" in capsys.readouterr().err


def test_admin_add_needs_a_user(monkeypatch, capsys):
    monkeypatch.setattr(sys, "argv", ["catalogue.py", "admin", "add"])

    assert catalogue.main() == 2
    assert "user's ID" in capsys.readouterr().err


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
    monkeypatch.setattr(sys, "argv", ["catalogue.py", "unpublish", str(uuid.uuid4())])

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


def test_an_edition_is_described_on_one_line():
    edition_id = uuid.uuid4()
    now = datetime(2026, 11, 17, tzinfo=UTC)
    movie = Edition(
        edition_id,
        "movie",
        "Fast X",
        "published",
        False,
        "VJ Junior",
        "lg",
        385687,
        "tmdb",
        now - timedelta(days=3),
        1,
        1,
    )
    series = Edition(
        edition_id,
        "series",
        "Kabaka",
        "draft",
        False,
        None,
        "lg",
        None,
        None,
        None,
        3,
        2,
    )

    assert describe_edition(movie, now) == (
        "Fast X  movie  published  VJ Junior  lg  TMDB 385687, fetched 3 days ago"
        f"  video ready  id {edition_id}"
    )
    assert describe_edition(series, now) == (
        "Kabaka  series  draft  no VJ yet  lg  no details yet  2 of 3 episodes "
        f"ready  id {edition_id}"
    )


# --- Drafts, on the test database --------------------------------------------


@needs_database
def test_a_movie_draft_is_an_edition_and_one_item(owner):
    draft = create_draft(owner, kind="movie", title="  Fast   X ", year=2023)

    edition = owner.execute(
        "select kind, display_title, submitted_year, language, status, vj_id, "
        "source_id from public.editions where id = %s",
        (draft.edition_id,),
    ).fetchone()
    item = owner.execute(
        "select edition_id, kind, season, episode, approved_at from public.items "
        "where id = %s",
        (draft.item_id,),
    ).fetchone()
    assert edition == ("movie", "Fast X", 2023, "lg", "draft", None, None)
    assert item == (draft.edition_id, "movie", None, None, None)
    assert editions.find_item(owner, draft.edition_id) == draft.item_id
    assert editions.find_item(owner, draft.item_id) == draft.item_id


@needs_database
def test_a_series_gets_one_item_per_episode(owner):
    first = create_draft(owner, kind="series", title="Kabaka", season=1, episode=1)
    second = create_draft(
        owner, kind="series", series_edition=first.edition_id, season=1, episode=2
    )

    assert second.edition_id == first.edition_id
    assert second.item_id != first.item_id
    with pytest.raises(EditionError, match="already exists"):
        create_draft(
            owner, kind="series", series_edition=first.edition_id, season=1, episode=2
        )
    with pytest.raises(EditionError, match="find_item|episode's item"):
        editions.find_item(owner, first.edition_id)


@needs_database
@pytest.mark.parametrize(
    ("changes", "message"),
    [
        ({"kind": "show"}, "movie or series"),
        ({"title": "   "}, "Give the title"),
        ({"title": "x" * 201}, "at most 200"),
        ({"year": 1850}, "1900 to 2100"),
        ({"season": 1}, "no season"),
        ({"kind": "series"}, "season and episode"),
        ({"kind": "series", "season": 1, "episode": 0}, "episodes 1"),
        ({"language": "xx"}, "No language"),
    ],
)
def test_draft_mistakes_are_explained(owner, changes, message):
    fields = {"kind": "movie", "title": "Fast X"} | changes
    with pytest.raises(EditionError, match=message):
        create_draft(owner, **fields)


@needs_database
def test_an_episode_needs_a_series_edition(owner):
    movie = create_draft(owner, kind="movie", title="Fast X")

    with pytest.raises(EditionError, match="movie, not a series"):
        create_draft(
            owner, kind="series", series_edition=movie.edition_id, season=1, episode=1
        )
    with pytest.raises(EditionError, match="No edition"):
        create_draft(
            owner, kind="series", series_edition=uuid.uuid4(), season=1, episode=1
        )


# --- Publishing --------------------------------------------------------------


def ready(owner, item_id):
    """An original taken to 'ready', as the worker would, for the item."""
    (key_id,) = owner.execute(
        """
        insert into public.upload_keys (item_id, key_hash, label, expires_at, used_at)
        values (%s, %s, 'Test', now() + interval '1 day', now()) returning id
        """,
        (item_id, os.urandom(32)),
    ).fetchone()
    original = uuid.uuid4()
    owner.execute(
        """
        insert into public.media_originals
          (id, item_id, upload_key_id, size_bytes, state, ready_at)
        values (%s, %s, %s, 1000, 'ready', now())
        """,
        (original, item_id, key_id),
    )
    return original


def vj(owner, name="VJ Junior"):
    slug = name.lower().replace(" ", "-") + "-" + uuid.uuid4().hex[:6]
    return owner.execute(
        "insert into public.vjs (name, slug) values (%s, %s) returning id",
        (f"{name} {slug[-6:]}", slug),
    ).fetchone()[0]


def describe(owner, edition_id, *, title="Fast X", tmdb_id=None, vj_id=None):
    """Gives an edition details, a poster and a VJ, as an admin will."""
    source = owner.execute(
        """
        insert into public.sources (kind, tmdb_id, title, details_from, fetched_at)
        select kind, %s, %s, case when %s::int is null then 'manual' else 'tmdb' end,
               now()
        from public.editions where id = %s
        returning id
        """,
        (tmdb_id, title, tmdb_id, edition_id),
    ).fetchone()[0]
    owner.execute(
        "update public.editions set source_id = %s, vj_id = %s, "
        "poster_path = '/p.jpg' where id = %s",
        (source, vj_id or vj(owner), edition_id),
    )
    return source


@needs_database
def test_publishing_says_what_is_missing(owner):
    draft = create_draft(owner, kind="movie", title="Fast X")

    with pytest.raises(PublishRefused) as refused:
        editions.publish(owner, draft.edition_id)

    assert refused.value.missing == [
        "a ready video",
        "details, from TMDB or typed in",
        "a chosen poster",
        "a confirmed VJ credit",
    ]


@needs_database
def test_a_complete_movie_publishes_and_its_item_is_approved(owner, app_url):
    draft = create_draft(owner, kind="movie", title="Fast X")
    original = ready(owner, draft.item_id)
    describe(owner, draft.edition_id)

    editions.publish(owner, draft.edition_id)
    owner.commit()
    try:
        assert as_app(
            app_url,
            "select id from public.media_originals where item_id = %s",
            (draft.item_id,),
        ) == [(original,)]
        editions.hide(owner, draft.edition_id)
        owner.commit()
        assert (
            as_app(
                app_url,
                "select id from public.items where id = %s",
                (draft.item_id,),
            )
            == []
        )
    finally:
        delete_editions(owner, "id = %s", (draft.edition_id,))
        owner.commit()


@needs_database
def test_a_series_shows_only_approved_episodes(owner, app_url):
    first = create_draft(owner, kind="series", title="Kabaka", season=1, episode=1)
    second = create_draft(
        owner, kind="series", series_edition=first.edition_id, season=1, episode=2
    )
    ready(owner, first.item_id)
    describe(owner, first.edition_id, title="Kabaka")
    editions.publish(owner, first.edition_id)
    owner.commit()
    try:

        def episodes():
            return as_app(
                app_url,
                "select episode from public.items where edition_id = %s "
                "order by episode",
                (first.edition_id,),
            )

        assert episodes() == [(1,)]
        with pytest.raises(PublishRefused):
            editions.approve_item(owner, second.item_id)
        ready(owner, second.item_id)
        editions.approve_item(owner, second.item_id)
        owner.commit()
        assert episodes() == [(1,), (2,)]
    finally:
        delete_editions(owner, "id = %s", (first.edition_id,))
        owner.commit()


@needs_database
def test_the_database_refuses_publishing_an_incomplete_edition(owner):
    draft = create_draft(owner, kind="movie", title="Fast X")

    with pytest.raises(psycopg.errors.CheckViolation):
        owner.execute(
            "update public.editions set status = 'published', published_at = now() "
            "where id = %s",
            (draft.edition_id,),
        )


@needs_database
def test_movie_parts_can_share_a_source_and_vj(owner):
    first = create_draft(owner, kind="movie", title="Fast X")
    second = create_draft(owner, kind="movie", title="Fast X again")
    source = describe(owner, first.edition_id, tmdb_id=new_id())
    junior = owner.execute(
        "select vj_id from public.editions where id = %s", (first.edition_id,)
    ).fetchone()[0]

    assert (
        owner.execute(
            "update public.editions set source_id = %s, vj_id = %s where id = %s",
            (source, junior, second.edition_id),
        ).rowcount
        == 1
    )


@needs_database
def test_an_edition_and_its_source_must_be_the_same_kind(owner):
    series = create_draft(owner, kind="series", title="Kabaka", season=1, episode=1)
    movie = create_draft(owner, kind="movie", title="Fast X")
    source = describe(owner, movie.edition_id)

    with pytest.raises(psycopg.errors.ForeignKeyViolation):
        owner.execute(
            "update public.editions set source_id = %s where id = %s",
            (source, series.edition_id),
        )


# --- What the API's role sees ------------------------------------------------


@needs_database
def test_the_api_role_sees_published_editions_only(owner, app_url):
    hidden, shown = new_id(), new_id()
    add_movie(owner, details(hidden, "Hidden"))
    add_movie(owner, details(shown, "Shown"))
    set_published(owner, str(shown), True)
    draft = create_draft(owner, kind="movie", title="A draft")
    owner.commit()
    try:
        seen = as_app(
            app_url,
            "select s.tmdb_id, s.title from public.editions e "
            "join public.sources s on s.id = e.source_id "
            "where s.tmdb_id in (%s, %s)",
            (hidden, shown),
        )
        assert seen == [(shown, "Shown")]
        assert as_app(
            app_url,
            "select count(*) from public.sources where tmdb_id = %s",
            (hidden,),
        ) == [(0,)]
        assert as_app(
            app_url,
            "select count(*) from public.editions where id = %s",
            (draft.edition_id,),
        ) == [(0,)]
    finally:
        delete_editions(owner, "test or id = %s", (draft.edition_id,))
        owner.commit()


@needs_database
def test_every_catalogue_check_passes_with_hidden_and_published_editions(
    owner, app_url
):
    hidden, shown = new_id(), new_id()
    add_movie(owner, details(hidden))
    add_movie(owner, details(shown))
    set_published(owner, str(shown), True)
    create_draft(owner, kind="series", title="Kabaka", season=1, episode=1)
    vj(owner)
    owner.commit()
    try:
        with psycopg.connect(app_url, autocommit=True) as conn:
            results = check_catalogue(conn)
        assert [r.name for r in results if not r.passed] == []
        assert len(results) == 5
    finally:
        delete_editions(owner)
        owner.execute("delete from public.vjs")
        owner.commit()


@needs_database
def test_the_api_role_can_refresh_a_published_source_but_not_a_hidden_one(
    owner, app_url
):
    hidden, shown = new_id(), new_id()
    add_movie(owner, details(hidden))
    add_movie(owner, details(shown))
    set_published(owner, str(shown), True)
    owner.commit()
    try:
        with psycopg.connect(app_url) as conn:
            changed = conn.execute(
                "update public.sources set title = 'New' where tmdb_id in (%s, %s)",
                (hidden, shown),
            ).rowcount
            conn.rollback()
        assert changed == 1
    finally:
        delete_editions(owner, "test")
        owner.commit()


@needs_database
def test_vjs_show_only_with_a_published_edition(owner, app_url):
    draft = create_draft(owner, kind="movie", title="Fast X")
    ready(owner, draft.item_id)
    describe(owner, draft.edition_id)
    junior = owner.execute(
        "select vj_id from public.editions where id = %s", (draft.edition_id,)
    ).fetchone()[0]
    owner.commit()
    try:

        def seen():
            return as_app(
                app_url, "select count(*) from public.vjs where id = %s", (junior,)
            )

        assert seen() == [(0,)]
        editions.publish(owner, draft.edition_id)
        owner.commit()
        assert seen() == [(1,)]
    finally:
        delete_editions(owner, "id = %s", (draft.edition_id,))
        owner.execute("delete from public.vjs where id = %s", (junior,))
        owner.commit()


# --- The editor role ---------------------------------------------------------


# editor_url is in conftest.py.


@needs_database
def test_the_editor_can_draft_describe_publish_and_manage_admins(editor_url):
    with psycopg.connect(editor_url) as conn:
        draft = create_draft(conn, kind="movie", title="Fast X")
        describe(conn, draft.edition_id)
        conn.execute(
            "insert into public.admins (user_id, email) values (%s, 'a@b.test'), "
            "(%s, 'c@d.test')",
            (uuid.uuid4(), uuid.uuid4()),
        )
        conn.execute(
            "delete from public.admins where email = 'a@b.test'",
        )
        with pytest.raises(PublishRefused, match="a ready video"):
            editions.publish(conn, draft.edition_id)
        conn.rollback()


@needs_database
@pytest.mark.parametrize(
    "statement",
    [
        "select count(*) from public.profiles",
        "select count(*) from neon_auth.users_sync",
        "select key_hash from public.upload_keys",
        "delete from public.editions",
        "delete from public.sources",
        "delete from public.upload_keys",
        "update public.media_originals set state = 'ready'",
        "update public.upload_keys set used_at = now()",
        "create table public.veloraug_check (id int)",
    ],
)
def test_the_editor_can_do_nothing_else(editor_url, statement):
    with (
        psycopg.connect(editor_url) as conn,
        pytest.raises(psycopg.errors.InsufficientPrivilege),
    ):
        conn.execute(statement)


@needs_database
def test_the_editor_deletes_only_vjs_without_titles(editor_url):
    """For merging duplicates and removing unused VJs (Step 13H). A VJ with
    titles stays: the titles' link to them refuses it."""
    with psycopg.connect(editor_url) as conn:
        unused = conn.execute(
            "insert into public.vjs (name, slug) values ('VJ Unused', 'vj-unused') "
            "returning id"
        ).fetchone()[0]
        used = conn.execute(
            "insert into public.vjs (name, slug) values ('VJ Used', 'vj-used') "
            "returning id"
        ).fetchone()[0]
        draft = create_draft(conn, kind="movie", title="Fast X")
        conn.execute(
            "update public.editions set vj_id = %s where id = %s",
            (used, draft.edition_id),
        )
        assert (
            conn.execute("delete from public.vjs where id = %s", (unused,)).rowcount
            == 1
        )
        with pytest.raises(psycopg.errors.ForeignKeyViolation):
            conn.execute("delete from public.vjs where id = %s", (used,))
        conn.rollback()


# --- Admins ------------------------------------------------------------------


@needs_database
def test_admins_are_added_listed_and_removed_but_never_the_last(owner):
    clear_admins(owner)
    first, second = str(uuid.uuid4()), str(uuid.uuid4())

    add_admin(owner, first, "owner@example.test")
    with pytest.raises(CatalogueError, match="already an admin"):
        add_admin(owner, first)
    with pytest.raises(CatalogueError, match="last admin"):
        remove_admin(owner, first)
    add_admin(owner, second)
    remove_admin(owner, first)

    assert [str(row[0]) for row in list_admins(owner)] == [second]
    with pytest.raises(CatalogueError, match="isn't an admin"):
        remove_admin(owner, first)
    with pytest.raises(CatalogueError, match="isn't a user ID"):
        add_admin(owner, "someone")
    with pytest.raises(CatalogueError, match="isn't an email"):
        add_admin(owner, str(uuid.uuid4()), "not-an-email")


@needs_database
def test_deleting_every_admin_at_once_is_refused(owner):
    clear_admins(owner)
    add_admin(owner, str(uuid.uuid4()))
    add_admin(owner, str(uuid.uuid4()))

    with pytest.raises(psycopg.errors.CheckViolation):
        owner.execute("delete from public.admins")


# --- Listing, refreshing and purging -----------------------------------------


@needs_database
def test_list_shows_published_first(owner):
    first, second = new_id(), new_id()
    hidden = add_movie(owner, details(first, "Hidden one"))
    shown = add_movie(owner, details(second, "Published one"))
    set_published(owner, str(second), True)

    found = [e.id for e in list_editions(owner) if e.id in (hidden, shown)]

    assert found == [shown, hidden]
    assert find_edition(owner, str(shown)).status == "published"
    with pytest.raises(CatalogueError, match="No edition"):
        find_edition(owner, str(uuid.uuid4()))
    with pytest.raises(CatalogueError, match="isn't an edition ID"):
        find_edition(owner, "fight-club")


def age(owner, tmdb_id, days):
    owner.execute(
        "update public.sources set fetched_at = now() - %s where tmdb_id = %s",
        (timedelta(days=days), tmdb_id),
    )


def fetched(owner, tmdb_id):
    return owner.execute(
        "select title, fetched_at from public.sources where tmdb_id = %s",
        (tmdb_id,),
    ).fetchone()


@needs_database
def test_refresh_fetches_only_old_copies(owner):
    fresh, old, missing = new_id(), new_id(), new_id()
    for tmdb_id in (fresh, old, missing):
        add_movie(owner, details(tmdb_id))
    age(owner, fresh, 1)
    age(owner, old, REFRESH_AFTER.days + 1)
    owner.execute(
        "update public.sources set fetched_at = null where tmdb_id = %s", (missing,)
    )
    fetched_ids: list[int] = []

    def fetch(kind, tmdb_id):
        fetched_ids.append(tmdb_id)
        return details(tmdb_id, f"New {tmdb_id}")

    refresh(owner, fetch)

    assert fresh not in fetched_ids
    assert old in fetched_ids and missing in fetched_ids
    assert fetched(owner, old)[0] == f"New {old}"
    assert fetched(owner, missing)[0] == f"New {missing}"
    assert fetched(owner, fresh)[0] == "A movie"


@needs_database
def test_a_failed_refresh_keeps_a_copy_until_180_days_then_clears_it(owner):
    young, expired = new_id(), new_id()
    add_movie(owner, details(young))
    shown = add_movie(owner, details(expired))
    set_published(owner, str(shown), True)
    age(owner, young, 30)
    age(owner, expired, DELETE_AFTER.days)

    def fetch(kind, tmdb_id):
        if tmdb_id == young:
            raise TmdbUnavailable("TMDB answered 503")
        if tmdb_id == expired:
            raise TmdbNotFound(f"TMDB has no movie {tmdb_id}")
        return details(tmdb_id)

    # The fixture ages copies using PostgreSQL's transaction clock.
    now = owner.execute("select now()").fetchone()[0]
    result = refresh(owner, fetch, now=now)

    assert fetched(owner, young)[1] is not None
    assert fetched(owner, expired)[1] is None
    assert find_edition(owner, str(shown)).status == "hidden"
    assert f"movie {young}: TMDB answered 503" in result.failed
    assert f"movie {expired}: TMDB has no movie {expired}" in result.failed
    assert result.deleted >= 1


@needs_database
def test_a_refused_token_stops_the_refresh(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))
    age(owner, tmdb_id, 30)

    def fetch(kind, tmdb_id):
        raise TmdbRefused("TMDB refused the token")

    with pytest.raises(TmdbRefused):
        refresh(owner, fetch)


@needs_database
def test_purge_clears_every_tmdb_copy_and_hides_what_shows_one(owner):
    tmdb_id = new_id()
    film = add_movie(owner, details(tmdb_id))
    set_published(owner, str(tmdb_id), True)
    typed_in = create_draft(owner, kind="movie", title="Typed in")
    describe(owner, typed_in.edition_id)

    purge_tmdb(owner)

    assert (
        owner.execute(
            "select count(*) from public.sources "
            "where details_from = 'tmdb' and fetched_at is not null"
        ).fetchone()[0]
        == 0
    )
    assert find_edition(owner, str(film)).status == "hidden"
    assert owner.execute(
        "select s.fetched_at is not null from public.editions e "
        "join public.sources s on s.id = e.source_id where e.id = %s",
        (typed_in.edition_id,),
    ).fetchone() == (True,)


# --- TMDB ratings (0011) -----------------------------------------------------


def rating_of(owner, tmdb_id):
    return owner.execute(
        "select tmdb_rating::float8, tmdb_vote_count, rating_updated_at is not null "
        "from public.sources where tmdb_id = %s",
        (tmdb_id,),
    ).fetchone()


def rated(tmdb_id: int, title: str = "A movie", rating=7.4, votes=120):
    from dataclasses import replace

    return replace(details(tmdb_id, title), rating=rating, vote_count=votes)


@needs_database
def test_refresh_saves_the_rating_with_the_copy(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))
    age(owner, tmdb_id, REFRESH_AFTER.days + 1)
    assert rating_of(owner, tmdb_id) == (None, None, False)

    refresh(owner, lambda kind, tmdb_id: rated(tmdb_id))

    assert rating_of(owner, tmdb_id) == (7.4, 120, True)


@needs_database
def test_a_title_tmdb_has_no_rating_for_is_still_marked_as_asked(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))
    age(owner, tmdb_id, REFRESH_AFTER.days + 1)

    refresh(owner, lambda kind, tmdb_id: details(tmdb_id))

    assert rating_of(owner, tmdb_id) == (None, None, True)


@needs_database
def test_clearing_an_expired_copy_clears_its_rating(owner):
    tmdb_id = new_id()
    shown = add_movie(owner, details(tmdb_id))
    set_published(owner, str(shown), True)
    catalogue.save_details(owner, rated(tmdb_id), "movie")
    age(owner, tmdb_id, DELETE_AFTER.days)

    def fetch(kind, tmdb_id):
        raise TmdbNotFound(f"TMDB has no movie {tmdb_id}")

    now = owner.execute("select now()").fetchone()[0]
    refresh(owner, fetch, now=now)

    assert rating_of(owner, tmdb_id) == (None, None, False)


@needs_database
def test_tmdb_popularity_is_saved_and_cleared_with_the_copy(owner):
    from dataclasses import replace

    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))
    catalogue.save_details(owner, replace(details(tmdb_id), popularity=81.25), "movie")

    def popularity():
        return owner.execute(
            "select tmdb_popularity::float8 from public.sources where tmdb_id = %s",
            (tmdb_id,),
        ).fetchone()[0]

    assert popularity() == 81.25
    purge_tmdb(owner)
    assert popularity() is None


@needs_database
def test_purge_clears_every_rating(owner):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))
    catalogue.save_details(owner, rated(tmdb_id), "movie")

    purge_tmdb(owner)

    assert rating_of(owner, tmdb_id) == (None, None, False)


@pytest.mark.parametrize(
    ("rating", "votes"), [(7.0, None), (None, 5), (10.5, 5), (-0.1, 5), (5.0, -1)]
)
@needs_database
def test_the_database_refuses_a_strange_rating(owner, rating, votes):
    tmdb_id = new_id()
    add_movie(owner, details(tmdb_id))

    with pytest.raises(psycopg.errors.CheckViolation):
        owner.execute(
            "update public.sources set tmdb_rating = %s, tmdb_vote_count = %s "
            "where tmdb_id = %s",
            (rating, votes, tmdb_id),
        )


@needs_database
def test_the_api_role_can_refresh_a_published_sources_rating(owner, app_url):
    tmdb_id = new_id()
    shown = add_movie(owner, details(tmdb_id))
    set_published(owner, str(shown), True)
    owner.commit()
    try:
        with psycopg.connect(app_url) as conn:
            changed = catalogue.save_details(conn, rated(tmdb_id, rating=6.1), "movie")
            conn.commit()
        assert changed == 1
        assert rating_of(owner, tmdb_id) == (6.1, 120, True)
    finally:
        delete_editions(owner, "test")
        owner.commit()


# --- Deleting the test films -------------------------------------------------


@needs_database
def test_test_films_are_deleted_in_two_runs(owner):
    delete_editions(owner, "test")
    film = add_movie(owner, details(new_id()))
    set_published(owner, str(film), True)
    original = ready(owner, film)
    kept = create_draft(owner, kind="movie", title="A real one")

    first = editions.delete_test_films(owner)

    assert (first.editions, first.marked_for_removal, first.deleted) == (1, 1, False)
    assert owner.execute(
        "select state from public.media_originals where id = %s", (original,)
    ).fetchone() == ("removing",)
    assert find_edition(owner, str(film)).status == "hidden"

    # The media worker removes the files, then marks it removed.
    owner.execute(
        "update public.media_originals set state = 'removed' where id = %s",
        (original,),
    )
    second = editions.delete_test_films(owner)

    assert second.deleted is True
    assert owner.execute(
        "select count(*) from public.editions where test"
    ).fetchone() == (0,)
    assert owner.execute(
        "select count(*) from public.editions where id = %s", (kept.edition_id,)
    ).fetchone() == (1,)
    assert editions.delete_test_films(owner).editions == 0


# --- Migration 0005 ----------------------------------------------------------


@needs_database
def test_0005_moves_todays_films_across_with_their_ids(owner_url, app_url):
    """A film, its key and its ready original made at 0004 keep their IDs,
    and the API still sees the original, after the upgrade."""
    try:
        migrate(owner_url, "0004", down=True)
        tmdb_id = new_id()
        with psycopg.connect(owner_url) as conn:
            (movie,) = conn.execute(
                "insert into public.movies (tmdb_id, published, published_at) "
                "values (%s, true, now()) returning id",
                (tmdb_id,),
            ).fetchone()
            conn.execute(
                "insert into public.tmdb_movie_details (tmdb_id, title) "
                "values (%s, 'The Matrix')",
                (tmdb_id,),
            )
            (key,) = conn.execute(
                """
                insert into public.upload_keys
                  (movie_id, key_hash, label, expires_at, used_at)
                values (%s, %s, 'Test', now() + interval '1 day', now())
                returning id
                """,
                (movie, os.urandom(32)),
            ).fetchone()
            original = uuid.uuid4()
            conn.execute(
                """
                insert into public.media_originals
                  (id, movie_id, upload_key_id, size_bytes, state, ready_at)
                values (%s, %s, %s, 1000, 'ready', now())
                """,
                (original, movie, key),
            )
        migrate(owner_url)
        with psycopg.connect(owner_url) as conn:
            assert conn.execute(
                "select e.status, e.test, i.id, s.title, s.tmdb_id "
                "from public.editions e join public.items i on i.edition_id = e.id "
                "join public.sources s on s.id = e.source_id where e.id = %s",
                (movie,),
            ).fetchone() == ("published", True, movie, "The Matrix", tmdb_id)
            assert conn.execute(
                "select item_id from public.media_originals where id = %s",
                (original,),
            ).fetchone() == (movie,)
        assert as_app(
            app_url,
            "select id from public.media_originals where item_id = %s",
            (movie,),
        ) == [(original,)]
    finally:
        migrate(owner_url)
        with psycopg.connect(owner_url) as conn:
            delete_editions(conn, "test")


@needs_database
def test_the_owner_sees_the_migration(owner_url, app_url):
    with psycopg.connect(owner_url) as conn:
        assert conn.execute(
            "select to_regclass('public.movies') is null, "
            "to_regclass('public.editions') is not null, "
            "(select name from public.languages where code = 'lg')"
        ).fetchone() == (True, True, "Luganda")
