"""Checks the migration connection before anything changes.

Migrations need the owner role over a direct connection. Neon's docs say
migrations need a direct connection, and the API's own role must not be able
to change the schema. On Neon, the database must also be the branch with Auth
enabled, which is the one that has a neon_auth schema.
"""

import os
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit

APP_ROLE = "veloraug_app"
ENV_FILE = Path(__file__).resolve().parent.parent / ".env"

# Run on the database itself. Readable by any role, without access to the
# schema's contents.
NEON_AUTH_TABLES = (
    "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace "
    "where n.nspname = 'neon_auth' and c.relkind = 'r'"
)

_URL = re.compile(r"postgres(?:ql)?(?:\+psycopg)?://[^\s'\"]+")


class UnsafeConnection(Exception):
    pass


def _setting(name: str) -> str:
    """From the environment, or else from services/api/.env."""
    value = os.environ.get(name, "").strip()
    if not value and ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith(f"{name}="):
                value = line.split("=", 1)[1].strip().strip('"').strip("'")
    return value


def clean(pasted: str) -> str:
    """The connection string inside what was pasted.

    The Neon Console can copy it wrapped in a psql command, with quotes.
    """
    found = _URL.search(pasted)
    if not found:
        raise UnsafeConnection("The connection string must start with postgresql://")
    return found.group(0)


def sqlalchemy_url(url: str) -> str:
    """Use the psycopg 3 driver, whichever form the Console gives."""
    if url.startswith("postgresql+psycopg://"):
        return url
    for prefix in ("postgresql://", "postgres://"):
        if url.startswith(prefix):
            return "postgresql+psycopg://" + url[len(prefix) :]
    raise UnsafeConnection("The connection string must start with postgresql://")


def is_neon(url: str) -> bool:
    return (urlsplit(url).hostname or "").endswith(".neon.tech")


def describe(url: str) -> str:
    """Refuse the wrong kind of connection, and say where this one goes.

    The description holds the host, database and user, never the password.
    """
    parts = urlsplit(url)
    if parts.scheme not in ("postgresql", "postgres", "postgresql+psycopg"):
        raise UnsafeConnection("The connection string must start with postgresql://")
    host = parts.hostname
    if not host:
        raise UnsafeConnection("The connection string has no host")
    if "-pooler" in host:
        raise UnsafeConnection(
            f"{host} is a pooled address. Migrations need the direct one: "
            "in the Neon Console, Connect, turn connection pooling off"
        )
    user = unquote(parts.username or "")
    if user == APP_ROLE:
        raise UnsafeConnection(
            f"{APP_ROLE} can't change the schema. Use the owner role, such as "
            "neondb_owner"
        )
    database = parts.path.lstrip("/") or "(default)"
    return f"host {host}, database {database}, as {user or '(default user)'}"


def _endpoint(host: str) -> str:
    """ep-name-123 from a Neon database, pooler or Auth host."""
    return host.split(".", 1)[0].removesuffix("-pooler")


def sign_in_database_host() -> str | None:
    """The database host of the branch the API's sign-in uses.

    A branch's Auth URL is its database host with `.neonauth` added, for
    example ep-name-123.neonauth.c-7.eu-central-1.aws.neon.tech.
    """
    host = urlsplit(_setting("VELORAUG_NEON_AUTH_URL")).hostname or ""
    if ".neonauth." not in host:
        return None
    return host.replace(".neonauth.", ".", 1)


def require_sign_in_branch(url: str, neon_auth_tables: int) -> str:
    """Refuse a Neon database that isn't the branch the API's sign-in uses.

    Two checks, because each alone has let the wrong database through or
    refused the right one: the host must match VELORAUG_NEON_AUTH_URL, which
    rules out other projects and branches, and the database must hold Neon
    Auth's tables. Local databases aren't checked.
    """
    if not is_neon(url):
        return "local database, branch not checked"
    host = urlsplit(url).hostname or ""
    expected = sign_in_database_host()
    if expected is None:
        raise UnsafeConnection(
            "Can't tell which Neon branch is right: VELORAUG_NEON_AUTH_URL "
            "isn't set in services/api/.env"
        )
    if (
        _endpoint(host) != _endpoint(expected)
        or host.split(".", 1)[1] != (expected.split(".", 1)[1])
    ):
        raise UnsafeConnection(
            f"This database is {host}, but sign-in uses the branch whose "
            f"database is {expected}. In the Neon Console, open that project "
            "and its development branch, and copy the string from there"
        )
    if neon_auth_tables == 0:
        raise UnsafeConnection(
            "This database has no neon_auth schema, so it isn't the branch "
            "with Auth enabled"
        )
    return (
        f"matches sign-in ({_endpoint(host)}), and Neon Auth found "
        f"({neon_auth_tables} tables)"
    )
