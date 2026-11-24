"""Checks the database as the API's own role, veloraug_app.

Run from services/api after the migration:

    .\\.venv\\Scripts\\python.exe scripts\\check_database.py

It reads VELORAUG_DATABASE_URL from the environment, or from
services/api/.env, and prints only the host. Every test that writes runs in a
transaction that is rolled back, with random user IDs, so it leaves nothing
behind. The checks follow the Step 5F criteria in docs/step-05a-neon-plan.md,
the Step 6B criteria in docs/step-06a-catalogue-plan.md, and the Step 8B
criteria in docs/step-08a-playback-plan.md.
"""

import sys
import threading
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote, urlsplit

import psycopg
from psycopg import errors

API_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(API_DIR))

from migrations.connection import (  # noqa: E402
    APP_ROLE,
    NEON_AUTH_TABLES,
    UnsafeConnection,
    _setting,
    require_sign_in_branch,
)


@dataclass
class Result:
    name: str
    passed: bool
    detail: str = ""


def database_url() -> str:
    """The app's URL, checked before any connection is made."""
    url = _setting("VELORAUG_DATABASE_URL")
    if not url:
        sys.exit("VELORAUG_DATABASE_URL isn't set, and isn't in services/api/.env")
    parts = urlsplit(url)
    if unquote(parts.username or "") != APP_ROLE:
        sys.exit(
            f"Refused: VELORAUG_DATABASE_URL must use {APP_ROLE}. Run "
            "scripts/create_app_role.py first"
        )
    return url


def as_user(conn: psycopg.Connection, user_id: uuid.UUID | None) -> None:
    value = "" if user_id is None else str(user_id)
    conn.execute("select set_config('app.user_id', %s, true)", (value,))


def refused(conn: psycopg.Connection, statement: str, params=()) -> bool:
    """True if the statement fails with a permission or policy error."""
    try:
        # Rolled back even if it succeeds, so a check can never change data.
        with conn.transaction(force_rollback=True):
            conn.execute(statement, params)
    except (errors.InsufficientPrivilege, errors.CheckViolation):
        return True
    return False


def check_role(conn: psycopg.Connection) -> list[Result]:
    who = conn.execute("select current_user, version()").fetchone()
    results = [Result("connected as veloraug_app", who[0] == APP_ROLE, who[0])]
    row = conn.execute(
        """
        select rolsuper, rolbypassrls, rolcreaterole, rolcreatedb, rolreplication
        from pg_roles where rolname = current_user
        """
    ).fetchone()
    results.append(
        Result(
            "no superuser, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION",
            not any(row),
        )
    )
    in_neon_superuser = conn.execute(
        """
        select exists (select from pg_roles where rolname = 'neon_superuser')
          and pg_has_role(current_user, 'neon_superuser', 'member')
        """
    ).fetchone()[0]
    results.append(Result("not a member of neon_superuser", not in_neon_superuser))
    memberships = conn.execute(
        """
        select count(*) from pg_auth_members m
        join pg_roles a on a.oid = m.member where a.rolname = current_user
        """
    ).fetchone()[0]
    results.append(Result("member of no other role", memberships == 0))
    owned = conn.execute(
        """
        select (select count(*) from pg_class where relowner = r.oid)
             + (select count(*) from pg_proc where proowner = r.oid)
             + (select count(*) from pg_namespace where nspowner = r.oid)
             + (select count(*) from pg_type where typowner = r.oid)
        from pg_roles r where r.rolname = current_user
        """
    ).fetchone()[0]
    results.append(Result("owns nothing", owned == 0, f"{owned} objects"))
    return results


def check_schema_rights(conn: psycopg.Connection) -> list[Result]:
    results = []
    neon_auth = conn.execute(
        "select exists (select from pg_namespace where nspname = 'neon_auth')"
    ).fetchone()[0]
    if neon_auth:
        usage = conn.execute(
            "select has_schema_privilege('neon_auth', 'USAGE')"
        ).fetchone()[0]
        readable = conn.execute(
            """
            select count(*) from pg_class c
            join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'neon_auth'
              and has_table_privilege(c.oid, 'SELECT, INSERT, UPDATE, DELETE')
            """
        ).fetchone()[0]
        results.append(
            Result(
                "can't read neon_auth",
                not usage and readable == 0,
                f"schema usage {usage}, readable tables {readable}",
            )
        )
    else:
        results.append(Result("can't read neon_auth", True, "no neon_auth schema"))

    can_create = conn.execute(
        "select has_schema_privilege('public', 'CREATE')"
    ).fetchone()[0]
    results.append(
        Result(
            "can't change the schema",
            not can_create
            and refused(conn, "create table public.veloraug_check (id int)")
            and refused(conn, "alter table public.profiles add column x int")
            and refused(conn, "drop table public.profiles"),
        )
    )
    results.append(
        Result(
            "no rights on alembic_version",
            not conn.execute(
                """
                select has_table_privilege('public.alembic_version',
                  'SELECT, INSERT, UPDATE, DELETE')
                """
            ).fetchone()[0],
        )
    )
    return results


def check_table(conn: psycopg.Connection) -> list[Result]:
    flags = conn.execute(
        """
        select relrowsecurity, relforcerowsecurity from pg_class
        where oid = 'public.profiles'::regclass
        """
    ).fetchone()
    results = [Result("RLS and forced RLS on profiles", flags == (True, True))]

    def table(privilege: str) -> bool:
        return conn.execute(
            "select has_table_privilege('public.profiles', %s)", (privilege,)
        ).fetchone()[0]

    def column(name: str, privilege: str) -> bool:
        return conn.execute(
            "select has_column_privilege('public.profiles', %s, %s)",
            (name, privilege),
        ).fetchone()[0]

    expected = {
        "SELECT": True,
        "INSERT on the table": False,
        "INSERT (user_id)": True,
        "UPDATE on the table": False,
        "UPDATE (display_name)": True,
        "UPDATE (user_id)": False,
        "UPDATE (created_at)": False,
        "UPDATE (updated_at)": False,
        # 0009: account deletion removes the viewer's own profile.
        "DELETE": True,
        "TRUNCATE": False,
        "REFERENCES": False,
        "TRIGGER": False,
    }
    actual = {
        "SELECT": table("SELECT"),
        "INSERT on the table": table("INSERT"),
        "INSERT (user_id)": column("user_id", "INSERT"),
        "UPDATE on the table": table("UPDATE"),
        "UPDATE (display_name)": column("display_name", "UPDATE"),
        "UPDATE (user_id)": column("user_id", "UPDATE"),
        "UPDATE (created_at)": column("created_at", "UPDATE"),
        "UPDATE (updated_at)": column("updated_at", "UPDATE"),
        "DELETE": table("DELETE"),
        "TRUNCATE": table("TRUNCATE"),
        "REFERENCES": table("REFERENCES"),
        "TRIGGER": table("TRIGGER"),
    }
    wrong = [name for name in expected if expected[name] != actual[name]]
    results.append(
        Result("grants match the migration", not wrong, ", ".join(wrong) or "")
    )
    return results


def check_isolation(conn: psycopg.Connection) -> list[Result]:
    """Users A and B, in one transaction that is rolled back at the end."""
    a, b = uuid.uuid4(), uuid.uuid4()
    results = []
    with conn.transaction(force_rollback=True):
        as_user(conn, None)
        visible = conn.execute("select count(*) from public.profiles").fetchone()[0]
        results.append(Result("with no user, reads nothing", visible == 0))
        results.append(
            Result(
                "with no user, writes nothing",
                refused(
                    conn, "insert into public.profiles (user_id) values (%s)", (a,)
                ),
            )
        )

        as_user(conn, a)
        conn.execute(
            "insert into public.profiles (user_id) values (%s) on conflict do nothing",
            (a,),
        )
        as_user(conn, b)
        conn.execute("insert into public.profiles (user_id) values (%s)", (b,))
        conn.execute(
            "update public.profiles set display_name = 'B' where user_id = %s", (b,)
        )

        as_user(conn, a)
        seen = conn.execute("select user_id from public.profiles").fetchall()
        asked = conn.execute(
            "select count(*) from public.profiles where user_id = %s", (b,)
        ).fetchone()[0]
        results.append(
            Result("A sees A's row and not B's", seen == [(a,)] and asked == 0)
        )
        changed = conn.execute(
            "update public.profiles set display_name = 'A' where user_id = %s", (b,)
        ).rowcount
        results.append(
            Result(
                "A can't change or create B's row",
                changed == 0
                and refused(
                    conn,
                    "insert into public.profiles (user_id) values (%s)",
                    (uuid.uuid4(),),
                ),
            )
        )
        results.append(
            Result(
                "user_id, created_at and updated_at can't be changed",
                refused(conn, "update public.profiles set user_id = %s", (b,))
                and refused(conn, "update public.profiles set created_at = now()")
                and refused(conn, "update public.profiles set updated_at = now()"),
            )
        )
        # 0009: a viewer may delete their own profile, to delete their
        # account, and never anyone else's.
        removed = conn.execute(
            "delete from public.profiles where user_id = %s", (b,)
        ).rowcount
        results.append(Result("A can't delete B's row", removed == 0))

        as_user(conn, b)
        name = conn.execute(
            "select display_name from public.profiles where user_id = %s", (b,)
        ).fetchone()
        results.append(Result("B's row unchanged, seen as B", name == ("B",)))
    return results


CATALOGUE_TABLES = (
    "public.languages",
    "public.vjs",
    "public.sources",
    "public.editions",
    "public.items",
    "public.tmdb_matches",
    "public.admins",
)


def check_catalogue(conn: psycopg.Connection) -> list[Result]:
    """The API reads what is published only, and can't change the catalogue.

    These follow the Step 9B criteria in docs/step-09a-vj-catalogue-plan.md,
    which replace Step 6B's.
    """
    flags = conn.execute(
        """
        select count(*) = %s and bool_and(relrowsecurity and relforcerowsecurity)
        from pg_class where oid = any(%s::regclass[])
        """,
        (len(CATALOGUE_TABLES), list(CATALOGUE_TABLES)),
    ).fetchone()[0]
    results = [Result("RLS and forced RLS on every catalogue table", flags)]

    privileges = ("SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES")
    expected = {
        "public.languages": {"SELECT"},
        "public.editions": {"SELECT"},
        "public.sources": {"SELECT"},
        "public.vjs": set(),
        "public.items": set(),
        "public.tmdb_matches": set(),
        "public.admins": set(),
    }
    wrong = []
    for table, allowed in expected.items():
        for privilege in (*privileges, "TRIGGER"):
            has = conn.execute(
                "select has_table_privilege(%s, %s)", (table, privilege)
            ).fetchone()[0]
            if has != (privilege in allowed):
                wrong.append(f"{table} {privilege}")
    # Column rights: some columns of VJs and items, and refreshing details.
    for table, privilege in (
        ("public.vjs", "INSERT"),
        ("public.vjs", "UPDATE"),
        ("public.items", "INSERT"),
        ("public.items", "UPDATE"),
        ("public.sources", "INSERT"),
    ):
        if conn.execute(
            "select has_any_column_privilege(%s, %s)", (table, privilege)
        ).fetchone()[0]:
            wrong.append(f"{table} {privilege}")
    results.append(
        Result("catalogue grants match the migration", not wrong, ", ".join(wrong))
    )

    unpublished = conn.execute(
        "select count(*) from public.editions where status <> 'published'"
    ).fetchone()[0]
    sources = conn.execute(
        """
        select count(*) from public.sources s
        where not exists (select from public.editions e where e.source_id = s.id)
        """
    ).fetchone()[0]
    items = conn.execute(
        """
        select count(*) from public.items i
        where not exists (select from public.editions e where e.id = i.edition_id)
        """
    ).fetchone()[0]
    vjs = conn.execute(
        """
        select count(*) from public.vjs v
        where not exists (select from public.editions e where e.vj_id = v.id)
        """
    ).fetchone()[0]
    results.append(
        Result(
            "drafts, hidden editions and what only they use can't be seen",
            unpublished == 0 and sources == 0 and items == 0 and vjs == 0,
            f"{unpublished} editions, {sources} sources, {items} items, {vjs} VJs seen",
        )
    )
    results.append(
        Result(
            "can't add, publish, hide or remove editions or episodes",
            refused(
                conn,
                "insert into public.editions (kind, display_title) "
                "values ('movie', 'x')",
            )
            and refused(conn, "update public.editions set status = 'published'")
            and refused(conn, "update public.editions set status = 'hidden'")
            and refused(conn, "delete from public.editions")
            and refused(conn, "update public.items set approved_at = now()"),
        )
    )
    results.append(
        Result(
            "can't add or delete sources, VJs, languages or admins",
            refused(
                conn,
                "insert into public.sources (kind, title, details_from) "
                "values ('movie', 'x', 'manual')",
            )
            and refused(conn, "delete from public.sources")
            and refused(conn, "insert into public.vjs (name, slug) values ('x', 'x')")
            and refused(
                conn, "insert into public.languages (code, name) values ('zz', 'x')"
            )
            # Since Step 10B it may see whether its own viewer is an admin,
            # by user ID only.
            and refused(conn, "select email from public.admins"),
        )
    )
    return results


def check_passes(conn: psycopg.Connection) -> list[Result]:
    """The API sees and changes only its viewer's payments and passes, can't
    change prices, and can't make a pass without a completed payment.

    These follow the Step 10B criteria in docs/step-10a-payments-plan.md.
    """
    tables = ("public.pass_plans", "public.payments", "public.passes")
    flags = conn.execute(
        """
        select count(*) = 3 and bool_and(relrowsecurity and relforcerowsecurity)
        from pg_class where oid = any(%s::regclass[])
        """,
        (list(tables),),
    ).fetchone()[0]
    results = [Result("RLS and forced RLS on the pass tables", flags)]

    expected = {
        "public.pass_plans": {"SELECT"},
        "public.payments": {"SELECT", "INSERT"},
        "public.passes": {"SELECT", "INSERT"},
    }
    wrong = []
    for table, allowed in expected.items():
        for privilege in ("SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"):
            has = conn.execute(
                "select has_table_privilege(%s, %s)", (table, privilege)
            ).fetchone()[0]
            if has != (privilege in allowed):
                wrong.append(f"{table} {privilege}")
    for table, column in (
        ("public.pass_plans", "price_ugx"),
        ("public.payments", "amount_ugx"),
        ("public.payments", "user_id"),
        ("public.payments", "max_devices"),
        ("public.passes", "plan_id"),
        ("public.passes", "max_devices"),
    ):
        if conn.execute(
            "select has_column_privilege(%s, %s, 'UPDATE')", (table, column)
        ).fetchone()[0]:
            wrong.append(f"{table}.{column} UPDATE")
    results.append(
        Result("pass grants match the migration", not wrong, ", ".join(wrong))
    )

    viewer = uuid.uuid4()
    with conn.transaction(force_rollback=True):
        as_user(conn, viewer)
        seen = conn.execute(
            "select (select count(*) from public.payments) + "
            "(select count(*) from public.passes)"
        ).fetchone()[0]
    results.append(
        Result(
            "a viewer sees no one else's payments or passes",
            seen == 0,
            f"{seen} seen",
        )
    )

    def as_viewer(statement: str, params=()) -> bool:
        try:
            with conn.transaction(force_rollback=True):
                as_user(conn, viewer)
                conn.execute(statement, params)
        except (errors.InsufficientPrivilege, errors.CheckViolation):
            return True
        return False

    results.append(
        Result(
            "can't change prices, or make a pass without a completed payment",
            refused(conn, "update public.pass_plans set price_ugx = 500")
            and as_viewer(
                """
                insert into public.passes (user_id, payment_id, starts_at, ends_at,
                  plan_id, max_devices, max_streams)
                values (%s, gen_random_uuid(), now(), now() + interval '1 day',
                  'velora_start', 1, 1)
                """,
                (viewer,),
            )
            and as_viewer(
                """
                insert into public.payments (user_id, plan_id, days, amount_ugx,
                  email)
                values (gen_random_uuid(), 'day', 1, 500, 'a@b.c')
                """
            )
            and as_viewer("delete from public.payments"),
        )
    )
    return results


TIERS = {
    "velora_start": (7, 1),
    "velora_flex": (14, 1),
    "velora_prime": (30, 1),
    "velora_duo": (90, 2),
    "velora_pro": (180, 2),
    "velora_max": (365, 3),
}


def check_subscriptions(conn: psycopg.Connection) -> list[Result]:
    """Milestone 10: the six tiers, and devices and playback sessions seen
    and changed only by their own viewer, three at most.

    These follow migration 0007 and docs/step-10a-payments-plan.md.
    """
    tables = ("public.devices", "public.playback_sessions", "public.plan_changes")
    flags = conn.execute(
        """
        select count(*) = 3 and bool_and(relrowsecurity and relforcerowsecurity)
        from pg_class where oid = any(%s::regclass[])
        """,
        (list(tables),),
    ).fetchone()[0]
    results = [Result("RLS and forced RLS on devices, sessions, plan changes", flags)]

    plans = {
        row[0]: (row[1], row[2])
        for row in conn.execute(
            "select id, days, max_devices from public.pass_plans where not legacy"
        ).fetchall()
    }
    results.append(
        Result(
            "the six tiers, with their days and devices",
            plans == TIERS,
            ", ".join(sorted(set(plans) ^ set(TIERS))),
        )
    )

    expected = {
        "public.devices": {"SELECT", "INSERT"},
        "public.playback_sessions": {"SELECT", "INSERT"},
        "public.plan_changes": set(),
    }
    wrong = []
    for table, allowed in expected.items():
        for privilege in ("SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"):
            has = conn.execute(
                "select has_table_privilege(%s, %s)", (table, privilege)
            ).fetchone()[0]
            if has != (privilege in allowed):
                wrong.append(f"{table} {privilege}")
    for table, column in (
        ("public.devices", "secret_hash"),
        ("public.devices", "user_id"),
        ("public.playback_sessions", "pass_id"),
        ("public.playback_sessions", "user_id"),
    ):
        if conn.execute(
            "select has_column_privilege(%s, %s, 'UPDATE')", (table, column)
        ).fetchone()[0]:
            wrong.append(f"{table}.{column} UPDATE")
    results.append(
        Result(
            "device and session grants match the migration", not wrong, ", ".join(wrong)
        )
    )

    viewer = uuid.uuid4()
    with conn.transaction(force_rollback=True):
        as_user(conn, viewer)
        seen = conn.execute(
            "select (select count(*) from public.devices) + "
            "(select count(*) from public.playback_sessions)"
        ).fetchone()[0]
        unknown = conn.execute(
            "select count(*) from public.playback_session_status("
            "gen_random_uuid(), 180)"
        ).fetchone()[0]
    results.append(
        Result(
            "a viewer sees no one else's devices or sessions",
            seen == 0 and unknown == 0,
            f"{seen} seen",
        )
    )

    fourth_refused = False
    try:
        with conn.transaction(force_rollback=True):
            as_user(conn, viewer)
            for _ in range(4):
                conn.execute(
                    """
                    insert into public.devices (user_id, secret_hash, label, platform)
                    values (%s, sha256(gen_random_uuid()::text::bytea), 'Check',
                      'web')
                    """,
                    (viewer,),
                )
    except errors.CheckViolation:
        fourth_refused = True
    results.append(Result("a fourth device is refused", fourth_refused))
    return results


def check_account(conn: psycopg.Connection) -> list[Result]:
    """Migration 0009: watch history, notification read marks and account
    deletions, each seen and changed only by its own viewer."""
    tables = (
        "public.watch_history",
        "public.notification_reads",
        "public.account_deletions",
    )
    flags = conn.execute(
        """
        select count(*) = 3 and bool_and(relrowsecurity and relforcerowsecurity)
        from pg_class where oid = any(%s::regclass[])
        """,
        (list(tables),),
    ).fetchone()[0]
    results = [Result("RLS and forced RLS on the account tables", flags)]

    first, second = uuid.uuid4(), uuid.uuid4()
    item = uuid.uuid4()
    # Rolled back at the end, so the check never leaves a row behind.
    with conn.transaction(force_rollback=True):
        as_user(conn, first)
        conn.execute(
            "insert into public.watch_history (user_id, item_id) values (%s, %s)",
            (first, item),
        )
        as_user(conn, second)
        hidden = (
            conn.execute("select count(*) from public.watch_history").fetchone()[0] == 0
        )
        refused_other = refused(
            conn,
            "insert into public.watch_history (user_id, item_id) values (%s, %s)",
            (first, uuid.uuid4()),
        )
    results.append(
        Result(
            "a viewer sees and adds only their own watch history",
            hidden and refused_other,
        )
    )
    return results


def check_uploads(conn: psycopg.Connection) -> list[Result]:
    """The API can't see or change upload keys or qualities, and sees only
    which published items have a ready original.

    These follow the Step 7B criteria in docs/step-07a-uploads-plan.md and
    the Step 8B criteria in docs/step-08a-playback-plan.md.
    """
    tables = ("public.upload_keys", "public.media_originals", "public.media_renditions")
    flags = conn.execute(
        """
        select count(*) = 3 and bool_and(relrowsecurity and relforcerowsecurity)
        from pg_class where oid = any(%s::regclass[])
        """,
        (list(tables),),
    ).fetchone()[0]
    results = [Result("RLS and forced RLS on the upload tables", flags)]
    rights = [
        table
        for table in ("public.upload_keys", "public.media_renditions")
        if conn.execute(
            "select has_table_privilege(%s, 'SELECT, INSERT, UPDATE, DELETE')",
            (table,),
        ).fetchone()[0]
        or conn.execute(
            "select has_any_column_privilege(%s, 'SELECT, INSERT, UPDATE')",
            (table,),
        ).fetchone()[0]
    ]
    results.append(
        Result(
            "can't read or change upload keys or qualities",
            not rights
            and refused(conn, "select count(*) from public.upload_keys")
            and refused(conn, "select count(*) from public.media_renditions")
            and refused(conn, "update public.upload_keys set used_at = now()"),
            ", ".join(rights),
        )
    )
    readable = {
        column
        for (column,) in conn.execute(
            """
            select attname from pg_attribute
            where attrelid = 'public.media_originals'::regclass and attnum > 0
              and not attisdropped
              and has_column_privilege(attrelid, attnum, 'SELECT')
            """
        ).fetchall()
    }
    changes = (
        conn.execute(
            "select has_table_privilege('public.media_originals', "
            "'INSERT, UPDATE, DELETE, TRUNCATE')"
        ).fetchone()[0]
        or conn.execute(
            "select has_any_column_privilege("
            "'public.media_originals', 'INSERT, UPDATE')"
        ).fetchone()[0]
    )
    results.append(
        Result(
            "reads only the ID, item and state of originals, and changes none",
            readable == {"id", "item_id", "state"} and not changes,
            ", ".join(sorted(readable)),
        )
    )
    hidden = conn.execute(
        """
        select count(*) from public.media_originals o
        where o.state <> 'ready'
           or not exists (select from public.items i where i.id = o.item_id)
        """
    ).fetchone()[0]
    results.append(
        Result(
            "sees ready originals of published, approved items only",
            hidden == 0,
            f"{hidden} others seen",
        )
    )
    return results


def check_no_leak(url: str, connect: Callable[[str], psycopg.Connection]) -> Result:
    """A user set in one transaction is gone in the next, including through
    the pooler and with two users at once."""
    failures: list[str] = []

    def worker(user_id: uuid.UUID) -> None:
        try:
            with connect(url) as conn:
                for _ in range(15):
                    with conn.transaction():
                        as_user(conn, user_id)
                        seen = conn.execute(
                            "select public.current_app_user_id()"
                        ).fetchone()[0]
                        if seen != user_id:
                            failures.append("saw another user")
                    with conn.transaction():
                        left = conn.execute(
                            "select public.current_app_user_id()"
                        ).fetchone()[0]
                        if left is not None:
                            failures.append("a user was left set")
        except psycopg.Error as error:
            failures.append(type(error).__name__)

    threads = [threading.Thread(target=worker, args=(uuid.uuid4(),)) for _ in range(4)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return Result(
        "app.user_id doesn't leak between transactions, with 4 at once",
        not failures,
        ", ".join(sorted(set(failures))),
    )


def check_prepared(conn: psycopg.Connection) -> Result:
    """psycopg prepares a query after 5 runs. That must work through the
    pooler, in separate transactions."""
    try:
        for _ in range(10):
            with conn.transaction():
                as_user(conn, uuid.uuid4())
                conn.execute(
                    "select count(*) from public.profiles where user_id = %s",
                    (uuid.uuid4(),),
                ).fetchone()
    except psycopg.Error as error:
        return Result("prepared statements work", False, type(error).__name__)
    return Result("prepared statements work", True)


def run_checks(url: str, connect=None) -> list[Result]:
    connect = connect or (lambda u: psycopg.connect(u, connect_timeout=15))
    results: list[Result] = []
    with connect(url) as conn:
        conn.autocommit = True
        tables = conn.execute(NEON_AUTH_TABLES).fetchone()[0]
        try:
            results.append(
                Result(
                    "on the branch with Neon Auth",
                    True,
                    require_sign_in_branch(url, tables),
                )
            )
        except UnsafeConnection as error:
            # Stop here: the other checks would be about the wrong database.
            return [Result("on the branch with Neon Auth", False, str(error))]
        results += check_role(conn)
        results += check_schema_rights(conn)
        results += check_table(conn)
        results += check_isolation(conn)
        results += check_catalogue(conn)
        results += check_uploads(conn)
        results += check_passes(conn)
        results += check_subscriptions(conn)
        results += check_account(conn)
        results.append(check_prepared(conn))
    results.append(check_no_leak(url, connect))
    return results


def main() -> int:
    url = database_url()
    host = urlsplit(url).hostname or ""
    print(f"Database host: {host}")
    if host.endswith(".neon.tech") and "-pooler" not in host:
        print("Warning: not the pooled address, so the pooler isn't being tested")
    try:
        results = run_checks(url)
    except psycopg.OperationalError as error:
        print(f"Couldn't connect: {type(error).__name__}", file=sys.stderr)
        return 1
    except psycopg.errors.UndefinedTable:
        print("A table doesn't exist: run the migrations first", file=sys.stderr)
        return 1
    for result in results:
        mark = "PASS" if result.passed else "FAIL"
        detail = f" ({result.detail})" if result.detail else ""
        print(f"{mark}  {result.name}{detail}")
    failed = sum(not result.passed for result in results)
    print(f"\n{len(results) - failed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
