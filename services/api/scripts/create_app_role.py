"""Creates the API's database role, veloraug_app, or gives it a new password.
With --role media, gives the upload hooks' and worker's role, veloraug_media,
a login and a new password instead.

Run by the project owner, from services/api:

    .\\.venv\\Scripts\\python.exe scripts\\create_app_role.py
    .\\.venv\\Scripts\\python.exe scripts\\create_app_role.py --role media

It asks for the owner's direct connection string, hidden, unless
VELORAUG_MIGRATION_DATABASE_URL is set. It then:

1. generates a long random password for veloraug_app,
2. creates the role, or changes its password. Neon accepts only a plain
   password here, over the TLS connection. A local database gets only a
   SCRAM hash,
3. checks, after the commit, that the role has no special rights, and
   removes it again if it has, and
4. writes the role's pooled connection string to services/api/.env, as
   VELORAUG_DATABASE_URL. For veloraug_media, to services/api/.env.media, as
   VELORAUG_MEDIA_DATABASE_URL, so the API's container never holds it.

Nothing secret is printed. Running it again changes the password and updates
.env, so a lost password is fixed by running it again.
"""

import argparse
import base64
import getpass
import hashlib
import hmac
import os
import secrets
import sys
from pathlib import Path
from urllib.parse import quote, urlsplit, urlunsplit

import psycopg
from psycopg import sql

API_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(API_DIR))

from migrations.connection import (  # noqa: E402
    APP_ROLE,
    NEON_AUTH_TABLES,
    UnsafeConnection,
    clean,
    describe,
    is_neon,
    require_sign_in_branch,
)

ENV_FILE = API_DIR / ".env"
ENV_NAME = "VELORAUG_DATABASE_URL"
MEDIA_ROLE = "veloraug_media"
MEDIA_ENV_FILE = API_DIR / ".env.media"
MEDIA_ENV_NAME = "VELORAUG_MEDIA_DATABASE_URL"
# role option: (role, .env file, variable)
ROLES = {
    "app": (APP_ROLE, ENV_FILE, ENV_NAME),
    "media": (MEDIA_ROLE, MEDIA_ENV_FILE, MEDIA_ENV_NAME),
}
CONNECTION_LIMIT = 20
SCRAM_ITERATIONS = 4096


def scram_verifier(password: str, salt: bytes | None = None) -> str:
    """The SCRAM-SHA-256 hash Postgres stores, so the password never reaches it.

    The format is Postgres's own: SCRAM-SHA-256$<iterations>:<salt>$<stored
    key>:<server key>. Postgres recognises it and stores it as given.
    """
    salt = salt or secrets.token_bytes(16)
    salted = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, SCRAM_ITERATIONS)
    client_key = hmac.digest(salted, b"Client Key", "sha256")
    stored_key = hashlib.sha256(client_key).digest()
    server_key = hmac.digest(salted, b"Server Key", "sha256")

    def b64(data: bytes) -> str:
        return base64.b64encode(data).decode()

    return (
        f"SCRAM-SHA-256${SCRAM_ITERATIONS}:{b64(salt)}"
        f"${b64(stored_key)}:{b64(server_key)}"
    )


def ensure_app_role(
    conn: psycopg.Connection,
    password: str,
    *,
    plain: bool = False,
    role: str = APP_ROLE,
) -> bool:
    """Creates the role, or changes its password. True if it was created.

    Neon's control plane refuses a hash ("Neon only supports being given
    plaintext passwords"), so `plain` sends the password itself.
    """
    verifier = sql.Literal(password if plain else scram_verifier(password))
    exists = conn.execute(
        "select 1 from pg_roles where rolname = %s", (role,)
    ).fetchone()
    if exists:
        conn.execute(
            sql.SQL("alter role {} with login password {}").format(
                sql.Identifier(role), verifier
            )
        )
        return False
    conn.execute(
        sql.SQL(
            "create role {} with login nosuperuser nocreatedb nocreaterole "
            "noinherit noreplication nobypassrls connection limit {} password {}"
        ).format(sql.Identifier(role), sql.Literal(CONNECTION_LIMIT), verifier)
    )
    return True


def role_problems(conn: psycopg.Connection, role: str = APP_ROLE) -> list[str]:
    """Anything that would let the role get round row-level security."""
    row = conn.execute(
        """
        select rolsuper, rolbypassrls, rolcreaterole, rolcreatedb, rolreplication
        from pg_roles where rolname = %s
        """,
        (role,),
    ).fetchone()
    if row is None:
        return ["the role doesn't exist"]
    names = ["superuser", "bypass RLS", "create roles", "create databases"]
    names.append("replication")
    problems = [
        f"it can {name}" for name, value in zip(names, row, strict=True) if value
    ]
    memberships = conn.execute(
        """
        select r.rolname from pg_auth_members m
        join pg_roles r on r.oid = m.roleid
        join pg_roles a on a.oid = m.member
        where a.rolname = %s
        """,
        (role,),
    ).fetchall()
    problems += [f"it is a member of {name}" for (name,) in memberships]
    return problems


def app_database_url(owner_url: str, password: str, role: str = APP_ROLE) -> str:
    """The same database, as the role, through Neon's connection pooler."""
    parts = urlsplit(owner_url)
    host = parts.hostname or ""
    if host.endswith(".neon.tech") and "-pooler" not in host:
        endpoint, _, rest = host.partition(".")
        host = f"{endpoint}-pooler.{rest}"
    netloc = f"{role}:{quote(password, safe='')}@{host}"
    if parts.port:
        netloc += f":{parts.port}"
    scheme = "postgresql" if parts.scheme == "postgres" else parts.scheme
    return urlunsplit((scheme, netloc, parts.path, parts.query, ""))


def write_env(path: Path, url: str, name: str = ENV_NAME) -> None:
    """Sets the variable in the .env file, keeping every other line."""
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    entry = f"{name}={url}"
    replaced = False
    for index, line in enumerate(lines):
        if line.strip().startswith(f"{name}="):
            lines[index] = entry
            replaced = True
    if not replaced:
        lines.append(entry)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create or update veloraug_app, or veloraug_media."
    )
    parser.add_argument("--role", choices=sorted(ROLES), default="app")
    parser.add_argument("--env-file", type=Path)
    args = parser.parse_args()
    role, default_env_file, env_name = ROLES[args.role]
    env_file = args.env_file or default_env_file
    owner_url = os.environ.get("VELORAUG_MIGRATION_DATABASE_URL", "").strip()
    if not owner_url:
        owner_url = getpass.getpass(
            "Owner connection string, direct (not pooled). Hidden as you paste: "
        )
    try:
        owner_url = clean(owner_url)
        print(f"Database: {describe(owner_url)}")
    except UnsafeConnection as error:
        print(f"Refused: {error}", file=sys.stderr)
        return 1

    password = secrets.token_urlsafe(32)
    try:
        with psycopg.connect(owner_url, connect_timeout=15) as conn:
            tables = conn.execute(NEON_AUTH_TABLES).fetchone()[0]
            try:
                print(f"Branch: {require_sign_in_branch(owner_url, tables)}")
            except UnsafeConnection as error:
                print(f"Refused: {error}", file=sys.stderr)
                return 1
            # PowerShell can put a byte-order mark before piped text.
            if (
                role == MEDIA_ROLE
                and not conn.execute(
                    "select 1 from pg_roles where rolname = %s", (role,)
                ).fetchone()
            ):
                print(
                    f"Refused: {role} doesn't exist here. Run the migration first.",
                    file=sys.stderr,
                )
                return 1
            answer = input(f"Create or update {role} here? Type yes: ")
            if answer.strip().lstrip("\ufeff").lower() != "yes":
                conn.rollback()
                print("Nothing changed.")
                return 1
            created = ensure_app_role(
                conn, password, plain=is_neon(owner_url), role=role
            )
            # Checked after the commit, because Neon applies role changes then.
            conn.commit()
            problems = role_problems(conn, role)
            if problems:
                if created:
                    conn.execute(sql.SQL("drop role {}").format(sql.Identifier(role)))
                    conn.commit()
                print(
                    f"Stopped: {', '.join(problems)}. "
                    + ("The role was removed again." if created else ""),
                    file=sys.stderr,
                )
                return 1
    except psycopg.Error as error:
        # Postgres and Neon messages don't repeat the statement, so this
        # can't show the password.
        print(
            f"Failed, nothing saved: {type(error).__name__}: {error}", file=sys.stderr
        )
        return 1
    write_env(env_file, app_database_url(owner_url, password, role), env_name)

    print(f"{role} {'created' if created else 'has a new password'}.")
    print(f"Its pooled connection string is saved in {env_file}, as {env_name}.")
    print("The password wasn't shown. Run this again if it's ever lost.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
