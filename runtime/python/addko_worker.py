#!/usr/bin/env python3
"""AddKo legacy Kodi addon worker.

The worker executes one Kodi-style Python plugin or script invocation. Kodi
compatibility modules live in runtime/python/shims and emit JSON-line events
back to the AddKo host.
"""

from __future__ import annotations

import importlib
import json
import os
import sys
import traceback
from pathlib import Path

PROTOCOL_PREFIX = "ADDKO_RPC "


def emit(method: str, **params: object) -> None:
    message = {"method": method, "params": params}
    print(PROTOCOL_PREFIX + json.dumps(message, ensure_ascii=False), flush=True)


def _install_kodi_api_fallbacks() -> None:
    """Attach the shared Kodi compatibility fallback to every legacy module.

    Dedicated APIs in the shim modules always win. The fallback is only used
    when an addon reaches a Kodi symbol that has not been bridged explicitly.
    This mirrors the official Kodi API surface without growing a second set of
    Dart implementations for every minor helper.
    """

    from kodi_proxy import module_getattr

    for module_name in (
        "xbmc",
        "xbmcaddon",
        "xbmcgui",
        "xbmcplugin",
        "xbmcvfs",
        "xbmcdrm",
    ):
        try:
            module = importlib.import_module(module_name)
        except Exception:
            continue

        if "__getattr__" in module.__dict__:
            continue

        def fallback(name: str, _module_name: str = module_name):
            return module_getattr(_module_name, name)

        module.__getattr__ = fallback


def _execute_entrypoint(entrypoint: Path) -> None:
    """Execute an addon without letting runpy replace Kodi's sys.argv[0]."""
    namespace = {
        "__name__": "__main__",
        "__file__": str(entrypoint),
        "__package__": None,
        "__cached__": None,
    }
    code = compile(entrypoint.read_bytes(), str(entrypoint), "exec")
    exec(code, namespace, namespace)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: addko_worker.py <context.json>", file=sys.stderr)
        return 2

    context_path = Path(sys.argv[1]).resolve()
    with context_path.open("r", encoding="utf-8") as handle:
        context = json.load(handle)

    os.environ["ADDKO_CONTEXT_FILE"] = str(context_path)

    search_paths = [
        context["shims_path"],
        context["addon_path"],
        *context.get("python_paths", []),
    ]
    for value in reversed(search_paths):
        if value and value not in sys.path:
            sys.path.insert(0, value)

    _install_kodi_api_fallbacks()

    custom_argv = context.get("argv")
    if isinstance(custom_argv, list):
        sys.argv = [str(value) for value in custom_argv]
    else:
        plugin_url = context["plugin_url"]
        plugin_handle = str(context["handle"])
        query = context.get("query", "")
        sys.argv = [plugin_url, plugin_handle, query]

    entrypoint = Path(context["entrypoint_path"]).resolve()
    addon_root = Path(context["addon_path"]).resolve()
    try:
        entrypoint.relative_to(addon_root)
    except ValueError:
        emit(
            "invocation.error",
            message="Entrypoint outside addon directory.",
            traceback="",
        )
        return 3

    if not entrypoint.is_file():
        emit(
            "invocation.error",
            message=f"Entrypoint not found: {entrypoint}",
            traceback="",
        )
        return 4

    try:
        _execute_entrypoint(entrypoint)
        emit("invocation.complete", succeeded=True)
        return 0
    except SystemExit as error:
        code = error.code if isinstance(error.code, int) else 0
        if code == 0:
            emit("invocation.complete", succeeded=True)
            return 0
        emit(
            "invocation.error",
            message=f"Addon exited with code {code}",
            traceback="",
        )
        return code
    except BaseException as error:
        emit(
            "invocation.error",
            message=f"{type(error).__name__}: {error}",
            traceback=traceback.format_exc(),
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
