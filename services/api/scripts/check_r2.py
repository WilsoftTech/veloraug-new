"""Checks the R2 bucket the media worker publishes to, before any film goes up.

Run by the project owner, from services/api, once services/api/.env.r2 holds
the four VELORAUG_R2_* settings:

    .\\.venv\\Scripts\\python.exe scripts\\check_r2.py

It asks for nothing and never prints a key. It uploads two test objects under
checks/, a small one and a 65 MB one sent in parts to Infrequent Access as
originals are, checks their sizes and storage classes, checks that the bucket
refuses a request without keys, then deletes both. Infrequent Access bills the
65 MB object for 30 days even though it is deleted: well under a cent.
"""

import os
import sys
import tempfile
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(API_DIR))

from app.media_publisher import R2Settings, R2Store  # noqa: E402

ENV_FILE = API_DIR / ".env.r2"
LARGE_BYTES = 65 * 1024**2


def load_env_file() -> None:
    """VELORAUG_R2_* from .env.r2, unless already set in the environment."""
    if not ENV_FILE.exists():
        return
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        name, sep, value = line.partition("=")
        name = name.strip()
        if sep and name.startswith("VELORAUG_R2_") and not os.environ.get(name):
            os.environ[name] = value.strip().strip('"').strip("'")


def anonymous_status(settings: R2Settings, key: str) -> int:
    """What R2 answers someone without keys asking for an object."""
    url = f"{settings.endpoint}/{settings.bucket}/{key}"
    try:
        with urllib.request.urlopen(url, timeout=15) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def main() -> int:
    load_env_file()
    settings = R2Settings()
    if not settings.configured:
        print(f"R2 isn't set up. Put the four VELORAUG_R2_* lines in {ENV_FILE}.")
        return 1
    print(f"Bucket {settings.bucket} at {settings.endpoint}")
    store = R2Store(settings)
    prefix = f"checks/{uuid.uuid4()}/"
    results = []
    with tempfile.TemporaryDirectory() as folder:
        small, large = Path(folder) / "small", Path(folder) / "large"
        small.write_bytes(os.urandom(1000))
        large.write_bytes(os.urandom(LARGE_BYTES))
        try:
            store.upload(small, prefix + "small.m4s", "video/iso.segment")
            results.append(("upload a small file", True, ""))
            found = store.size(prefix + "small.m4s")
            results.append(("its size matches", found == 1000, f"{found} bytes"))
            store.upload(
                large, prefix + "large", "application/octet-stream", infrequent=True
            )
            found = store.size(prefix + "large")
            results.append(
                ("upload 65 MB in parts", found == LARGE_BYTES, f"{found} bytes")
            )
            cls = store.storage_class(prefix + "large")
            results.append(("it is in Infrequent Access", cls == "STANDARD_IA", cls))
            status = anonymous_status(settings, prefix + "small.m4s")
            results.append(
                ("refused without keys", status in (400, 401, 403), f"HTTP {status}")
            )
        except Exception as error:  # boto3 or the network: show what, never keys
            results.append(("talk to R2", False, f"{type(error).__name__}: {error}"))
        finally:
            try:
                deleted = store.delete_prefix(prefix)
                results.append(("delete the test files", True, f"{deleted} deleted"))
            except Exception as error:
                results.append(("delete the test files", False, type(error).__name__))
    for name, passed, detail in results:
        print(
            f"{'PASS' if passed else 'FAIL'}  {name}"
            + (f" ({detail})" if detail else "")
        )
    failed = sum(not passed for _, passed, _ in results)
    print(f"\n{len(results) - failed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
