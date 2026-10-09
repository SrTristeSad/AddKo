#!/usr/bin/env python3
"""Regression test for AddKo's interpreter-local Kodi invocation context."""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHIMS = ROOT / "runtime" / "python" / "shims"
sys.path.insert(0, str(SHIMS))

import addko_bridge  # noqa: E402


def write_context(path: Path, addon_id: str) -> None:
    path.write_text(
        json.dumps(
            {
                "addon_id": addon_id,
                "special_paths": {
                    "special://profile": str(path.parent / addon_id),
                },
            }
        ),
        encoding="utf-8",
    )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="addko-context-") as temporary:
        root = Path(temporary)
        first = root / "first.json"
        second = root / "second.json"
        write_context(first, "service.first")
        write_context(second, "service.second")

        # A process-global environment value must never override the context of
        # the current CPython subinterpreter.
        os.environ["ADDKO_CONTEXT_FILE"] = str(second)
        sys._addko_context_file = str(first)  # type: ignore[attr-defined]
        addko_bridge.reset_context_cache()
        assert addko_bridge.context()["addon_id"] == "service.first"
        assert addko_bridge.special_path("special://profile/cache").endswith(
            "service.first/cache"
        )

        # Future reusable language invokers can switch context paths safely in
        # one interpreter; the bridge invalidates the cached JSON automatically.
        sys._addko_context_file = str(second)  # type: ignore[attr-defined]
        assert addko_bridge.context()["addon_id"] == "service.second"

        # Desktop/process execution keeps the environment fallback.
        del sys._addko_context_file  # type: ignore[attr-defined]
        os.environ["ADDKO_CONTEXT_FILE"] = str(first)
        addko_bridge.reset_context_cache()
        assert addko_bridge.context()["addon_id"] == "service.first"

    os.environ.pop("ADDKO_CONTEXT_FILE", None)
    addko_bridge.reset_context_cache()
    print("[AddKo] embedded context isolation: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
