"""Step 12A: makes download.mp4 for films published before downloads.

Since Step 12A the media worker joins each quality into one download.mp4
when it converts. Films published before then have only their chunks in
R2. This makes their files: for each ready original, one quality at a
time, it fetches the quality's chunks from R2 into a scratch folder, joins
them exactly as the worker does, uploads download.mp4, checks its size, and
deletes the scratch folder. A quality that already has its file is skipped,
so a run that stops can simply be started again.

Run on the server, in the media worker's container, which has FFmpeg, R2's
keys and the media role's database connection:

    docker compose -f infra/compose.prod.yaml exec media-worker \\
        python -m app.download_files --list     # what it would make
    docker compose -f infra/compose.prod.yaml exec media-worker \\
        python -m app.download_files            # make them
"""

import argparse
import re
import shutil
import subprocess
import sys
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from app.db import Database
from app.media_publisher import (
    CONTENT_TYPES,
    IMMUTABLE,
    R2Settings,
    R2Store,
    Store,
    read_master,
)
from app.media_worker import WorkerSettings, download_command
from app.playback import DOWNLOAD_FILE

# Names the media worker writes beside a quality's playlist. Nothing else is
# fetched, so a playlist can't name a path outside the scratch folder.
_FILE = re.compile(r"^(?:init(?:_\d{1,2})?\.mp4|seg_\d{1,6}\.m4s)$")
FETCH_AT_ONCE = 8


class BackfillError(Exception):
    """One quality couldn't be made. The message says which and why."""


def ready_originals(database: Database) -> list[tuple[uuid.UUID, uuid.UUID]]:
    """(item, original) for every ready original, oldest first."""
    with database.anonymous() as conn:
        return conn.execute(
            "select item_id, id from public.media_originals "
            "where state = 'ready' order by ready_at"
        ).fetchall()


def playlist_files(text: str) -> list[str]:
    """The init file and chunks a quality's playlist names, in order."""
    files: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("#EXT-X-MAP:"):
            found = re.search(r'URI="([^"]*)"', line)
            name = found.group(1) if found else ""
        elif line and not line.startswith("#"):
            name = line
        else:
            continue
        if not _FILE.match(name):
            raise BackfillError(f"The playlist names an unexpected file: {name!r}")
        if name not in files:
            files.append(name)
    if not files:
        raise BackfillError("The playlist names no files.")
    return files


def make_one(
    store: Store, prefix: str, quality: str, work: Path, run=subprocess.run
) -> int:
    """Fetches one quality, joins it, uploads download.mp4. Answers its size."""
    folder = work / quality
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    try:
        store.download(f"{prefix}/{quality}/index.m3u8", folder / "index.m3u8")
        names = playlist_files((folder / "index.m3u8").read_text())
        with ThreadPoolExecutor(FETCH_AT_ONCE) as pool:
            list(
                pool.map(
                    lambda name: store.download(
                        f"{prefix}/{quality}/{name}", folder / name
                    ),
                    names,
                )
            )
        result = run(
            download_command(quality), cwd=work, capture_output=True, text=True
        )
        made = folder / DOWNLOAD_FILE
        if result.returncode != 0 or not made.is_file():
            lines = (result.stderr or "").strip().splitlines()
            raise BackfillError(
                f"Joining {quality} failed: {lines[-1] if lines else 'no message'}"
            )
        key = f"{prefix}/{quality}/{DOWNLOAD_FILE}"
        size = made.stat().st_size
        store.upload(made, key, CONTENT_TYPES[".mp4"], cache_control=IMMUTABLE)
        if store.size(key) != size:
            raise BackfillError(f"R2 doesn't have all of {quality}'s file.")
        return size
    finally:
        shutil.rmtree(folder, ignore_errors=True)


def backfill(
    database: Database,
    store: Store,
    work: Path,
    *,
    list_only: bool = False,
    run=subprocess.run,
    say=print,
) -> tuple[int, int, int]:
    """Makes every missing download file. Answers (made, already there,
    failed). One quality failing doesn't stop the others."""
    made = present = failed = 0
    for item_id, original_id in ready_originals(database):
        prefix = f"movies/{item_id}/{original_id}"
        folder = work / str(original_id)
        shutil.rmtree(folder, ignore_errors=True)
        folder.mkdir(parents=True)
        try:
            try:
                store.download(f"{prefix}/master.m3u8", folder / "master.m3u8")
                qualities = read_master(folder / "master.m3u8")
            except Exception as error:  # noqa: BLE001 - reported, then on
                failed += 1
                say(f"FAILED:  {prefix}/master.m3u8: {error!r}")
                continue
            for quality in qualities:
                key = f"{prefix}/{quality.name}/{DOWNLOAD_FILE}"
                if store.size(key) is not None:
                    present += 1
                    continue
                if list_only:
                    say(f"to make: {key}")
                    made += 1
                    continue
                try:
                    size = make_one(store, prefix, quality.name, folder, run)
                except Exception as error:  # noqa: BLE001 - reported, then on
                    failed += 1
                    say(f"FAILED:  {key}: {error}")
                    continue
                made += 1
                say(f"made:    {key} ({size / 1e6:.0f} MB)")
        finally:
            shutil.rmtree(folder, ignore_errors=True)
    return made, present, failed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--list", action="store_true", help="only list what would be made"
    )
    args = parser.parse_args(argv)
    settings = WorkerSettings()
    r2 = R2Settings()
    if not r2.configured:
        print("R2 isn't set up here, so there is nothing to do.", file=sys.stderr)
        return 1
    database = Database(settings.database_url.get_secret_value(), max_size=1)
    database.open()
    try:
        made, present, failed = backfill(
            database,
            R2Store(r2),
            settings.output_dir / "_download_files",
            list_only=args.list,
        )
    finally:
        database.close()
    verb = "to make" if args.list else "made"
    print(f"{made} {verb}, {present} already there, {failed} failed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
