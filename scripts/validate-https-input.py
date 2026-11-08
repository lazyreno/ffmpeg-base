#!/usr/bin/env python3
"""Verify FFmpeg can read a short audio file over local HTTPS."""

import argparse
import functools
import http.server
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
from pathlib import Path


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def https_command(ffmpeg: Path, port: int) -> list[str]:
    return [str(ffmpeg), "-hide_banner", "-v", "error", "-tls_verify", "0",
            "-i", f"https://127.0.0.1:{port}/sample.wav", "-f", "null", "-"]


def run(command: list[str], cwd: Path) -> None:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(command)} exited {result.returncode}: {result.stderr}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    args = parser.parse_args()
    ffmpeg = args.ffmpeg.resolve()
    openssl = shutil.which("openssl")
    if not openssl:
        print("OpenSSL is required for the local HTTPS fixture", file=sys.stderr)
        return 1
    try:
        with tempfile.TemporaryDirectory(prefix="ffmpeg-https-") as temporary:
            work = Path(temporary)
            run([str(ffmpeg), "-hide_banner", "-v", "error", "-y", "-f", "lavfi", "-i",
                 "sine=frequency=440:sample_rate=16000", "-t", "0.1", "sample.wav"], work)
            run([openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "key.pem",
                 "-out", "cert.pem", "-subj", "/CN=localhost", "-days", "1"], work)
            handler = functools.partial(QuietHandler, directory=str(work))
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(str(work / "cert.pem"), str(work / "key.pem"))
            server.socket = context.wrap_socket(server.socket, server_side=True)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                run(https_command(ffmpeg, server.server_port), work)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)
    except (OSError, RuntimeError, ssl.SSLError) as error:
        print(error, file=sys.stderr)
        return 1
    print("local HTTPS input: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
