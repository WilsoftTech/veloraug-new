"""The uploaders' script, tools/veloraug_upload.py, against a small fake tus
server that can drop a connection halfway through a piece."""

import hashlib
import importlib.util
import io
import os
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parents[3] / "tools" / "veloraug_upload.py"
spec = importlib.util.spec_from_file_location("veloraug_upload", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

GOOD_KEY = "vu_good"


class FakeTus(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)
        self.uploads: dict[str, bytearray] = {}
        self.sizes: dict[str, int] = {}
        self.keys_seen: list[str] = []
        self.drops = 0
        self.patches = 0

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server_address[1]}/files/"


class Handler(BaseHTTPRequestHandler):
    server: FakeTus

    def log_message(self, *args):
        pass

    def reply(self, status, headers=None, body=b""):
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        key = self.headers.get("Upload-Key", "")
        self.server.keys_seen.append(key)
        if key != GOOD_KEY:
            return self.reply(403, body=b"This upload key doesn't work.\n")
        upload_id = uuid.uuid4().hex
        self.server.uploads[upload_id] = bytearray()
        self.server.sizes[upload_id] = int(self.headers["Upload-Length"])
        self.reply(201, {"Location": f"/files/{upload_id}"})

    def upload_id(self):
        return self.path.rsplit("/", 1)[-1]

    def do_HEAD(self):
        data = self.server.uploads.get(self.upload_id())
        if data is None:
            return self.reply(404)
        self.reply(200, {"Upload-Offset": str(len(data)), "Cache-Control": "no-store"})

    def do_PATCH(self):
        data = self.server.uploads[self.upload_id()]
        start = int(self.headers["Upload-Offset"])
        length = int(self.headers["Content-Length"])
        if start != len(data):
            self.rfile.read(length)
            return self.reply(409)
        body = self.rfile.read(length)
        self.server.patches += 1
        if self.server.drops:
            # Keep half, then hang up without answering, as a dropped
            # connection would.
            self.server.drops -= 1
            data += body[: length // 2]
            self.close_connection = True
            return
        data += body
        self.reply(204, {"Upload-Offset": str(len(data))})


@pytest.fixture
def server():
    fake = FakeTus()
    thread = threading.Thread(target=fake.serve_forever, daemon=True)
    thread.start()
    yield fake
    fake.shutdown()
    fake.server_close()


@pytest.fixture
def movie(tmp_path, monkeypatch):
    monkeypatch.setattr(tool, "CHUNK_BYTES", 64 * 1024)
    monkeypatch.setattr(tool, "SEND_BYTES", 8 * 1024)
    monkeypatch.setattr(tool.time, "sleep", lambda seconds: None)
    path = tmp_path / "Film.mp4"
    path.write_bytes(os.urandom(300 * 1024 + 7))
    return path


def stored(server):
    [data] = server.uploads.values()
    return hashlib.sha256(data).digest()


def test_a_file_uploads_in_pieces_and_matches(server, movie):
    out = io.StringIO()

    tool.upload(movie, server.url, lambda: GOOD_KEY, out)

    assert stored(server) == hashlib.sha256(movie.read_bytes()).digest()
    assert server.patches == 5
    assert not tool.state_file(movie).exists()
    assert GOOD_KEY not in out.getvalue()
    assert "Uploaded." in out.getvalue()


def test_a_dropped_connection_carries_on_from_where_it_stopped(server, movie):
    server.drops = 2

    tool.upload(movie, server.url, lambda: GOOD_KEY, io.StringIO())

    assert stored(server) == hashlib.sha256(movie.read_bytes()).digest()


def test_running_again_resumes_without_asking_for_the_key(server, movie, monkeypatch):
    real_send = tool.send_chunk
    calls = 0

    def stop_after_two(*args):
        nonlocal calls
        calls += 1
        if calls > 2:
            raise KeyboardInterrupt
        return real_send(*args)

    monkeypatch.setattr(tool, "send_chunk", stop_after_two)
    with pytest.raises(KeyboardInterrupt):
        tool.upload(movie, server.url, lambda: GOOD_KEY, io.StringIO())
    assert tool.state_file(movie).exists()
    assert GOOD_KEY not in tool.state_file(movie).read_text()

    monkeypatch.setattr(tool, "send_chunk", real_send)

    def no_key():
        raise AssertionError("asked for the key again")

    out = io.StringIO()
    tool.upload(movie, server.url, no_key, out)

    assert "Carrying on" in out.getvalue()
    assert stored(server) == hashlib.sha256(movie.read_bytes()).digest()
    assert server.keys_seen == [GOOD_KEY]


def test_a_refused_key_shows_the_servers_sentence(server, movie):
    with pytest.raises(tool.UploadError) as error:
        tool.upload(movie, server.url, lambda: "vu_wrong", io.StringIO())

    assert str(error.value) == "This upload key doesn't work."
    assert not tool.state_file(movie).exists()


def test_an_upload_the_server_forgot_explains_what_to_do(server, movie):
    tool.save_state(movie, movie.stat().st_size, server.url, server.url + "gone")

    with pytest.raises(tool.UploadError) as error:
        tool.upload(movie, server.url, lambda: GOOD_KEY, io.StringIO())

    assert "can't be resumed" in str(error.value)


def test_progress_from_another_file_isnt_used(server, movie):
    tool.save_state(movie, 1, server.url, server.url + "x")

    with pytest.raises(tool.UploadError) as error:
        tool.upload(movie, server.url, lambda: GOOD_KEY, io.StringIO())

    assert "different file" in str(error.value)


def test_an_unreachable_server_gives_up_with_advice(movie, monkeypatch):
    monkeypatch.setattr(tool, "RETRIES", 1)

    with pytest.raises(tool.UploadError) as error:
        tool.upload(movie, "http://127.0.0.1:1/files/", lambda: GOOD_KEY, io.StringIO())

    assert "Run the same command again" in str(error.value)


def test_an_empty_or_missing_file_is_refused(tmp_path):
    empty = tmp_path / "empty.mp4"
    empty.write_bytes(b"")

    for path in (empty, tmp_path / "missing.mp4"):
        with pytest.raises(tool.UploadError):
            tool.upload(path, "http://127.0.0.1:1/files/", lambda: GOOD_KEY)


def test_the_tool_needs_only_the_standard_library():
    imports = [
        line.split()[1].split(".")[0]
        for line in TOOL.read_text(encoding="utf-8").splitlines()
        if line.startswith(("import ", "from "))
    ]
    allowed = {
        "argparse",
        "base64",
        "getpass",
        "http",
        "json",
        "os",
        "re",
        "sys",
        "time",
        "pathlib",
        "urllib",
    }
    assert set(imports) <= allowed


def test_resume_location_stays_on_configured_https_origin():
    server = "https://upload.example.test/files/"
    assert tool.resume_address(server, "local-id") == server + "local-id"
    for target in (
        "https://elsewhere.example.test/files/id",
        "http://upload.example.test/files/id",
        "/elsewhere/id",
        "/files/a%2fb",
    ):
        with pytest.raises(tool.UploadError):
            tool.resume_address(server, target)
