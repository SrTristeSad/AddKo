from __future__ import annotations

import time
from typing import Any

from addko_bridge import emit, request, special_path
from kodi_proxy import module_getattr

LOGDEBUG = 0
LOGINFO = 1
LOGWARNING = 2
LOGERROR = 3
LOGFATAL = 4
LOGNONE = 5

ISO_639_1 = 0
ISO_639_2 = 1
ENGLISH_NAME = 2
ISO_NAME = 3

PLAYLIST_MUSIC = 0
PLAYLIST_VIDEO = 1

# Values documented by Kodi's xbmc.getDVDState().
DRIVE_NOT_READY = 1
TRAY_OPEN = 16
TRAY_CLOSED_NO_MEDIA = 64
TRAY_CLOSED_MEDIA_PRESENT = 96


def log(msg: Any, level: int = LOGDEBUG) -> None:
    emit("xbmc.log", message=str(msg), level=level)


def sleep(timemillis: int) -> None:
    time.sleep(max(0, timemillis) / 1000.0)


def shutdown() -> None:
    emit("xbmc.shutdown")


def restart() -> None:
    emit("xbmc.restart")


def executescript(script: str) -> None:
    emit("xbmc.executescript", script=str(script))


def executebuiltin(function: str, wait: bool = False) -> None:
    emit("xbmc.executebuiltin", function=function, wait=bool(wait))


def executeJSONRPC(jsonrpccommand: str) -> str:
    return str(
        request(
            "xbmc.executeJSONRPC",
            default='{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"AddKo bridge unavailable"}}',
            request=jsonrpccommand,
        )
    )


def getLocalizedString(id: int) -> str:
    value = request("xbmc.getLocalizedString", default=str(id), string_id=int(id))
    return str(id) if value is None else str(value)


def getInfoLabel(infotag: str) -> str:
    value = request("xbmc.getInfoLabel", default="", infotag=infotag)
    return "" if value is None else str(value)


def getInfoImage(infotag: str) -> str:
    value = request("xbmc.getInfoImage", default="", infotag=infotag)
    return "" if value is None else str(value)


def getCondVisibility(condition: str) -> bool:
    return bool(request("xbmc.getCondVisibility", default=False, condition=condition))


def getLanguage(format: int = ENGLISH_NAME, region: bool = False) -> str:
    if format == ISO_639_1:
        return "en-US" if region else "en"
    if format == ISO_639_2:
        return "eng-US" if region else "eng"
    return "English (United States)" if region and format == ENGLISH_NAME else "English"


def getIPAddress() -> str:
    value = request("xbmc.getIPAddress", default="127.0.0.1")
    return "127.0.0.1" if value is None else str(value)


def getDVDState() -> int:
    value = request("xbmc.getDVDState", default=DRIVE_NOT_READY)
    try:
        return int(value)
    except (TypeError, ValueError):
        return DRIVE_NOT_READY


def getFreeMem() -> int:
    value = request("xbmc.getFreeMem", default=0)
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def getRegion(id: str) -> str:
    defaults = {
        "dateshort": "%d/%m/%Y",
        "datelong": "%A, %d %B %Y",
        "time": "%H:%M:%S",
        "meridiem": "AM/PM",
        "tempunit": "C",
        "speedunit": "km/h",
    }
    value = request("xbmc.getRegion", default=defaults.get(id.lower(), ""), region_id=id)
    return defaults.get(id.lower(), "") if value is None else str(value)


def getSkinDir() -> str:
    value = request("xbmc.getSkinDir", default="skin.addko")
    return "skin.addko" if value is None else str(value)


def getSupportedMedia(mediaType: str) -> str:
    defaults = {
        "video": ".avi|.mkv|.mp4|.m4v|.mov|.ts|.m2ts|.webm|.flv|.strm",
        "music": ".mp3|.aac|.m4a|.flac|.ogg|.wav|.wma|.opus",
        "picture": ".jpg|.jpeg|.png|.gif|.bmp|.webp",
    }
    return defaults.get(str(mediaType).lower(), "")


def translatePath(path: str) -> str:
    return special_path(path)


def makeLegalFilename(filename: str, fatX: bool = True) -> str:
    return filename


def validatePath(path: str) -> str:
    return special_path(path)


class Keyboard:
    """Compatibility wrapper for the historical xbmc.Keyboard API."""

    def __init__(self, default: str = "", heading: str = "", hidden: bool = False) -> None:
        from xbmcgui import Keyboard as GuiKeyboard

        self._keyboard = GuiKeyboard(default, heading, hidden)

    def doModal(self, autoclose: int = 0) -> None:
        self._keyboard.doModal(autoclose)

    def isConfirmed(self) -> bool:
        return self._keyboard.isConfirmed()

    def getText(self) -> str:
        return self._keyboard.getText()

    def setDefault(self, value: str) -> None:
        self._keyboard.setDefault(value)

    def setHeading(self, value: str) -> None:
        self._keyboard.setHeading(value)

    def setHiddenInput(self, value: bool) -> None:
        self._keyboard.setHiddenInput(value)


class Monitor:
    def __init__(self) -> None:
        self._abort = False

    def abortRequested(self) -> bool:
        remote = request("xbmc.Monitor.abortRequested", default=None)
        if remote is not None:
            self._abort = bool(remote)
        return self._abort

    def waitForAbort(self, timeout: float = -1) -> bool:
        if self.abortRequested():
            return True

        remote = request(
            "xbmc.Monitor.waitForAbort",
            default=None,
            timeout=timeout,
        )
        if remote is not None:
            self._abort = bool(remote)
            return self._abort

        if timeout is not None and timeout > 0:
            time.sleep(timeout)
        return self.abortRequested()

    def onSettingsChanged(self) -> None:
        pass

    def onNotification(self, sender: str, method: str, data: str) -> None:
        pass

    def onScreensaverActivated(self) -> None:
        pass

    def onScreensaverDeactivated(self) -> None:
        pass

    def onDPMSActivated(self) -> None:
        pass

    def onDPMSDeactivated(self) -> None:
        pass

    def onDatabaseUpdated(self, database: str) -> None:
        pass

    def onDatabaseScanStarted(self, database: str) -> None:
        pass

    def onCleanStarted(self, library: str) -> None:
        pass

    def onCleanFinished(self, library: str) -> None:
        pass

    def onScanStarted(self, library: str) -> None:
        pass

    def onScanFinished(self, library: str) -> None:
        pass

    def onAbortRequested(self) -> None:
        self._abort = True


class Player:
    def __init__(self, core: int = 0) -> None:
        self._playing = False
        self._file = ""

    def play(
        self,
        item: Any = "",
        listitem: Any = None,
        windowed: bool = False,
        startpos: int = -1,
    ) -> None:
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
        value = request("xbmc.Player.getTime", default=0.0)
        try:
            return float(value)
        except (TypeError, ValueError):
            return 0.0

    def getTotalTime(self) -> float:
        value = request("xbmc.Player.getTotalTime", default=0.0)
        try:
            return float(value)
        except (TypeError, ValueError):
            return 0.0

    def seekTime(self, seekTime: float) -> None:
        emit("xbmc.Player.seekTime", time=seekTime)

    def setSubtitles(self, subtitleFile: str) -> None:
        emit("xbmc.Player.setSubtitles", path=subtitleFile)

    def showSubtitles(self, visible: bool) -> None:
        emit("xbmc.Player.showSubtitles", visible=bool(visible))

    def getSubtitles(self) -> str:
        value = request("xbmc.Player.getSubtitles", default="")
        return "" if value is None else str(value)

    def onPlayBackStarted(self) -> None:
        pass

    def onAVStarted(self) -> None:
        pass

    def onAVChange(self) -> None:
        pass

    def onPlayBackEnded(self) -> None:
        pass

    def onPlayBackStopped(self) -> None:
        pass

    def onPlayBackError(self) -> None:
        pass

    def onPlayBackPaused(self) -> None:
        pass

    def onPlayBackResumed(self) -> None:
        pass

    def onPlayBackSeek(self, time: int, seekOffset: int) -> None:
        pass

    def onPlayBackSeekChapter(self, chapter: int) -> None:
        pass

    def onQueueNextItem(self) -> None:
        pass


class PlayList:
    def __init__(self, playList: int) -> None:
        self.playList = playList
        self._items: list[tuple[str, Any]] = []
        self._position = 0

    def add(self, url: str, listitem: Any = None, index: int = -1) -> None:
        value = (url, listitem)
        if index < 0 or index >= len(self._items):
            self._items.append(value)
        else:
            self._items.insert(index, value)

    def clear(self) -> None:
        self._items.clear()
        self._position = 0

    def size(self) -> int:
        return len(self._items)

    def remove(self, filename: str) -> None:
        self._items = [item for item in self._items if item[0] != filename]

    def getposition(self) -> int:
        return self._position

    def __len__(self) -> int:
        return len(self._items)

    def __getitem__(self, index: int) -> Any:
        return self._items[index][1]


def __getattr__(name: str) -> Any:
    return module_getattr("xbmc", name)
