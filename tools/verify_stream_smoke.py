"""Verify a real MP4 file over AddKo's local HTTP Range test server.

No Android SDK, Flutter, Docker, internet access or external test packages.
ffmpeg is only required when no MP4 path is supplied.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import threading
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from stream_smoke_server import handler_for, make_test_video


def inspect_codec(path: Path) -> str:
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        return "indisponível (ffprobe não encontrado)"
    result = subprocess.run(
        [ffprobe, "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=codec_name,width,height", "-of", "json", str(path)],
        capture_output=True, text=True, check=True, timeout=15,
    )
    streams = json.loads(result.stdout).get("streams", [])
    if not streams:
        raise ValueError("MP4 não contém uma faixa de vídeo reconhecível")
    stream = streams[0]
    return f"{stream.get('codec_name', '?')} {stream.get('width', '?')}x{stream.get('height', '?')}"


def verify(path: Path) -> dict[str, object]:
    if not path.is_file() or path.stat().st_size < 1024:
        raise ValueError("Arquivo MP4 não encontrado ou muito pequeno")
    disk_digest = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(64 * 1024), b""):
            disk_digest.update(block)
    size = path.stat().st_size
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(path))
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = f"http://127.0.0.1:{server.server_port}/test.mp4"
    try:
        with urlopen(Request(url, method="HEAD"), timeout=8) as response:
            assert response.status == 200, response.status
            assert int(response.headers["Content-Length"]) == size
            assert response.headers["Accept-Ranges"] == "bytes"
            assert response.read() == b""
        with urlopen(url, timeout=8) as response:
            assert response.status == 200
            assert int(response.headers["Content-Length"]) == size
            transfer_digest = hashlib.sha256()
            received = 0
            while block := response.read(64 * 1024):
                received += len(block)
                transfer_digest.update(block)
            assert received == size
            assert transfer_digest.digest() == disk_digest.digest(), "Arquivo corrompido na transferência"
        n = min(4096, size)
        with urlopen(Request(url, headers={"Range": f"bytes=0-{n-1}"}), timeout=8) as response:
            assert response.status == 206
            assert response.headers["Content-Range"] == f"bytes 0-{n-1}/{size}"
            head = response.read()
            assert len(head) == n
            with path.open("rb") as file:
                assert head == file.read(n)
        with urlopen(Request(url, headers={"Range": f"bytes=-{n}"}), timeout=8) as response:
            assert response.status == 206
            assert response.headers["Content-Range"] == f"bytes {size-n}-{size-1}/{size}"
            tail = response.read()
            assert len(tail) == n
            with path.open("rb") as file:
                file.seek(size - n)
                assert tail == file.read(n)
        try:
            with urlopen(Request(url, headers={"Range": f"bytes={size}-"}), timeout=8):
                raise AssertionError("Range fora de limite deveria gerar HTTP 416")
        except HTTPError as e:
            assert e.code == 416, e.code
            assert e.headers.get("Content-Range") == f"bytes */{size}"
            e.close()
        return {"bytes": size, "head": 200, "get": 200,
                "ranges": [206, 206], "invalid_range": 416,
                "codec": inspect_codec(path)}
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validar MP4 e HTTP Range antes do teste Android")
    parser.add_argument("video", nargs="?", type=Path)
    args = parser.parse_args()
    try:
        if args.video is not None:
            source = args.video.resolve()
        else:
            source = make_test_video(Path("dist/addko-stream-test.mp4").resolve())
        result = verify(source)
    except (OSError, ValueError, AssertionError, subprocess.SubprocessError,
            TimeoutError, json.JSONDecodeError) as error:
        print("FALHOU: verificação do MP4/HTTP Range:", error, file=sys.stderr)
        return 1
    print("PASSOU: arquivo", source)
    print("PASSOU: HEAD=200, GET=200, Range=206/206, inválido=416")
    print("PASSOU: tamanho", result["bytes"], "bytes; codec", result["codec"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
