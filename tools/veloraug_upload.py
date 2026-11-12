"""Uploads one movie file to VeloraUG with a one-time upload key.

Needs only Python 3.10 or newer, with no packages. Run:

    python veloraug_upload.py "C:\\Movies\\My Film.mp4"

It asks for the upload key, hidden as you paste, unless VELORAUG_UPLOAD_KEY
is set. If the connection drops, or you stop it with Ctrl+C, run the same
command again: it carries on from where it stopped. Progress is kept in a
small file beside the movie, ending .veloraug-upload, which is deleted when
the upload finishes. Keep that file private until then: it holds the address
of the unfinished upload.

The key is never printed or saved. See docs/step-07a-uploads-plan.md.
"""

import argparse
import base64
import getpass
import http.client
import json
import os
import sys
import time
from pathlib import Path
from urllib.parse import urljoin, urlsplit

DEFAULT_SERVER = "http://127.0.0.1:1080/files/"
TUS_VERSION = "1.0.0"
CHUNK_BYTES = 50 * 1024 * 1024
SEND_BYTES = 1024 * 1024
RETRIES = 8
TIMEOUT_SECONDS = 60
STATE_SUFFIX = ".veloraug-upload"


class UploadError(Exception):
    """Stops the upload. The message is safe to show."""


class Retry(Exception):
    """A dropped connection or a server hiccup. Worth trying again."""


def connect(url: str) -> http.client.HTTPConnection:
    parts = urlsplit(url)
    if parts.scheme == "https":
        return http.client.HTTPSConnection(
            parts.hostname, parts.port, timeout=TIMEOUT_SECONDS
        )
    if parts.scheme == "http":
        return http.client.HTTPConnection(
            parts.hostname, parts.port, timeout=TIMEOUT_SECONDS
        )
    raise UploadError(f"The server address must start with http:// or https://: {url}")


def path_of(url: str) -> str:
    parts = urlsplit(url)
    return (parts.path or "/") + (f"?{parts.query}" if parts.query else "")


def request(
    method: str, url: str, headers: dict[str, str], body: bytes = b""
) -> tuple[int, dict[str, str], str]:
    conn = connect(url)
    try:
        conn.request(method, path_of(url), body=body, headers=headers)
        response = conn.getresponse()
        text = response.read(4096).decode("utf-8", "replace").strip()
        return response.status, {k.lower(): v for k, v in response.getheaders()}, text
    except (OSError, http.client.HTTPException) as error:
        raise Retry(type(error).__name__) from None
    finally:
        conn.close()


def tus_headers(**extra: str) -> dict[str, str]:
    return {"Tus-Resumable": TUS_VERSION, **extra}


def create(server: str, key: str, path: Path, size: int) -> str:
    """Starts an upload. The server checks the key before any data is sent."""
    name = base64.b64encode(path.name.encode()).decode()
    status, headers, text = request(
        "POST",
        server,
        tus_headers(
            **{
                "Upload-Length": str(size),
                "Upload-Metadata": f"filename {name}",
                "Upload-Key": key,
                "Content-Length": "0",
            }
        ),
    )
    if status == 201 and headers.get("location"):
        return urljoin(server, headers["location"])
    if status >= 500 and status != 503:
        raise Retry(f"HTTP {status}")
    # The server's sentence explains a refusal: a bad key, a file too large.
    raise UploadError(text or f"The server refused the upload (HTTP {status}).")


def offset(url: str) -> int:
    status, headers, _ = request("HEAD", url, tus_headers())
    if status in (404, 410):
        raise UploadError(
            "This upload can't be resumed any more. Ask VeloraUG's owner for a "
            f"new key, delete the {STATE_SUFFIX} file beside the movie, and start "
            "again."
        )
    if status >= 500:
        raise Retry(f"HTTP {status}")
    if status != 200 or "upload-offset" not in headers:
        raise UploadError(f"The server gave an unexpected answer (HTTP {status}).")
    return int(headers["upload-offset"])


def send_chunk(url: str, path: Path, start: int, length: int) -> int:
    """Sends one piece, streamed from the file. Returns the new offset."""
    conn = connect(url)
    try:
        conn.putrequest("PATCH", path_of(url))
        for name, value in tus_headers(
            **{
                "Upload-Offset": str(start),
                "Content-Type": "application/offset+octet-stream",
                "Content-Length": str(length),
            }
        ).items():
            conn.putheader(name, value)
        conn.endheaders()
        with path.open("rb") as file:
            file.seek(start)
            left = length
            while left:
                data = file.read(min(SEND_BYTES, left))
                if not data:
                    raise UploadError("The file got shorter while uploading.")
                conn.send(data)
                left -= len(data)
        response = conn.getresponse()
        text = response.read(4096).decode("utf-8", "replace").strip()
        if response.status == 204:
            return int(response.getheader("Upload-Offset", start + length))
        if response.status >= 500 or response.status == 409:
            raise Retry(f"HTTP {response.status}")
        raise UploadError(
            text or f"The server refused a piece (HTTP {response.status})."
        )
    except (OSError, http.client.HTTPException) as error:
        raise Retry(type(error).__name__) from None
    finally:
        conn.close()


def state_file(path: Path) -> Path:
    return path.with_name(path.name + STATE_SUFFIX)


def load_state(path: Path, size: int, server: str) -> str | None:
    """The unfinished upload's address, if this same file was started here."""
    saved = state_file(path)
    if not saved.exists():
        return None
    try:
        state = json.loads(saved.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise UploadError(
            f"{saved.name} can't be read. Delete it to start again."
        ) from None
    if state.get("size") != size or state.get("server") != server:
        raise UploadError(
            f"{saved.name} is for a different file or server. Delete it to start "
            "again, with a new key."
        )
    return state.get("url")


def save_state(path: Path, size: int, server: str, url: str) -> None:
    state_file(path).write_text(
        json.dumps({"server": server, "size": size, "url": url}), encoding="utf-8"
    )


def progress(done: int, size: int, started: float, at_start: int) -> str:
    elapsed = max(time.monotonic() - started, 0.001)
    rate = (done - at_start) / elapsed
    eta = (size - done) / rate if rate > 0 else 0
    return (
        f"\r{done / size:6.1%}  {done / 1e9:.2f} of {size / 1e9:.2f} GB  "
        f"{rate / 1e6:5.1f} MB/s  about {int(eta // 60)} min left   "
    )


def with_retries(action, *args, pause=time.sleep):
    for attempt in range(RETRIES + 1):
        try:
            return action(*args)
        except Retry as error:
            if attempt == RETRIES:
                raise UploadError(
                    f"The connection kept failing ({error}). Run the same command "
                    "again later to carry on."
                ) from None
            wait = min(2**attempt, 60)
            print(f"\nConnection problem ({error}). Trying again in {wait} s.")
            pause(wait)


def upload(path: Path, server: str, key_source, out=sys.stdout) -> None:
    if not path.is_file():
        raise UploadError(f"No file at {path}")
    size = path.stat().st_size
    if size == 0:
        raise UploadError("The file is empty.")
    url = load_state(path, size, server)
    if url:
        print("Carrying on with the upload started earlier.", file=out)
    else:
        key = key_source()
        if not key.strip():
            raise UploadError("No key given.")
        url = with_retries(create, server, key.strip(), path, size)
        save_state(path, size, server, url)
    done = with_retries(offset, url)
    started, at_start = time.monotonic(), done
    failures = 0
    while done < size:
        length = min(CHUNK_BYTES, size - done)
        try:
            done = send_chunk(url, path, done, length)
            failures = 0
        except Retry as error:
            failures += 1
            if failures > RETRIES:
                raise UploadError(
                    f"The connection kept failing ({error}). Run the same command "
                    "again later to carry on."
                ) from None
            wait = min(2**failures, 60)
            print(
                f"\nConnection problem ({error}). Checking where it stopped, in "
                f"{wait} s.",
                file=out,
            )
            time.sleep(wait)
            done = with_retries(offset, url)
        print(progress(done, size, started, at_start), end="", flush=True, file=out)
    state_file(path).unlink(missing_ok=True)
    print(
        "\nUploaded. VeloraUG will check the file and make its qualities. "
        "The owner can follow it with `catalogue.py uploads`.",
        file=out,
    )


def ask_key() -> str:
    key = os.environ.get("VELORAUG_UPLOAD_KEY", "")
    return key or getpass.getpass("Upload key, hidden as you paste: ")


def main() -> int:
    parser = argparse.ArgumentParser(description="Upload a movie file to VeloraUG.")
    parser.add_argument("file", type=Path, help="the movie file")
    parser.add_argument(
        "--server", default=DEFAULT_SERVER, help=f"upload address, {DEFAULT_SERVER}"
    )
    args = parser.parse_args()
    server = args.server if args.server.endswith("/") else args.server + "/"
    try:
        upload(args.file, server, ask_key)
    except UploadError as error:
        print(f"\n{error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nStopped. Run the same command again to carry on.", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
