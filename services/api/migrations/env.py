"""Runs the migrations in versions/.

The owner's direct connection string comes from
VELORAUG_MIGRATION_DATABASE_URL, or is asked for, hidden, when that isn't set.
It is never printed or saved. `alembic upgrade head --sql` needs no
connection.
"""

import getpass
import os
import sys
from logging.config import fileConfig

from alembic import context
from sqlalchemy import create_engine, pool

from migrations.connection import (
    NEON_AUTH_TABLES,
    UnsafeConnection,
    clean,
    describe,
    require_sign_in_branch,
    sqlalchemy_url,
)

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name, disable_existing_loggers=False)


def owner_url() -> str:
    url = os.environ.get("VELORAUG_MIGRATION_DATABASE_URL", "").strip()
    if not url:
        url = getpass.getpass(
            "Owner connection string, direct (not pooled). Hidden as you paste: "
        )
    try:
        url = clean(url)
        where = describe(url)
    except UnsafeConnection as error:
        sys.exit(f"Refused: {error}")
    print(f"Database: {where}", file=sys.stderr)
    return url


def run_offline() -> None:
    context.configure(
        dialect_name="postgresql",
        literal_binds=True,
        transactional_ddl=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_online() -> None:
    url = owner_url()
    engine = create_engine(
        sqlalchemy_url(url),
        poolclass=pool.NullPool,
        connect_args={"connect_timeout": 15},
    )
    with engine.connect() as connection:
        # Checked before anything changes. The rollback ends the read.
        tables = connection.exec_driver_sql(NEON_AUTH_TABLES).scalar()
        connection.rollback()
        try:
            print(f"Branch: {require_sign_in_branch(url, tables)}", file=sys.stderr)
        except UnsafeConnection as error:
            sys.exit(f"Refused: {error}")
        # One transaction for the whole run: a failure leaves no change.
        context.configure(connection=connection, transactional_ddl=True)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_offline()
else:
    run_online()
