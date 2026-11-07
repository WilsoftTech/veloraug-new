"""The API's database connections, as veloraug_app.

Every request that touches user data runs in one transaction, with the user's
ID set for that transaction only, so row-level security applies. Neon's pooler
runs in transaction mode, so a setting that outlived the transaction couldn't
be trusted.
"""

import logging
from collections.abc import Iterator
from contextlib import contextmanager
from uuid import UUID

import psycopg
from psycopg_pool import ConnectionPool

# A database that has scaled to zero takes a moment to wake. Past these
# limits the request gets 503 rather than hanging.
CONNECT_TIMEOUT_SECONDS = 10
POOL_WAIT_SECONDS = 15

logger = logging.getLogger("veloraug.db")


class DatabaseUnavailable(Exception):
    """The database couldn't be reached. The message is the error type only."""


class Database:
    def __init__(
        self,
        url: str,
        *,
        max_size: int = 5,
        wait_seconds: float = POOL_WAIT_SECONDS,
    ) -> None:
        self._pool = ConnectionPool(
            url,
            min_size=0,
            max_size=max_size,
            open=False,
            timeout=wait_seconds,
            # Neon closes idle connections when it scales to zero. Checking
            # each one before use replaces a dead one instead of failing.
            check=ConnectionPool.check_connection,
            max_idle=240,
            kwargs={"connect_timeout": CONNECT_TIMEOUT_SECONDS},
            name="veloraug",
        )

    def open(self) -> None:
        # Doesn't wait for a connection, so the API starts even while the
        # database is asleep or unreachable.
        self._pool.open(wait=False)

    def close(self) -> None:
        self._pool.close()

    @contextmanager
    def as_user(self, user_id: UUID) -> Iterator[psycopg.Connection]:
        """A connection in a transaction that acts for this user only."""
        try:
            with self._pool.connection() as conn, conn.transaction():
                conn.execute(
                    "select set_config('app.user_id', %s, true)", (str(user_id),)
                )
                yield conn
        except psycopg.OperationalError as error:
            # Includes the pool's own timeout. Only the type is kept: a
            # driver message can name the host or user.
            raise DatabaseUnavailable(type(error).__name__) from None
