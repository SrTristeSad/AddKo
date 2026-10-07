from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

PROTOCOL_PREFIX = "ADDKO_RPC "
_context_cache: dict[str, Any] | None = None


def emit(method: str, **params: Any) -> None:
    message = {"method": method, "params": params}
    print(PROTOCOL_PREFIX + json.dumps(message, ensure_ascii=False), flush=True)


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
