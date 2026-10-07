from __future__ import annotations

import json
import time
from typing import Any

from addko_bridge import emit, special_path

LOGDEBUG = 0
LOGINFO = 1
LOGWARNING = 2
LOGERROR = 3
LOGFATAL = 4
LOGNONE = 5

ISO_639_1 = 0
ISO_639_2 = 1
ENGLISH_NAME = 2

PLAYLIST_MUSIC = 0
PLAYLIST_VIDEO = 1
TRAY_OPEN = 0
DRIVE_NOT_READY = 1
TRAY_CLOSED_NO_MEDIA = 2
TRAY_CLOSED_MEDIA_PRESENT = 3


def log(msg: Any, level: int = LOGDEBUG) -> None:
    emit("xbmc.log", message=str(msg), level=level)


def sleep(timemillis: int) -> None:
    time.sleep(max(0, timemillis) / 1000.0)


def executebuiltin(function: str, wait: bool = False) -> None:
    emit("xbmc.executebuiltin", function=function, wait=bool(wait))


def executeJSONRPC(jsonrpccommand: str) -> str:
    emit("xbmc.executeJSONRPC", request=jsonrpccommand)
    try:
        request = json.loads(jsonrpccommand)
        request_id = request.get("id", 1) if isinstance(request, dict) else 1
    except json.JSONDecodeError:
        request_id = 1
    return json.dumps(
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {
                "code": -32601,
                "message": "JSON-RPC method not implemented by AddKo yet",
            },
        }
    )


def getInfoLabel(infotag: str) -> str:
    emit("xbmc.getInfoLabel", infotag=infotag)
    return ""


def getCondVisibility(condition: str) -> bool:
    emit("xbmc.getCondVisibility", condition=condition)
    return False


def getLanguage(format: int = ENGLISH_NAME, region: bool = False) -> str:
    if format == ISO_639_1:
        return "en"
    if format == ISO_639_2:
        return "eng"
    return "English"


def getRegion(id: str) -> str:
    defaults = {
        "dateshort": "%d/%m/%Y",
        "datelong": "%A, %d %B %Y",
        "time": "%H:%M:%S",
        "meridiem": "AM/PM",
        "tempunit": "C",
        "speedunit": "km/h",
    }
    return defaults.get(id.lower(), "")


def getSkinDir() -> str:
    return "skin.addko"


def translatePath(path: str) -> str:
    return special_path(path)


def makeLegalFilename(filename: str, fatX: bool = True) -> str:
    return filename


def validatePath(path: str) -> str:
    return special_path(path)


class Monitor:
    def __init__(self) -> None:
        self._abort = False

    def abortRequested(self) -> bool:
        return self._abort

    def waitForAbort(self, timeout: float = -1) -> bool:
        if timeout is not None and timeout > 0:
            time.sleep(timeout)
        return self._abort

    def onSettingsChanged(self) -> None:
        pass

    def onNotification(self, sender: str, method: str, data: str) -> None:
        pass

    def onAbortRequested(self) -> None:
        self._abort = True


class Player:
    def __init__(self, core: int = 0) -> None:
        self._playing = False
        self._file = ""

    def play(self, item: Any = "", listitem: Any = None, windowed: bool = False, startpos: int = -1) -> None:
        path = ""
        if isinstance(item, str):
            path = item
        elif hasattr(item, "getPath"):
            path = item.getPath()
        self._file = path
        self._playing = True
        emit(
            "xbmc.Player.play",
            path=path,
            item=listitem.to_addko_dict() if hasattr(listitem, "to_addko_dict") else None,
            windowed=bool(windowed),
            startpos=startpos,
        )

    def stop(self) -> None:
        self._playing = False
        emit("xbmc.Player.stop")

    def pause(self) -> None:
        emit("xbmc.Player.pause")

    def playnext(self) -> None:
        emit("xbmc.Player.playnext")

    def playprevious(self) -> None:
        emit("xbmc.Player.playprevious")

    def isPlaying(self) -> bool:
        return self._playing

    def isPlayingVideo(self) -> bool:
        return self._playing

    def isPlayingAudio(self) -> bool:
        return False

    def getPlayingFile(self) -> str:
        return self._file

    def getTime(self) -> float:
        return 0.0

    def getTotalTime(self) -> float:
        return 0.0

    def seekTime(self, seekTime: float) -> None:
        emit("xbmc.Player.seekTime", time=seekTime)

    def setSubtitles(self, subtitleFile: str) -> None:
        emit("xbmc.Player.setSubtitles", path=subtitleFile)

    def showSubtitles(self, visible: bool) -> None:
        emit("xbmc.Player.showSubtitles", visible=bool(visible))


class PlayList:
    def __init__(self, playList: int) -> None:
        self.playList = playList
        self._items: list[tuple[str, Any]] = []

    def add(self, url: str, listitem: Any = None, index: int = -1) -> None:
        value = (url, listitem)
        if index < 0 or index >= len(self._items):
            self._items.append(value)
        else:
            self._items.insert(index, value)

    def clear(self) -> None:
        self._items.clear()

    def size(self) -> int:
        return len(self._items)

    def remove(self, filename: str) -> None:
        self._items = [item for item in self._items if item[0] != filename]

    def __len__(self) -> int:
        return len(self._items)
