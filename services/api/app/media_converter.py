"""Run media tools in the isolated converter container over a Unix socket."""

import json
import os
import socket
import socketserver
import subprocess
from pathlib import Path

from app.media_worker import TOOL_ENV, ConversionFailed, stream_process

SOCKET = "/srv/converter/worker.sock"


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        def send(message):
            self.wfile.write(json.dumps(message).encode() + b"\n")

        try:
            command, folder, timeout, stream = json.loads(self.rfile.readline(65536))
            if command[0] not in ("ffmpeg", "ffprobe"):
                raise ValueError("Unknown media tool")
            if stream:
                result = stream_process(
                    command, Path(folder), lambda line: send({"progress": line})
                )
            else:
                result = subprocess.run(
                    command,
                    cwd=folder,
                    timeout=timeout,
                    capture_output=True,
                    text=True,
                    env=TOOL_ENV,
                )
            send({"result": [result.returncode, result.stdout, result.stderr[-8192:]]})
        except subprocess.TimeoutExpired:
            send({"timeout": True})
        except (OSError, ValueError, ConversionFailed) as error:
            send({"error": str(error)[:300]})


def execute(command, *, cwd=None, timeout=300, on_line=None):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.connect(SOCKET)
        with connection.makefile("rwb") as wire:
            wire.write(
                json.dumps(
                    [command, str(cwd) if cwd else None, timeout, on_line is not None]
                ).encode()
                + b"\n"
            )
            wire.flush()
            for line in wire:
                message = json.loads(line)
                if "progress" in message:
                    on_line(message["progress"])
                elif "result" in message:
                    return subprocess.CompletedProcess(command, *message["result"])
                elif "timeout" in message:
                    raise subprocess.TimeoutExpired(command, timeout)
                else:
                    raise ConversionFailed(message["error"])
    raise ConversionFailed("The converter stopped before returning a result.")


def run(command, *, cwd=None, timeout=300, capture_output=True, text=True, env=None):
    return execute(command, cwd=cwd, timeout=timeout)


def stream(command, cwd, on_line):
    return execute(command, cwd=cwd, on_line=on_line)


def main():
    Path(SOCKET).unlink(missing_ok=True)
    os.umask(0o077)
    with socketserver.UnixStreamServer(SOCKET, Handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
