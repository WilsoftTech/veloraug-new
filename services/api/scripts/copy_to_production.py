"""Copies published films from development to production, Step 11F.

Decision 12 of docs/step-11a-pilot-deployment-plan.md: rather than uploading
and converting each film again, this copies a published edition's rows to
production with the same IDs, and its files inside R2, from veloraug-dev to
veloraug, without downloading them.

Run by the owner, from services/api, with both owner connections set in the
terminal only, never in a file:

    $env:VELORAUG_COPY_FROM_DATABASE_URL = "<development owner, direct>"
    $env:VELORAUG_COPY_TO_DATABASE_URL = "<production owner, direct>"
    .\\.venv\\Scripts\\python.exe scripts\\copy_to_production.py
    .\\.venv\\Scripts\\python.exe scripts\\copy_to_production.py --apply

Without --apply it only lists what it would copy. R2's endpoint and keys come
from services/api/.env.r2, as for check_r2.py; the keys must be able to read
the development bucket and write the production one.

For each published edition that isn't a test and isn't on production yet:
1. its files are copied: each playable item's quality folder
   movies/<item>/<original>/, the edition's poster and the VJ's photo;
2. every copied file's size is checked in the production bucket;
3. its rows go to production in one transaction: language, VJ, source,
   edition, the playable items, and each one's upload key (already used),
   ready original and qualities.

An edition already on production is skipped, so running it again copies
nothing twice. If a run stops between the files and the rows, the next run
copies only the files that aren't there whole, and then the rows.
"""

import argparse
import os
import sys
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import urlsplit

import psycopg
from psycopg import sql
from psycopg.rows import dict_row

API_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(API_DIR))

from migrations.connection import UnsafeConnection, clean, describe  # noqa: E402

FROM_URL = "VELORAUG_COPY_FROM_DATABASE_URL"
TO_URL = "VELORAUG_COPY_TO_DATABASE_URL"
# R2 copies one object of up to 5 GB in one request. Qualities' segments are
# a few MB each; anything bigger means something unexpected is in the folder.
MAX_COPY_BYTES = 5 * 1024**3
# botocore keeps 10 connections per client, so no more at once than that.
COPY_WORKERS = 10


class CopyError(Exception):
    pass


class Files(Protocol):
    def list(self, bucket: str, prefix: str) -> dict[str, int]:
        """Every object under the prefix, with its size."""
        ...

    def copy(self, from_bucket: str, to_bucket: str, key: str) -> None: ...


class R2Files:
    """Both buckets, through one set of R2 keys."""

    def __init__(self, client: Any) -> None:
        self.client = client

    def list(self, bucket: str, prefix: str) -> dict[str, int]:
        found: dict[str, int] = {}
        pages = self.client.get_paginator("list_objects_v2").paginate(
            Bucket=bucket, Prefix=prefix
        )
        for page in pages:
            for item in page.get("Contents", []):
                found[item["Key"]] = item["Size"]
        return found

    def copy(self, from_bucket: str, to_bucket: str, key: str) -> None:
        # Content type and cache control are copied with the object.
        self.client.copy_object(
            Bucket=to_bucket,
            Key=key,
            CopySource={"Bucket": from_bucket, "Key": key},
            MetadataDirective="COPY",
        )


@dataclass
class Edition:
    """One edition's rows, as found on development."""

    edition: dict[str, Any]
    language: dict[str, Any]
    vj: dict[str, Any]
    source: dict[str, Any]
    items: list[dict[str, Any]] = field(default_factory=list)
    keys: list[dict[str, Any]] = field(default_factory=list)
    originals: list[dict[str, Any]] = field(default_factory=list)
    renditions: list[dict[str, Any]] = field(default_factory=list)
    skipped_items: int = 0

    @property
    def title(self) -> str:
        return self.edition["display_title"]

    def folders(self) -> list[str]:
        return [f"movies/{o['item_id']}/{o['id']}/" for o in self.originals]

    def images(self) -> list[str]:
        """The poster and VJ photo, when they are ours in R2. A TMDB poster's
        path starts with / and isn't copied."""
        paths = [self.edition.get("poster_path"), self.vj.get("photo_path")]
        return [p for p in paths if p and p.startswith(("posters/", "vjs/"))]


@dataclass
class Report:
    copied: list[str] = field(default_factory=list)
    already: list[str] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)
    files: int = 0
    bytes: int = 0


def connection_url(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise UnsafeConnection(
            f"Set {name} in this terminal first. It is never read from a file"
        )
    return clean(value)


def check_pair(from_url: str, to_url: str) -> tuple[str, str]:
    """Descriptions of both, refusing the same database twice."""
    a, b = describe(from_url), describe(to_url)
    same_host = urlsplit(from_url).hostname == urlsplit(to_url).hostname
    same_db = urlsplit(from_url).path == urlsplit(to_url).path
    if same_host and same_db:
        raise UnsafeConnection(
            "Both connection strings name the same database. Production's is "
            "the default branch's, development's the development branch's"
        )
    return a, b


def revision(conn: psycopg.Connection) -> str:
    return conn.execute("select version_num from public.alembic_version").fetchone()[0]


def rows(conn, query: str, params=()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        return cur.execute(query, params).fetchall()


def one(conn, query: str, params=()) -> dict[str, Any]:
    found = rows(conn, query, params)
    if len(found) != 1:
        raise CopyError(f"expected one row, found {len(found)}: {query.split()[3]}")
    return found[0]


def published_editions(conn) -> list[dict[str, Any]]:
    return rows(
        conn,
        "select * from public.editions where status = 'published' and not test "
        "order by published_at, id",
    )


def gather(conn, edition: dict[str, Any]) -> Edition:
    """An edition's rows, with only its playable items: approved, with a
    ready original."""
    found = Edition(
        edition=edition,
        language=one(
            conn,
            "select * from public.languages where code = %s",
            (edition["language"],),
        ),
        vj=one(conn, "select * from public.vjs where id = %s", (edition["vj_id"],)),
        source=one(
            conn, "select * from public.sources where id = %s", (edition["source_id"],)
        ),
    )
    items = rows(
        conn,
        "select * from public.items where edition_id = %s order by season, episode",
        (edition["id"],),
    )
    for item in items:
        ready = rows(
            conn,
            "select * from public.media_originals where item_id = %s "
            "and state = 'ready'",
            (item["id"],),
        )
        if item["approved_at"] is None or not ready:
            found.skipped_items += 1
            continue
        original = ready[0]
        found.items.append(item)
        found.originals.append(original)
        found.keys.append(
            one(
                conn,
                "select * from public.upload_keys where id = %s",
                (original["upload_key_id"],),
            )
        )
        found.renditions.extend(
            rows(
                conn,
                "select * from public.media_renditions where original_id = %s "
                "order by height",
                (original["id"],),
            )
        )
    return found


def on_production(conn, edition_id) -> bool:
    return (
        conn.execute(
            "select 1 from public.editions where id = %s", (edition_id,)
        ).fetchone()
        is not None
    )


def insert(conn, table: str, row: dict[str, Any], *, shared: bool = False) -> None:
    """Inserts a row as it is, with its ID. A shared row (a language, VJ or
    source that other editions use) may already be there; it must then be
    there under the same key."""
    columns = list(row)
    statement = sql.SQL("insert into public.{} ({}) values ({})").format(
        sql.Identifier(table),
        sql.SQL(", ").join(map(sql.Identifier, columns)),
        sql.SQL(", ").join(sql.Placeholder() * len(columns)),
    )
    if shared:
        statement += sql.SQL(" on conflict do nothing")
    conn.execute(statement, [row[c] for c in columns])
    if shared:
        key = "code" if table == "languages" else "id"
        there = conn.execute(
            sql.SQL("select 1 from public.{} where {} = %s").format(
                sql.Identifier(table), sql.Identifier(key)
            ),
            (row[key],),
        ).fetchone()
        if there is None:
            raise CopyError(
                f"production already has a different row in {table} for "
                f"{row.get('name') or row.get('title') or row[key]}: the same "
                "name, slug or TMDB ID under another ID. Fix it there first"
            )


def copy_rows(conn, found: Edition) -> None:
    insert(conn, "languages", found.language, shared=True)
    insert(conn, "vjs", found.vj, shared=True)
    insert(conn, "sources", found.source, shared=True)
    insert(conn, "editions", found.edition)
    for item in found.items:
        insert(conn, "items", item)
    for key in found.keys:
        insert(conn, "upload_keys", key)
    for original in found.originals:
        insert(conn, "media_originals", original)
    for rendition in found.renditions:
        insert(conn, "media_renditions", rendition)


def copy_files(
    files: Files,
    from_bucket: str,
    to_bucket: str,
    found: Edition,
    say: Callable[[str], None] = print,
) -> tuple[int, int]:
    """Copies the edition's files, then checks each one's size on
    production. The number of files, and their bytes."""
    wanted: dict[str, int] = {}
    for folder in found.folders():
        listed = files.list(from_bucket, folder)
        if folder + "master.m3u8" not in listed:
            raise CopyError(f"{folder}master.m3u8 isn't in {from_bucket}")
        wanted.update(listed)
    for image in found.images():
        listed = files.list(from_bucket, image)
        if image not in listed:
            raise CopyError(f"{image} isn't in {from_bucket}")
        wanted[image] = listed[image]
    too_big = [k for k, size in wanted.items() if size > MAX_COPY_BYTES]
    if too_big:
        raise CopyError(f"{too_big[0]} is over 5 GB, which this can't copy")

    def on_production() -> dict[str, int]:
        there: dict[str, int] = {}
        for prefix in found.folders() + found.images():
            there.update(files.list(to_bucket, prefix))
        return there

    # Files left by a stopped run, whole, aren't copied again.
    there = on_production()
    todo = sorted(k for k, size in wanted.items() if there.get(k) != size)
    say(
        f"copying {found.title}: {len(todo)} of {len(wanted)} files, "
        f"{sum(wanted[k] for k in todo) / 1024**3:.2f} GB"
    )
    # R2 copies each file itself; several at once save the round trips.
    with ThreadPoolExecutor(max_workers=COPY_WORKERS) as pool:
        for future in [
            pool.submit(files.copy, from_bucket, to_bucket, key) for key in todo
        ]:
            future.result()
    copied = on_production()
    wrong = [k for k, size in wanted.items() if copied.get(k) != size]
    if wrong:
        raise CopyError(
            f"{len(wrong)} file(s) didn't arrive whole in {to_bucket}, such as "
            f"{wrong[0]}. Nothing was added to production's database"
        )
    return len(wanted), sum(wanted.values())


def copy_to_production(
    source: psycopg.Connection,
    target: psycopg.Connection,
    files: Files,
    *,
    from_bucket: str,
    to_bucket: str,
    apply: bool,
    say: Callable[[str], None] = print,
) -> Report:
    if from_bucket == to_bucket:
        raise CopyError("the two buckets must differ")
    if revision(source) != revision(target):
        raise CopyError(
            f"development is at migration {revision(source)} and production at "
            f"{revision(target)}. Migrate production first"
        )
    report = Report()
    for edition in published_editions(source):
        found = gather(source, edition)
        name = f"{found.title} ({edition['id']})"
        if on_production(target, edition["id"]):
            report.already.append(name)
            continue
        if not found.items:
            report.skipped.append(f"{name}: no approved item with a ready original")
            continue
        if not apply:
            extra = (
                f", {found.skipped_items} item(s) not ready"
                if found.skipped_items
                else ""
            )
            say(f"would copy {name}: {len(found.items)} item(s){extra}")
            report.copied.append(name)
            continue
        count, size = copy_files(files, from_bucket, to_bucket, found, say)
        with target.transaction():
            copy_rows(target, found)
        report.copied.append(name)
        report.files += count
        report.bytes += size
        say(f"copied {name}: {count} files, {size / 1024**3:.2f} GB")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--apply", action="store_true", help="copy, not just list")
    parser.add_argument("--from-bucket", default="veloraug-dev")
    parser.add_argument("--to-bucket", default="veloraug")
    args = parser.parse_args()

    try:
        from_url, to_url = connection_url(FROM_URL), connection_url(TO_URL)
        from_text, to_text = check_pair(from_url, to_url)
    except UnsafeConnection as error:
        print(f"Refused: {error}")
        return 1
    print(f"From development: {from_text}, bucket {args.from_bucket}")
    print(f"To production:    {to_text}, bucket {args.to_bucket}")

    files: Files | None = None
    if args.apply:
        from pydantic import ValidationError

        from app.media_publisher import R2Settings, R2Store
        from scripts.check_r2 import load_env_file

        load_env_file()
        try:
            settings = R2Settings(bucket=args.to_bucket)
        except ValidationError as error:
            print(f"R2 isn't set up in .env.r2: {error.errors()[0]['msg']}")
            return 1
        if not settings.configured:
            print("R2 isn't set up: fill in services/api/.env.r2")
            return 1
        files = R2Files(R2Store(settings).client)

    with (
        psycopg.connect(from_url, autocommit=True) as source,
        psycopg.connect(to_url, autocommit=True) as target,
    ):
        # Autocommit, so no transaction stays open on development while a
        # film's files copy for minutes: Neon ends a connection left idle in
        # a transaction for 5 minutes. Every statement is still read-only.
        source.execute("set default_transaction_read_only = on")
        try:
            report = copy_to_production(
                source,
                target,
                files,  # type: ignore[arg-type]
                from_bucket=args.from_bucket,
                to_bucket=args.to_bucket,
                apply=args.apply,
            )
        except CopyError as error:
            print(f"Stopped: {error}")
            return 1

    for name in report.already:
        print(f"already on production: {name}")
    for line in report.skipped:
        print(f"skipped {line}")
    verb = "Copied" if args.apply else "Would copy"
    print(
        f"{verb} {len(report.copied)} edition(s); {len(report.already)} already "
        f"there; {len(report.skipped)} skipped."
    )
    if args.apply:
        print(f"{report.files} files, {report.bytes / 1024**3:.2f} GB.")
    else:
        print("Nothing was changed. Run again with --apply to copy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
