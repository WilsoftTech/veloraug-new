"""Profile reads and writes. Each runs inside Database.as_user, so row-level
security applies, and each also filters on the user's ID."""

from dataclasses import dataclass
from uuid import UUID

import psycopg


@dataclass(frozen=True)
class Profile:
    user_id: UUID
    display_name: str | None


def get_or_create(conn: psycopg.Connection, user_id: UUID) -> Profile:
    # Concurrent first requests both reach this. The primary key means only
    # one row is created, and the other insert does nothing.
    conn.execute(
        """
        insert into public.profiles (user_id) values (%s)
        on conflict (user_id) do nothing
        """,
        (user_id,),
    )
    row = conn.execute(
        "select user_id, display_name from public.profiles where user_id = %s",
        (user_id,),
    ).fetchone()
    return Profile(*row)


def set_display_name(
    conn: psycopg.Connection, user_id: UUID, display_name: str | None
) -> Profile:
    get_or_create(conn, user_id)
    row = conn.execute(
        """
        update public.profiles set display_name = %s where user_id = %s
        returning user_id, display_name
        """,
        (display_name, user_id),
    ).fetchone()
    return Profile(*row)
