"""The copy from development to production, Step 11F, between two local
test databases and an in-memory stand-in for the two buckets.

The database tests need a local Postgres: see tests/db_support.py.
"""

import threading
import uuid

import psycopg
import pytest

from migrations.connection import UnsafeConnection
from scripts.copy_to_production import (
    CopyError,
    check_pair,
    copy_to_production,
)
from tests.db_support import (
    ADMIN_URL,
    OWNER,
    OWNER_PASSWORD,
    SECOND_DATABASE,
    admin_credentials,
    delete_editions,
    migrate,
    needs_database,
    url_for,
)

TARGET = SECOND_DATABASE


class FakeFiles:
    def __init__(self):
        self.buckets: dict[str, dict[str, int]] = {"dev": {}, "prod": {}}
        self.copies = 0
        self.broken: set[str] = set()
        self.lock = threading.Lock()

    def list(self, bucket, prefix):
        return {k: s for k, s in self.buckets[bucket].items() if k.startswith(prefix)}

    def copy(self, from_bucket, to_bucket, key):
        with self.lock:
            self.copies += 1
            size = self.buckets[from_bucket][key]
            self.buckets[to_bucket][key] = size - 1 if key in self.broken else size


# --- Without a database --------------------------------------------------------


def test_the_same_database_twice_is_refused():
    url = "postgresql://neondb_owner:pw@ep-a-1.eu-central-1.aws.neon.tech/neondb"
    with pytest.raises(UnsafeConnection, match="same database"):
        check_pair(url, url)


def test_pooled_and_app_role_connections_are_refused():
    direct = "postgresql://neondb_owner:pw@ep-a-1.eu-central-1.aws.neon.tech/neondb"
    pooled = "postgresql://neondb_owner:pw@ep-b-1-pooler.eu-central-1.aws.neon.tech/x"
    app = "postgresql://veloraug_app:pw@ep-b-1.eu-central-1.aws.neon.tech/neondb"
    with pytest.raises(UnsafeConnection, match="pooled"):
        check_pair(direct, pooled)
    with pytest.raises(UnsafeConnection, match="veloraug_app"):
        check_pair(app, direct)


def test_different_branches_are_accepted():
    a = "postgresql://neondb_owner:pw@ep-a-1.eu-central-1.aws.neon.tech/neondb"
    b = "postgresql://neondb_owner:pw@ep-b-2.eu-central-1.aws.neon.tech/neondb"
    first, second = check_pair(a, b)
    assert "ep-a-1" in first and "ep-b-2" in second
    assert "pw" not in first + second


# --- Two real databases ----------------------------------------------------------


@pytest.fixture(scope="module")
def target_url(owner_url, app_url):
    """A second database, migrated to head like the first: production.
    Dropped after this file's tests, because other files' downgrade tests
    drop the roles it holds grants for."""
    with psycopg.connect(ADMIN_URL, autocommit=True) as admin:
        admin.execute(f"drop database if exists {TARGET} with (force)")
        admin.execute(f"create database {TARGET} owner {OWNER}")
    with psycopg.connect(url_for(*admin_credentials(), TARGET)) as admin_db:
        admin_db.execute("create schema neon_auth")
        admin_db.execute("create table neon_auth.users_sync (id text, email text)")
        admin_db.execute(
            'create table neon_auth."user" (id uuid primary key, email text, '
            '"emailVerified" boolean, banned boolean)'
        )
        admin_db.execute(f"grant usage on schema neon_auth to {OWNER}")
        admin_db.execute(f'grant select on neon_auth."user" to {OWNER}')
    url = url_for(OWNER, OWNER_PASSWORD, TARGET)
    migrate(url)
    yield url
    with psycopg.connect(ADMIN_URL, autocommit=True) as admin:
        admin.execute(f"drop database if exists {TARGET} with (force)")


@pytest.fixture
def dbs(owner_url, target_url):
    with (
        psycopg.connect(owner_url, autocommit=True) as source,
        psycopg.connect(target_url, autocommit=True) as target,
    ):
        # Other tests share the first database: only what these make goes.
        before = {
            conn: (
                [r[0] for r in conn.execute("select id from public.editions")],
                [r[0] for r in conn.execute("select id from public.vjs")],
            )
            for conn in (source, target)
        }
        yield source, target
        for conn, (editions, vjs) in before.items():
            delete_editions(conn, "id <> all(%s)", (editions,))
            conn.execute("delete from public.vjs where id <> all(%s)", (vjs,))


def add_film(
    conn,
    files: FakeFiles,
    *,
    title="Film",
    test=False,
    status="published",
    ready=True,
    vj=None,
):
    """A published film with one ready original, its files in 'dev'."""
    vj = vj or uuid.uuid4()
    conn.execute(
        "insert into public.vjs (id, name, slug, photo_path) values (%s, %s, %s, %s) "
        "on conflict do nothing",
        (vj, f"VJ {vj.hex[:6]}", f"vj-{vj.hex[:8]}", f"vjs/{vj}/photo1234567890ab.jpg"),
    )
    source, edition, item, key, original = (uuid.uuid4() for _ in range(5))
    conn.execute(
        "insert into public.sources (id, kind, title, details_from, genres) "
        "values (%s, 'movie', %s, 'manual', '{}')",
        (source, title),
    )
    poster = f"posters/{edition}/poster1234567890ab.jpg"
    conn.execute(
        """
        insert into public.editions (id, kind, source_id, vj_id, display_title,
          poster_path, status, published_at, test)
        values (%s, 'movie', %s, %s, %s, %s, %s,
                case when %s = 'published' then now() end, %s)
        """,
        (edition, source, vj, title, poster, status, status, test),
    )
    conn.execute(
        "insert into public.items (id, edition_id, kind, approved_at) "
        "values (%s, %s, 'movie', now())",
        (item, edition),
    )
    conn.execute(
        "insert into public.upload_keys (id, item_id, key_hash, label, expires_at, "
        "used_at) values (%s, %s, %s, 'k', now() + interval '1 day', now())",
        (key, item, uuid.uuid4().bytes * 2),
    )
    conn.execute(
        """
        insert into public.media_originals (id, item_id, upload_key_id, state,
          size_bytes, duration_seconds, ready_at)
        values (%s, %s, %s, %s, 1000, 5400.5, case when %s then now() end)
        """,
        (original, item, key, "ready" if ready else "failed", ready),
    )
    if ready:
        for height, width in ((360, 640), (720, 1280)):
            conn.execute(
                "insert into public.media_renditions (original_id, height, width, "
                "bandwidth, size_bytes) values (%s, %s, %s, 800000, 500)",
                (original, height, width),
            )
    folder = f"movies/{item}/{original}/"
    files.buckets["dev"].update(
        {
            folder + "master.m3u8": 300,
            folder + "360p/index.m3u8": 200,
            folder + "360p/seg_00001.ts": 4_000_000,
            poster: 90_000,
            f"vjs/{vj}/photo1234567890ab.jpg": 40_000,
        }
    )
    return edition


def run(source, target, files, apply=True):
    return copy_to_production(
        source,
        target,
        files,
        from_bucket="dev",
        to_bucket="prod",
        apply=apply,
        say=lambda _: None,
    )


@needs_database
def test_a_published_film_is_copied_with_its_ids_and_files(dbs):
    source, target = dbs
    files = FakeFiles()
    edition = add_film(source, files, title="Baby John")

    report = run(source, target, files)

    assert report.copied == [f"Baby John ({edition})"]
    assert files.buckets["prod"] == files.buckets["dev"]
    assert report.files == 5
    for table, where in (
        ("editions", "id = %s"),
        ("items", "edition_id = %s"),
        (
            "media_originals",
            "item_id in (select id from public.items where edition_id = %s)",
        ),
    ):
        query = f"select * from public.{table} where {where}"
        assert (
            source.execute(query, (edition,)).fetchall()
            == target.execute(query, (edition,)).fetchall()
        )
    (qualities,) = target.execute(
        "select count(*) from public.media_renditions"
    ).fetchone()
    assert qualities == 2


@needs_database
def test_running_again_copies_nothing_twice(dbs):
    source, target = dbs
    files = FakeFiles()
    edition = add_film(source, files)
    run(source, target, files)
    copies = files.copies

    report = run(source, target, files)

    assert report.copied == []
    assert report.already == [f"Film ({edition})"]
    assert files.copies == copies


@needs_database
def test_test_hidden_and_unready_editions_stay_behind(dbs):
    source, target = dbs
    files = FakeFiles()
    add_film(source, files, title="Test", test=True)
    add_film(source, files, title="Hidden", status="hidden")
    add_film(source, files, title="Failed", ready=False)

    report = run(source, target, files)

    assert report.copied == []
    assert [line.split(" (")[0] for line in report.skipped] == ["Failed"]
    assert files.copies == 0
    assert target.execute("select count(*) from public.editions").fetchone() == (0,)


@needs_database
def test_two_films_by_one_vj_share_the_vj(dbs):
    source, target = dbs
    files = FakeFiles()
    vj = uuid.uuid4()
    add_film(source, files, title="One", vj=vj)
    add_film(source, files, title="Two", vj=vj)

    report = run(source, target, files)

    assert len(report.copied) == 2
    assert target.execute("select count(*) from public.vjs").fetchone() == (1,)


@needs_database
def test_a_dry_run_changes_nothing(dbs):
    source, target = dbs
    files = FakeFiles()
    add_film(source, files)

    report = run(source, target, files, apply=False)

    assert len(report.copied) == 1
    assert files.copies == 0
    assert target.execute("select count(*) from public.editions").fetchone() == (0,)


@needs_database
def test_a_file_that_arrives_wrong_adds_no_rows(dbs):
    source, target = dbs
    files = FakeFiles()
    add_film(source, files)
    files.broken = {k for k in files.buckets["dev"] if k.endswith(".ts")}

    with pytest.raises(CopyError, match="didn't arrive whole"):
        run(source, target, files)

    assert target.execute("select count(*) from public.editions").fetchone() == (0,)


@needs_database
def test_a_stopped_copy_resumes_with_the_missing_files(dbs):
    source, target = dbs
    files = FakeFiles()
    add_film(source, files)
    dev = files.buckets["dev"]
    # A stopped run left two files whole and one cut short.
    whole = sorted(k for k in dev if not k.endswith(".ts"))[:2]
    files.buckets["prod"] = {k: dev[k] for k in whole}
    segment = next(k for k in dev if k.endswith(".ts"))
    files.buckets["prod"][segment] = dev[segment] - 1

    report = run(source, target, files)

    assert len(report.copied) == 1
    assert files.copies == len(dev) - 2
    assert files.buckets["prod"] == dev


@needs_database
def test_a_missing_playlist_stops_before_copying(dbs):
    source, target = dbs
    files = FakeFiles()
    add_film(source, files)
    files.buckets["dev"] = {
        k: s for k, s in files.buckets["dev"].items() if not k.endswith("master.m3u8")
    }

    with pytest.raises(CopyError, match="master.m3u8"):
        run(source, target, files)

    assert files.copies == 0


@needs_database
def test_a_clashing_vj_on_production_stops_the_copy(dbs):
    source, target = dbs
    files = FakeFiles()
    vj = uuid.uuid4()
    add_film(source, files, vj=vj)
    # Production has the same slug under another ID.
    target.execute(
        "insert into public.vjs (name, slug) values ('Other', %s)",
        (f"vj-{vj.hex[:8]}",),
    )

    with pytest.raises(CopyError, match="different row in vjs"):
        run(source, target, files)

    assert target.execute("select count(*) from public.editions").fetchone() == (0,)


@needs_database
def test_databases_at_different_migrations_are_refused(dbs):
    source, target = dbs
    target.execute("update public.alembic_version set version_num = '0005'")
    try:
        with pytest.raises(CopyError, match="Migrate production first"):
            run(source, target, FakeFiles())
    finally:
        target.execute("update public.alembic_version set version_num = '0010'")
