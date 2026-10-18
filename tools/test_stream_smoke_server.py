"""Pure-Python regression tests for the desktop MP4 HTTP Range smoke server."""
from __future__ import annotations

import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from stream_smoke_server import handler_for, parse_range


class ParseRangeTest(unittest.TestCase):
    def test_full_and_open_range(self) -> None:
        self.assertEqual(parse_range(None, 26), (0, 25, False))
        self.assertEqual(parse_range("bytes=4-9", 26), (4, 9, True))
        self.assertEqual(parse_range("bytes=18-", 26), (18, 25, True))
        self.assertEqual(parse_range("bytes=-5", 26), (21, 25, True))
        self.assertEqual(parse_range("bytes=0-999", 26), (0, 25, True))

    def test_reject_invalid_and_multiple_ranges(self) -> None:
        for header in ("bytes=20-1", "bytes=26-", "bytes=-0",
                       "bytes=0-1,3-5", "bytes=-", "items=0-9"):
            with self.subTest(header=header), self.assertRaises(ValueError):
                parse_range(header, 26)


class StreamingHttpTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.video = Path(self.temp.name) / "test.mp4"
        self.video.write_bytes(b"abcdefghijklmnopqrstuvwxyz")
        self.server = ThreadingHTTPServer(("127.0.0.1", 0),
                                          handler_for(self.video))
        self.thread = threading.Thread(
            target=self.server.serve_forever, daemon=True
        )
        self.thread.start()
        self.url = f"http://127.0.0.1:{self.server.server_port}/test.mp4"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)
        self.temp.cleanup()

    def test_get_head_and_range(self) -> None:
        with urlopen(self.url, timeout=3) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), b"abcdefghijklmnopqrstuvwxyz")
            self.assertEqual(response.headers.get("Accept-Ranges"), "bytes")
        with urlopen(Request(self.url, method="HEAD"), timeout=3) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.headers.get("Content-Length"), "26")
            self.assertEqual(response.read(), b"")
        with urlopen(Request(self.url, headers={"Range": "bytes=4-9"}),
                     timeout=3) as response:
            self.assertEqual(response.status, 206)
            self.assertEqual(response.headers.get("Content-Range"),
                             "bytes 4-9/26")
            self.assertEqual(response.read(), b"efghij")

    def test_404_and_416(self) -> None:
        for url, headers, expected in (
            (self.url.replace("test.mp4", "private"), {}, 404),
            (self.url, {"Range": "bytes=999-"}, 416),
            (self.url, {"Range": "bytes=1-2,5-7"}, 416),
        ):
            with self.subTest(url=url, headers=headers):
                with self.assertRaises(HTTPError) as error:
                    urlopen(Request(url, headers=headers), timeout=3)
                self.assertEqual(error.exception.code, expected)
                error.exception.close()


if __name__ == "__main__":
    unittest.main()
