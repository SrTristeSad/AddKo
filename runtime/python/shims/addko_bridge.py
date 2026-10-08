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
_request_ids = itertools.count(1)
_request_lock = threading.Lock()


def emit(method: str, **params: Any) -> None:
    message = {"method": method, "params": params}
    print(PROTOCOL_PREFIX + json.dumps(message, ensure_ascii=False), flush=True)


def request(method: str, default: Any = None, **params: Any) -> Any:
    # A real AddKo/Kodi addon invocation always has ADDKO_CONTEXT_FILE set by
    # addko_worker.py before the xbmc* compatibility modules are used. The
    # standalone smoke test imports those same modules directly, without a host
    # process on stdin. In that mode a synchronous RPC would block forever on
    # sys.stdin.readline(). Return the Kodi-shaped fallback immediately instead.
    #
    # This keeps the production bridge synchronous while making the shim suite
    # safe to run from build_android.bat, CI and ordinary `python` invocations.
    if not os.environ.get("ADDKO_CONTEXT_FILE"):
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
    global _context_cache
    if _context_cache is None:
        source = os.environ.get("ADDKO_CONTEXT_FILE")
        if not source:
            raise RuntimeError("ADDKO_CONTEXT_FILE is not configured")
        with Path(source).open("r", encoding="utf-8") as handle:
            _context_cache = json.load(handle)
    return _context_cache


def special_path(value: str) -> str:
    if not value.startswith("special://"):
        return value

    ctx = context()
    mappings = ctx.get("special_paths", {})
    for key, target in sorted(mappings.items(), key=lambda item: len(item[0]), reverse=True):
        prefix = key if key.endswith("/") else key + "/"
        if value == key.rstrip("/"):
            return str(target)
        if value.startswith(prefix):
            suffix = value[len(prefix) :]
            return str(Path(target) / suffix)
    return value
