from __future__ import annotations

import itertools
import json
import os
import sys
import threading
from pathlib import Path
from typing import Any

PROTOCOL_PREFIX = "ADDKO_RPC "
_context_cache: dict[str, Any] | None = None
_context_cache_source: str | None = None
_request_ids = itertools.count(1)
_request_lock = threading.Lock()


def emit(method: str, **params: Any) -> None:
    message = {"method": method, "params": params}
    print(PROTOCOL_PREFIX + json.dumps(message, ensure_ascii=False), flush=True)


def _context_source() -> str | None:
    """Return the invocation context for the current Python interpreter.

    Android runs several Kodi add-ons in CPython subinterpreters inside the same
    process. Environment variables are process-global, so using
    ADDKO_CONTEXT_FILE as the primary source can make concurrent services read
    another add-on's context. A sys attribute is interpreter-local and avoids
    that race. The environment variable remains as a desktop/backward-compatible
    fallback.
    """

    local_source = getattr(sys, "_addko_context_file", None)
    if local_source:
        return str(local_source)
    environment_source = os.environ.get("ADDKO_CONTEXT_FILE")
    return str(environment_source) if environment_source else None


def reset_context_cache() -> None:
    global _context_cache, _context_cache_source
    _context_cache = None
    _context_cache_source = None


def request(method: str, default: Any = None, **params: Any) -> Any:
    # A real AddKo/Kodi invocation has an interpreter-local context configured
    # by addko_worker.py (or ADDKO_CONTEXT_FILE on the desktop fallback). The
    # standalone smoke test imports the shims without a host on stdin. In that
    # mode a synchronous RPC would block forever, so return the Kodi-shaped
    # default immediately.
    if not _context_source():
        return default

    with _request_lock:
        request_id = next(_request_ids)
        message = {
            "method": method,
            "params": params,
            "request_id": request_id,
            "expects_response": True,
            "default": default,
        }
        print(PROTOCOL_PREFIX + json.dumps(message, ensure_ascii=False), flush=True)

        response_line = sys.stdin.readline()
        if not response_line:
            return default
        try:
            response = json.loads(response_line)
        except json.JSONDecodeError:
            return default
        if response.get("request_id") != request_id:
            return default
        return response.get("result", default)


def context() -> dict[str, Any]:
    global _context_cache, _context_cache_source
    source = _context_source()
    if not source:
        raise RuntimeError("AddKo invocation context is not configured")

    # Reusable language invokers may eventually execute multiple invocations in
    # the same interpreter. Refresh automatically if the host changes the
    # interpreter-local context path.
    if _context_cache is None or _context_cache_source != source:
        with Path(source).open("r", encoding="utf-8") as handle:
            value = json.load(handle)
        if not isinstance(value, dict):
            raise RuntimeError("AddKo invocation context must be a JSON object")
        _context_cache = value
        _context_cache_source = source
    return _context_cache


def special_path(value: str) -> str:
    if not value.startswith("special://"):
        return value

    ctx = context()
    mappings = ctx.get("special_paths", {})
    if not isinstance(mappings, dict):
        return value
    for key, target in sorted(mappings.items(), key=lambda item: len(item[0]), reverse=True):
        key = str(key)
        prefix = key if key.endswith("/") else key + "/"
        if value == key.rstrip("/"):
            return str(target)
        if value.startswith(prefix):
            suffix = value[len(prefix) :]
            return str(Path(str(target)) / suffix)
    return value
