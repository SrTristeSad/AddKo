#!/usr/bin/env python3
"""Vendor the exact Kodi Omega legacy Python API source used by AddKo.

This tool is intentionally separate from the normal Android build. It is used
when updating AddKo's compatibility layer so API names/signatures/constants are
copied from Kodi instead of being guessed or recreated from memory.
"""

from __future__ import annotations

import hashlib
import json
import urllib.request
from pathlib import Path

KODI_REPOSITORY = "https://raw.githubusercontent.com/xbmc/xbmc"
KODI_COMMIT = "f8815ee40f49a700c047982d752be4b2a61420e2"

FILES = (
    "xbmc/interfaces/swig/AddonModuleXbmc.i",
    "xbmc/interfaces/swig/AddonModuleXbmcaddon.i",
    "xbmc/interfaces/swig/AddonModuleXbmcgui.i",
    "xbmc/interfaces/swig/AddonModuleXbmcplugin.i",
    "xbmc/interfaces/swig/AddonModuleXbmcvfs.i",
    "xbmc/interfaces/legacy/ModuleXbmc.h",
    "xbmc/interfaces/legacy/ModuleXbmcgui.h",
    "xbmc/interfaces/legacy/ModuleXbmcplugin.h",
    "xbmc/interfaces/legacy/ModuleXbmcvfs.h",
    "xbmc/interfaces/legacy/Addon.h",
    "xbmc/interfaces/legacy/Settings.h",
    "xbmc/interfaces/legacy/Dialog.h",
    "xbmc/interfaces/legacy/Keyboard.h",
    "xbmc/interfaces/legacy/ListItem.h",
    "xbmc/interfaces/legacy/Player.h",
    "xbmc/interfaces/legacy/PlayList.h",
    "xbmc/interfaces/legacy/Monitor.h",
    "xbmc/interfaces/legacy/Window.h",
    "xbmc/interfaces/legacy/WindowXML.h",
    "xbmc/interfaces/legacy/Control.h",
    "xbmc/interfaces/legacy/File.h",
    "xbmc/interfaces/legacy/Stat.h",
)


def root() -> Path:
    return Path(__file__).resolve().parents[1]


def download(relative: str, destination: Path) -> str:
    url = f"{KODI_REPOSITORY}/{KODI_COMMIT}/{relative}"
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "AddKo-Kodi-vendor/1.0"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
    if not data:
        raise RuntimeError(f"Kodi returned an empty file for {relative}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    destination_root = root() / "third_party" / "kodi_omega" / "upstream"
    manifest: dict[str, object] = {
        "repository": "https://github.com/xbmc/xbmc",
        "commit": KODI_COMMIT,
        "license": "GPL-2.0-or-later",
        "files": {},
    }

    for relative in FILES:
        destination = destination_root / relative
        digest = download(relative, destination)
        manifest["files"][relative] = {  # type: ignore[index]
            "sha256": digest,
            "bytes": destination.stat().st_size,
        }
        print(f"[AddKo] Kodi Omega: {relative}")

    manifest_path = root() / "third_party" / "kodi_omega" / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    print(f"[AddKo] Kodi Omega API snapshot written to {destination_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
