#!/usr/bin/env python3
"""Fast smoke test for the Python Kodi compatibility modules shipped by AddKo."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHIMS = ROOT / "runtime" / "python" / "shims"
sys.path.insert(0, str(SHIMS))

import xbmc  # noqa: E402
import xbmcaddon  # noqa: E402,F401
import xbmcgui  # noqa: E402
import xbmcplugin  # noqa: E402
import xbmcvfs  # noqa: E402


def require(module: object, *names: str) -> None:
    missing = [name for name in names if not hasattr(module, name)]
    if missing:
        raise AssertionError(
            f"{getattr(module, '__name__', module)} missing Kodi API: {', '.join(missing)}"
        )


def main() -> int:
    require(
        xbmc,
        "Keyboard",
        "Monitor",
        "Player",
        "PlayList",
        "executebuiltin",
        "executeJSONRPC",
        "getInfoLabel",
        "getCondVisibility",
        "getLanguage",
        "translatePath",
    )
    require(
        xbmcgui,
        "Dialog",
        "Keyboard",
        "ListItem",
        "Window",
        "WindowXML",
        "INPUT_ALPHANUM",
        "INPUT_NUMERIC",
        "INPUT_DATE",
        "INPUT_TIME",
        "INPUT_IPADDRESS",
        "INPUT_PASSWORD",
        "PASSWORD_VERIFY",
        "ALPHANUM_HIDE_INPUT",
        "INPUT_TYPE_PASSWORD",
        "getCurrentWindowId",
        "getScreenWidth",
        "getScreenHeight",
    )
    require(
        xbmcplugin,
        "addDirectoryItem",
        "addDirectoryItems",
        "endOfDirectory",
        "setResolvedUrl",
        "setContent",
        "setPluginCategory",
        "setPluginFanart",
        "setProperty",
        "addSortMethod",
        "SORT_METHOD_NONE",
        "SORT_METHOD_UNSORTED",
        "SORT_METHOD_BITRATE",
    )
    require(
        xbmcvfs,
        "File",
        "Stat",
        "copy",
        "delete",
        "rename",
        "exists",
        "mkdir",
        "mkdirs",
        "rmdir",
        "listdir",
        "makeLegalFilename",
        "translatePath",
        "validatePath",
    )

    assert xbmcgui.INPUT_ALPHANUM == 0
    assert xbmcgui.INPUT_NUMERIC == 1
    assert xbmcgui.INPUT_DATE == 2
    assert xbmcgui.INPUT_TIME == 3
    assert xbmcgui.INPUT_IPADDRESS == 4
    assert xbmcgui.INPUT_PASSWORD == 5
    assert xbmcgui.PASSWORD_VERIFY == 1
    assert xbmcgui.ALPHANUM_HIDE_INPUT == 2

    assert xbmc.DRIVE_NOT_READY == 1
    assert xbmc.TRAY_OPEN == 16
    assert xbmc.TRAY_CLOSED_NO_MEDIA == 64
    assert xbmc.TRAY_CLOSED_MEDIA_PRESENT == 96

    assert xbmcplugin.SORT_METHOD_NONE == 0
    assert xbmcplugin.SORT_METHOD_UNSORTED == 40
    assert xbmcplugin.SORT_METHOD_BITRATE == 43

    keyboard = xbmc.Keyboard("hello", "heading", True)
    assert keyboard.getText() == "hello"

    item = xbmcgui.ListItem(label="Demo", path="https://example.invalid/video.mp4")
    item.setProperty("IsPlayable", "true")
    item.setArt({"thumb": "thumb.png"})
    snapshot = item.to_addko_dict()
    assert snapshot["label"] == "Demo"
    assert snapshot["properties"]["IsPlayable"] == "true"

    with tempfile.TemporaryDirectory(prefix="addko-vfs-") as temporary:
        path = os.path.join(temporary, "hello.txt")
        writer = xbmcvfs.File(path, "w")
        assert writer.write("olá")
        writer.close()
        reader = xbmcvfs.File(path, "r")
        assert reader.read() == "olá"
        reader.close()
        assert xbmcvfs.exists(path)
        assert xbmcvfs.Stat(path).st_size() > 0

    print("[AddKo] Kodi Python shims: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
