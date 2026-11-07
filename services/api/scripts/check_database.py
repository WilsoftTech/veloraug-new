"""Checks the database as the API's own role, veloraug_app.

Run from services/api after the migration:

    .\\.venv\\Scripts\\python.exe scripts\\check_database.py

It reads VELORAUG_DATABASE_URL from the environment, or from
services/api/.env, and prints only the host. Every test that writes runs in a
transaction that is rolled back, with random user IDs, so it leaves nothing
behind. The checks follow the Step 5F criteria in docs/step-05a-neon-plan.md.
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
        "DELETE": False,
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
        results.append(
            Result(
                "delete is refused",
                refused(conn, "delete from public.profiles where user_id = %s", (a,)),
            )
        )

        as_user(conn, b)
        name = conn.execute(
            "select display_name from public.profiles where user_id = %s", (b,)
        ).fetchone()
        results.append(Result("B's row unchanged, seen as B", name == ("B",)))
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
        print("public.profiles doesn't exist: run the migration first", file=sys.stderr)
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
