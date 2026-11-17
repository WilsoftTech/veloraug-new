"""Checks the database as the upload hooks' and worker's role, veloraug_media.

Run by the project owner, from services/api, after
`create_app_role.py --role media`:

    .\\.venv\\Scripts\\python.exe scripts\\check_media_role.py

It connects with VELORAUG_MEDIA_DATABASE_URL, from the environment or
services/api/.env.media, and asks for nothing. Everything it tries is rolled
back, so it changes nothing. See docs/step-07a-uploads-plan.md.
"""

import os
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

import psycopg

API_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(API_DIR))

from migrations.connection import NEON_AUTH_TABLES, require_sign_in_branch  # noqa: E402
from scripts.check_database import Result, refused  # noqa: E402

MEDIA_ROLE = "veloraug_media"
ENV_FILE = API_DIR / ".env.media"
ENV_NAME = "VELORAUG_MEDIA_DATABASE_URL"

# Each must fail with a permission or policy error.
REFUSED = {
    "can't make upload keys": (
        "insert into public.upload_keys (item_id, key_hash, label, expires_at) "
        "select item_id, sha256('x'::bytea), 'x', now() + interval '1 day' "
        "from public.media_originals limit 1"
    ),
    "can't revoke or relabel keys": "update public.upload_keys set label = 'x'",
    "can't read who a key is for": "select label from public.upload_keys",
    "can't delete keys": "delete from public.upload_keys",
    "can't delete originals": "delete from public.media_originals",
    "can't read editions": "select count(*) from public.editions",
    "can't publish editions": "update public.editions set status = 'published'",
    "can't read source details": "select count(*) from public.sources",
    "can't read admins": "select count(*) from public.admins",
    "can't read profiles": "select count(*) from public.profiles",
    "can't change the schema": "create table public.veloraug_check (id int)",
}


def media_url() -> str:
    url = os.environ.get(ENV_NAME, "").strip()
    if not url and ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith(f"{ENV_NAME}="):
                url = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not url:
        sys.exit(f"{ENV_NAME} isn't set. Run create_app_role.py --role media first.")
    if unquote(urlsplit(url).username or "") != MEDIA_ROLE:
        sys.exit(f"Refused: {ENV_NAME} must use {MEDIA_ROLE}.")
    return url


def run_checks(url: str) -> list[Result]:
    with psycopg.connect(url, connect_timeout=15) as conn:
        conn.autocommit = True
        tables = conn.execute(NEON_AUTH_TABLES).fetchone()[0]
        results = [
            Result(
                "on the branch with Neon Auth",
                True,
                require_sign_in_branch(url, tables),
            )
        ]
        who, special = conn.execute(
            """
            select current_user, rolsuper or rolbypassrls or rolcreaterole
                   or rolcreatedb or rolreplication
            from pg_roles where rolname = current_user
            """
        ).fetchone()
        results.append(Result(f"connected as {MEDIA_ROLE}", who == MEDIA_ROLE, who))
        results.append(Result("no special rights", not special))
        claim_needs_valid_key = (
            conn.execute(
                """
                select count(*) from pg_policies
                where tablename = 'upload_keys' and policyname = 'keys_media_claim'
                """
            ).fetchone()[0]
            == 1
        )
        results.append(
            Result("keys can be used only once, while valid", claim_needs_valid_key)
        )
        for name, statement in REFUSED.items():
            results.append(Result(name, refused(conn, statement)))
    return results


def main() -> int:
    url = media_url()
    print(f"Database host: {urlsplit(url).hostname}")
    results = run_checks(url)
    for result in results:
        detail = f" ({result.detail})" if result.detail else ""
        print(f"{'PASS' if result.passed else 'FAIL'}  {result.name}{detail}")
    failed = sum(not result.passed for result in results)
    print(f"\n{len(results) - failed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
