#!/usr/bin/env python3
"""AddKo legacy Kodi addon worker.

The worker executes one Kodi-style Python plugin or script invocation. Kodi
compatibility modules live in runtime/python/shims and emit JSON-line events
back to the AddKo host.
"""

from __future__ import annotations

import datetime
import importlib
import json
import os
import re
import sqlite3
import sys
import traceback
from pathlib import Path

PROTOCOL_PREFIX = "ADDKO_RPC "


def emit(method: str, **params: object) -> None:
    message = {"method": method, "params": params}
    print(PROTOCOL_PREFIX + json.dumps(message, ensure_ascii=False), flush=True)


def _install_kodi_api_fallbacks() -> None:
    """Attach the shared Kodi compatibility fallback to every legacy module."""

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


def _installed_addons(context: dict[str, object]) -> dict[str, str]:
    """Return the current Kodi-style installed addon snapshot.

    Prefer the registry snapshot supplied by Dart. Also discover addon.xml files
    directly because legacy addons can unpack a dependency into the addons
    directory before the Dart registry has observed it.
    """

    installed: dict[str, str] = {}
    raw_snapshot = context.get("installed_addons")
    if isinstance(raw_snapshot, dict):
        for addon_id, version in raw_snapshot.items():
            value = str(addon_id).strip()
            if value:
                installed[value] = str(version or "")

    addons_root = Path(str(context.get("addons_root", "")))
    if addons_root.is_dir():
        try:
            for child in addons_root.iterdir():
                manifest = child / "addon.xml"
                if child.is_dir() and manifest.is_file():
                    installed.setdefault(child.name, "")
        except OSError:
            pass
    return installed


def _install_runtime_overrides(context: dict[str, object]) -> None:
    """Bridge Kodi conditions that can be answered locally without RPC."""

    try:
        import xbmc
    except Exception:
        return

    installed_ids = {addon_id.lower() for addon_id in _installed_addons(context)}
    original_get_cond_visibility = xbmc.getCondVisibility
    addon_condition = re.compile(
        r"^system\.(?:hasaddon|addonisenabled)\((.+)\)$",
        re.IGNORECASE,
    )

    def get_cond_visibility(condition: str) -> bool:
        raw = str(condition).strip()
        match = addon_condition.match(raw)
        if match is not None:
            addon_id = match.group(1).strip().strip("\"'").lower()
            return addon_id in installed_ids
        return bool(original_get_cond_visibility(condition))

    xbmc.getCondVisibility = get_cond_visibility


def _ensure_kodi_addon_database(context: dict[str, object]) -> None:
    """Create the subset of Addons33.db used by legacy Kodi addons.

    Kodi maintains addon installation/enabled state in its addon database. Some
    older ecosystems, including Brazuca Play helpers, access Addons33.db with
    sqlite3 directly instead of going through JSON-RPC. A missing database makes
    those helpers silently fail and the freshly extracted addon never becomes
    usable. Keep a small compatible installed table synchronized with AddKo's
    real addon registry.
    """

    special_paths = context.get("special_paths")
    if not isinstance(special_paths, dict):
        return
    profile_value = special_paths.get("special://profile")
    if not profile_value:
        return

    database_dir = Path(str(profile_value)) / "Database"
    database_dir.mkdir(parents=True, exist_ok=True)
    database_path = database_dir / "Addons33.db"
    installed = _installed_addons(context)
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    try:
        connection = sqlite3.connect(str(database_path), timeout=2.0)
        try:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS installed (
                  id INTEGER PRIMARY KEY,
                  addonID TEXT,
                  enabled BOOLEAN,
                  installDate TEXT,
                  lastUpdated TEXT,
                  lastUsed TEXT,
                  origin TEXT
                )
                """
            )

            # Old third-party helpers sometimes created a reduced installed
            # table themselves. Add the columns Kodi-era code commonly queries.
            columns = {
                str(row[1])
                for row in connection.execute("PRAGMA table_info(installed)")
            }
            for name, sql_type in (
                ("lastUpdated", "TEXT"),
                ("lastUsed", "TEXT"),
                ("origin", "TEXT"),
            ):
                if name not in columns:
                    connection.execute(
                        f"ALTER TABLE installed ADD COLUMN {name} {sql_type}"
                    )

            for addon_id in installed:
                existing = connection.execute(
                    "SELECT id FROM installed WHERE addonID=? LIMIT 1",
                    (addon_id,),
                ).fetchone()
                if existing is None:
                    connection.execute(
                        """
                        INSERT INTO installed
                          (addonID, enabled, installDate, lastUpdated, origin)
                        VALUES (?, 1, ?, ?, ?)
                        """,
                        (addon_id, now, now, "repository.addko"),
                    )
                else:
                    connection.execute(
                        "UPDATE installed SET enabled=1 WHERE addonID=?",
                        (addon_id,),
                    )
            connection.commit()
        finally:
            connection.close()
    except (OSError, sqlite3.Error) as error:
        emit(
            "xbmc.log",
            level=2,
            message=f"AddKo Addons33.db compatibility warning: {error}",
        )


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


def _exception_details(error: BaseException, addon_root: Path) -> dict[str, object]:
    """Return a compact traceback that points at the failing addon source."""

    extracted = traceback.extract_tb(error.__traceback__)
    frames: list[dict[str, object]] = []
    addon_location = ""

    for frame in extracted:
        source = (frame.line or "").strip()
        frames.append(
            {
                "file": frame.filename,
                "line": frame.lineno,
                "function": frame.name,
                "source": source,
            }
        )

        try:
            frame_path = Path(frame.filename).resolve()
            relative = frame_path.relative_to(addon_root)
        except (OSError, ValueError):
            continue

        addon_location = f"{relative}:{frame.lineno} in {frame.name}"
        if source:
            addon_location += f" -> {source}"

    if not addon_location and frames:
        last = frames[-1]
        addon_location = f"{last['file']}:{last['line']} in {last['function']}"

    return {
        "exception_type": type(error).__name__,
        "exception_message": str(error),
        "addon_location": addon_location,
        "traceback": "".join(
            traceback.format_exception(type(error), error, error.__traceback__)
        ),
        "frames": frames,
    }


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
    _install_runtime_overrides(context)
    _ensure_kodi_addon_database(context)

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
            exception_type="SystemExit",
            exception_message=str(error),
            traceback="",
        )
        return code
    except BaseException as error:
        details = _exception_details(error, addon_root)
        emit(
            "invocation.error",
            message=f"{type(error).__name__}: {error}",
            **details,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
