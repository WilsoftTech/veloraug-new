"""Read-only checks before running migration 0007 on a hosted database.

Run from services/api, after making the backup branch the runbook asks
for, with the owner connection string pasted when asked (never in a
message):

    .\\.venv\\Scripts\\python.exe scripts\\preflight_0007.py

It changes nothing: every query runs in a read-only transaction that is
rolled back. It prints counts only, never an email, a phone number or an
ID. Each check says PASS or FAIL; migrate only when all pass. See
docs/step-10e-runbook.md, "Migration 0007".
"""

import getpass
import os
import sys
from pathlib import Path

import psycopg

API_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(API_DIR))

from migrations.connection import (  # noqa: E402
    NEON_AUTH_TABLES,
    UnsafeConnection,
    clean,
    describe,
    require_sign_in_branch,
)

LEGACY = ("day", "week", "month")


def checks(conn: psycopg.Connection) -> list[tuple[str, bool, str]]:
    results = []

    def add(name: str, passed: bool, detail: str = "") -> None:
        results.append((name, passed, detail))

    (revision,) = conn.execute(
        "select version_num from public.alembic_version"
    ).fetchone()
    add("the database is at 0006", revision == "0006", f"at {revision}")

    (constraint,) = conn.execute(
        """
        select count(*) from pg_constraint
        where conrelid = 'public.pass_plans'::regclass
          and conname = 'pass_plans_id_check'
        """
    ).fetchone()
    add("pass_plans_id_check exists, as 0007 replaces it", constraint == 1)

    plans = {
        row[0] for row in conn.execute("select id from public.pass_plans").fetchall()
    }
    add(
        "only the three legacy passes exist",
        plans == set(LEGACY),
        ", ".join(sorted(plans - set(LEGACY))),
    )

    (unknown,) = conn.execute(
        "select count(*) from public.payments where plan_id <> all(%s)",
        (list(LEGACY),),
    ).fetchone()
    add("every payment is for a legacy pass", unknown == 0, f"{unknown} not")

    (orphans,) = conn.execute(
        """
        select count(*) from public.passes s
        left join public.payments p on p.id = s.payment_id where p.id is null
        """
    ).fetchone()
    add("every pass has its payment", orphans == 0, f"{orphans} without")

    for table in ("devices", "playback_sessions", "plan_changes"):
        (exists,) = conn.execute(
            "select to_regclass(%s) is not null", (f"public.{table}",)
        ).fetchone()
        add(f"public.{table} doesn't exist yet", not exists)

    for role in ("veloraug_app", "veloraug_editor"):
        (found,) = conn.execute(
            "select count(*) from pg_roles where rolname = %s", (role,)
        ).fetchone()
        add(f"role {role} exists", found == 1)

    counts = conn.execute(
        """
        select (select count(*) from public.payments),
               (select count(*) from public.passes),
               (select count(*) from public.payments where state = 'completed')
        """
    ).fetchone()
    add(
        "counts to compare after migrating",
        True,
        f"{counts[0]} payments, {counts[1]} passes, {counts[2]} completed",
    )
    return results


def owner_url() -> str:
    """As migrations/env.py asks for it: the environment, or a hidden paste."""
    url = os.environ.get("VELORAUG_MIGRATION_DATABASE_URL", "").strip()
    if not url:
        url = getpass.getpass(
            "Owner connection string, direct (not pooled). Hidden as you paste: "
        )
    return clean(url)


def main() -> int:
    try:
        url = owner_url()
        print(f"Database: {describe(url)}")
    except UnsafeConnection as error:
        print(f"Refused: {error}", file=sys.stderr)
        return 2
    with psycopg.connect(url, connect_timeout=15) as conn:
        tables = conn.execute(NEON_AUTH_TABLES).fetchone()[0]
        try:
            require_sign_in_branch(url, tables)
        except UnsafeConnection as error:
            print(f"Refused: {error}", file=sys.stderr)
            return 2
        conn.execute("set transaction read only")
        try:
            results = checks(conn)
        finally:
            conn.rollback()
    for name, passed, detail in results:
        print(
            f"{'PASS' if passed else 'FAIL'}  {name}"
            + (f" ({detail})" if detail else "")
        )
    failed = sum(not passed for _, passed, _ in results)
    print(f"\n{len(results) - failed} passed, {failed} failed")
    if failed:
        print("Don't migrate. Send back what failed.")
        return 1
    print(
        "Ready. Check the backup branch is listed in the Neon Console, then run: "
        "python -m alembic upgrade 0007"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
