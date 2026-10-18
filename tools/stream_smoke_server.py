"""Reproducible local MP4 + HTTP byte-range server for AddKo Android.

Works on Windows with Python 3. No Docker or GitHub Actions.
Use "adb reverse tcp:8765 tcp:8765" to let a USB-connected Android
phone reach this desktop-only 127.0.0.1 test server.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = 8765
CHUNK_SIZE = 64 * 1024
RANGE = re.compile(r"^bytes=(\d*)-(\d*)$")


def make_test_video(destination: Path) -> Path:
    if destination.is_file() and destination.stat().st_size:
        return destination
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError(
            "ffmpeg não encontrado. Passe seu MP4 como argumento:\n"
            "TESTAR_STREAM_ANDROID.bat C:\\Videos\\meu_video.mp4"
        )
    destination.parent.mkdir(parents=True, exist_ok=True)
    command = [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "testsrc=size=256x144:rate=12:duration=18",
        "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-preset", "ultrafast", "-crf", "35", "-movflags", "+faststart",
        str(destination),
    ]
    subprocess.run(command, check=True)
    if not destination.is_file() or destination.stat().st_size < 1024:
        raise RuntimeError("MP4 de teste não foi gerado corretamente.")
    return destination


def parse_range(header: str | None, length: int) -> tuple[int, int, bool]:
    """Return inclusive byte start/end and whether request was ranged."""
    if not header:
        return (0, length - 1, False)
    match = RANGE.fullmatch(header.strip())
    if not match or not (match.group(1) or match.group(2)):
        raise ValueError("HTTP Range inválido")
    first, last = match.groups()
    if not first:  # bytes=-4096
        suffix = int(last)
        if suffix < 1:
            raise ValueError("Sufixo inválido")
        return (max(0, length - suffix), length - 1, True)
    start = int(first)
    end = min(length - 1, int(last)) if last else length - 1
    if start >= length or start > end:
        raise ValueError("Range fora do arquivo")
    return (start, end, True)


def handler_for(video: Path) -> type[BaseHTTPRequestHandler]:
    class VideoHandler(BaseHTTPRequestHandler):
        server_version = "AddKoSmoke/1.0"
        protocol_version = "HTTP/1.1"

        def do_HEAD(self) -> None:
            self._respond(with_body=False)

        def do_GET(self) -> None:
            self._respond(with_body=True)

        def _respond(self, *, with_body: bool) -> None:
            if self.path != "/test.mp4":
                self.send_error(404, "Apenas /test.mp4 disponível")
                return
            size = video.stat().st_size
            try:
                start, end, partial = parse_range(
                    self.headers.get("Range"), size
                )
            except ValueError:
                self.send_response(416)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return

            self.send_response(206 if partial else 200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(end - start + 1))
            self.send_header("Cache-Control", "no-store")
            if partial:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.end_headers()
            if not with_body:
                return
            try:
                with video.open("rb") as source:
                    source.seek(start)
                    remaining = end - start + 1
                    while remaining > 0:
                        block = source.read(min(remaining, CHUNK_SIZE))
                        if not block:
                            break
                        self.wfile.write(block)
                        remaining -= len(block)
            except (BrokenPipeError, ConnectionResetError):
                # The native player normally cancels the previous request on seek.
                pass

        def log_message(self, format_string: str, *args: object) -> None:
            print(
                self.address_string(),
                self.command,
                self.path,
                "Range=" + str(self.headers.get("Range")),
                format_string % args,
                flush=True,
            )

    return VideoHandler


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Servidor de vídeo MP4 com suporte a Range para testar AddKo."
    )
    parser.add_argument(
        "video", nargs="?", type=Path,
        help="Arquivo MP4 próprio. Se omitido, gera vídeo com ffmpeg.",
    )
    parser.add_argument("--port", type=int, default=PORT)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("Porta deve estar entre 1 e 65535")
    source = args.video if args.video is not None else (
        Path("dist") / "addko-stream-test.mp4"
    )
    try:
        if args.video is not None:
            video = source.resolve()
            if not video.is_file() or video.stat().st_size < 1024:
                raise FileNotFoundError(
                    "MP4 inexistente ou vazio: " + str(video)
                )
        else:
            video = make_test_video(source.resolve())
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print("ERRO:", error, file=sys.stderr)
        return 1

    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(video))
    server.daemon_threads = True
    print("AddKo streaming smoke test", flush=True)
    print("Vídeo:", video, flush=True)
    print("Endereço no Android: http://127.0.0.1:" + str(args.port) + "/test.mp4", flush=True)
    print("Abra o addon Media Bridge e toque Reproduzir.", flush=True)
    print("Confira Range=bytes=... ao usar a barra de progresso.", flush=True)
    print("Ctrl+C para encerrar.", flush=True)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
