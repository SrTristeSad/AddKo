from __future__ import annotations

"""Kodi Omega ``xbmcwsgi`` compatibility surface.

Kodi only exposes this module to Python web-interface add-ons through its WSGI
web-server invoker. AddKo does not host Kodi's HTTP server yet, but keeping the
same public stream/response objects means web-interface packages can be parsed,
imported and exercised without failing merely because ``xbmcwsgi`` is absent.
"""

from typing import Any, Iterable, Iterator

from addko_bridge import emit


class WsgiErrorStream:
    """Representation of Kodi's ``wsgi.errors`` stream."""

    def flush(self) -> None:
        return None

    def write(self, value: str) -> None:
        message = str(value).rstrip("\n")
        if message:
            emit("xbmc.log", message=message, level=3)

    def writelines(self, seq: Iterable[str]) -> None:
        self.write("".join(str(value) for value in seq))


class WsgiInputStreamIterator:
    """Read/iteration behaviour exported by Kodi's WSGI input stream."""

    def __init__(self, data: str | bytes = b"") -> None:
        if isinstance(data, bytes):
            data = data.decode("latin-1")
        self._data = str(data)
        self._offset = 0

    def read(self, size: int = 0) -> str:
        if self._offset >= len(self._data):
            return ""
        if size is None or int(size) <= 0:
            result = self._data[self._offset :]
            self._offset = len(self._data)
            return result
        end = min(len(self._data), self._offset + int(size))
        result = self._data[self._offset : end]
        self._offset = end
        return result

    def readline(self, size: int = 0) -> str:
        if self._offset >= len(self._data):
            return ""
        newline = self._data.find("\n", self._offset)
        end = len(self._data) if newline < 0 else newline + 1
        if size is not None and int(size) > 0:
            end = min(end, self._offset + int(size))
        result = self._data[self._offset : end]
        self._offset = end
        return result

    def readlines(self, sizehint: int = 0) -> list[str]:
        lines: list[str] = []
        consumed = 0
        while self._offset < len(self._data):
            line = self.readline()
            if not line:
                break
            lines.append(line)
            consumed += len(line)
            if sizehint is not None and int(sizehint) > 0 and consumed >= int(sizehint):
                break
        return lines

    def __iter__(self) -> Iterator[str]:
        return self

    def __next__(self) -> str:
        value = self.readline()
        if not value:
            raise StopIteration
        return value


class WsgiInputStream(WsgiInputStreamIterator):
    """Kodi ``wsgi.input`` object.

    The optional data argument is an AddKo testing/host convenience. Kodi itself
    constructs this object internally and binds the current HTTP request.
    """

    pass


class WsgiResponseBody:
    """Callable ``write`` object returned by ``start_response``."""

    def __init__(self) -> None:
        self._chunks: list[str] = []

    def __call__(self, data: str) -> None:
        self._chunks.append(str(data))

    @property
    def data(self) -> str:
        return "".join(self._chunks)


class WsgiResponse:
    """Kodi-compatible ``start_response`` callable."""

    def __init__(self) -> None:
        self.called = False
        self.status = "500 Internal Server Error"
        self.response_headers: list[tuple[str, str]] = []
        self.body = WsgiResponseBody()

    def __call__(
        self,
        status: str,
        response_headers: Iterable[tuple[str, str]],
        exc_info: Any = None,
    ) -> WsgiResponseBody:
        if self.called and exc_info is None:
            raise RuntimeError("start_response called twice without exc_info")

        normalized_status = str(status)
        if len(normalized_status) < 4 or not normalized_status[:3].isdigit():
            raise ValueError(f"invalid WSGI status: {normalized_status!r}")

        headers: list[tuple[str, str]] = []
        for header in response_headers:
            if not isinstance(header, (tuple, list)) or len(header) != 2:
                raise TypeError("response_headers must contain (name, value) pairs")
            headers.append((str(header[0]), str(header[1])))

        self.called = True
        self.status = normalized_status
        self.response_headers = headers
        emit(
            "xbmcwsgi.WsgiResponse.start",
            status=self.status,
            headers=[list(header) for header in self.response_headers],
        )
        return self.body


__all__ = [
    "WsgiErrorStream",
    "WsgiInputStreamIterator",
    "WsgiInputStream",
    "WsgiResponseBody",
    "WsgiResponse",
]
