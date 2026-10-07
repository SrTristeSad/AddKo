from __future__ import annotations

from typing import Any, Iterable

from addko_bridge import emit, request
from addko_window import (
    Action,
    Control,
    ControlButton,
    ControlEdit,
    ControlGroup,
    ControlImage,
    ControlLabel,
    ControlList,
    ControlProgress,
    ControlRadioButton,
    ControlSlider,
    ControlSpin,
    ControlTextBox,
    Window,
    WindowDialog,
    WindowXML,
    WindowXMLDialog,
)

NOTIFICATION_INFO = "info"
NOTIFICATION_WARNING = "warning"
NOTIFICATION_ERROR = "error"
NOTIFICATION_DEFAULT = "default"

INPUT_ALPHANUM = 0
ALPHANUM_HIDE_INPUT = 1


class _InfoTag:
    def __init__(self) -> None:
        self.values: dict[str, Any] = {}

    def _set(self, key: str, value: Any) -> None:
        self.values[key] = value

    def setTitle(self, value: str) -> None:
        self._set("title", value)

    def setOriginalTitle(self, value: str) -> None:
        self._set("originaltitle", value)

    def setPlot(self, value: str) -> None:
        self._set("plot", value)

    def setPlotOutline(self, value: str) -> None:
        self._set("plotoutline", value)

    def setTagLine(self, value: str) -> None:
        self._set("tagline", value)

    def setYear(self, value: int) -> None:
        self._set("year", value)

    def setSeason(self, value: int) -> None:
        self._set("season", value)

    def setEpisode(self, value: int) -> None:
        self._set("episode", value)

    def setMediaType(self, value: str) -> None:
        self._set("mediatype", value)

    def setGenres(self, value: Iterable[str]) -> None:
        self._set("genre", list(value))

    def setDirectors(self, value: Iterable[str]) -> None:
        self._set("director", list(value))

    def setWriters(self, value: Iterable[str]) -> None:
        self._set("writer", list(value))

    def setStudios(self, value: Iterable[str]) -> None:
        self._set("studio", list(value))

    def setCountries(self, value: Iterable[str]) -> None:
        self._set("country", list(value))

    def setDuration(self, value: int) -> None:
        self._set("duration", value)

    def setPremiered(self, value: str) -> None:
        self._set("premiered", value)

    def setDateAdded(self, value: str) -> None:
        self._set("dateadded", value)

    def setRating(self, value: float, votes: int = 0, type: str = "default", isDefault: bool = False) -> None:
        self._set("rating", value)
        self._set("votes", votes)

    def setUniqueIDs(self, values: dict[str, str], defaultuniqueid: str = "") -> None:
        self._set("uniqueids", dict(values))
        if defaultuniqueid:
            self._set("defaultuniqueid", defaultuniqueid)


class VideoInfoTag(_InfoTag):
    pass


class MusicInfoTag(_InfoTag):
    def setArtist(self, value: str) -> None:
        self._set("artist", value)

    def setAlbum(self, value: str) -> None:
        self._set("album", value)

    def setAlbumArtist(self, value: str) -> None:
        self._set("albumartist", value)

    def setTrack(self, value: int) -> None:
        self._set("track", value)

    def setDisc(self, value: int) -> None:
        self._set("disc", value)


class ListItem:
    def __init__(self, label: str = "", label2: str = "", path: str = "", offscreen: bool = False) -> None:
        self.label = label or ""
        self.label2 = label2 or ""
        self.path = path or ""
        self.art: dict[str, str] = {}
        self.properties: dict[str, str] = {}
        self.info: dict[str, Any] = {}
        self.mime_type: str | None = None
        self.subtitles: list[str] = []
        self.context_menu: list[tuple[str, str]] = []
        self.video_info = VideoInfoTag()
        self.audio_info = MusicInfoTag()

    def setLabel(self, value: str) -> None:
        self.label = value or ""

    def getLabel(self) -> str:
        return self.label

    def setLabel2(self, value: str) -> None:
        self.label2 = value or ""

    def getLabel2(self) -> str:
        return self.label2

    def setPath(self, value: str) -> None:
        self.path = value or ""

    def getPath(self) -> str:
        return self.path

    def setArt(self, values: dict[str, str]) -> None:
        self.art.update({str(key): str(value) for key, value in values.items()})

    def getArt(self, key: str) -> str:
        return self.art.get(key, "")

    def setInfo(self, type: str, infoLabels: dict[str, Any]) -> None:
        self.info.update(infoLabels or {})

    def setProperty(self, key: str, value: Any) -> None:
        self.properties[str(key)] = str(value)

    def getProperty(self, key: str) -> str:
        return self.properties.get(str(key), "")

    def clearProperty(self, key: str) -> None:
        self.properties.pop(str(key), None)

    def setMimeType(self, value: str) -> None:
        self.mime_type = value

    def setContentLookup(self, enable: bool) -> None:
        self.properties["ContentLookup"] = "true" if enable else "false"

    def setSubtitles(self, values: Iterable[str]) -> None:
        self.subtitles = [str(value) for value in values]

    def addContextMenuItems(self, items: Iterable[tuple[str, str]], replaceItems: bool = False) -> None:
        if replaceItems:
            self.context_menu.clear()
        self.context_menu.extend((str(label), str(command)) for label, command in items)

    def addStreamInfo(self, type: str, values: dict[str, Any]) -> None:
        streams = self.info.setdefault("streams", {})
        streams.setdefault(type, []).append(dict(values))

    def setUniqueIDs(self, values: dict[str, str], defaultrating: str = "") -> None:
        self.video_info.setUniqueIDs(values, defaultrating)

    def setRating(self, type: str, rating: float, votes: int = 0, defaultt: bool = False) -> None:
        self.info.setdefault("ratings", {})[str(type)] = {
            "rating": rating,
            "votes": votes,
            "default": defaultt,
        }

    def getVideoInfoTag(self) -> VideoInfoTag:
        return self.video_info

    def getMusicInfoTag(self) -> MusicInfoTag:
        return self.audio_info

    def to_addko_dict(self) -> dict[str, Any]:
        return {
            "label": self.label,
            "label2": self.label2,
            "path": self.path,
            "art": dict(self.art),
            "properties": dict(self.properties),
            "info": dict(self.info),
            "video_info": dict(self.video_info.values),
            "audio_info": dict(self.audio_info.values),
            "mime_type": self.mime_type,
            "subtitles": list(self.subtitles),
            "context_menu": [
                {"label": label, "command": command}
                for label, command in self.context_menu
            ],
        }


class Dialog:
    def notification(self, heading: str, message: str, icon: str = NOTIFICATION_INFO, time: int = 5000, sound: bool = True) -> None:
        emit("xbmcgui.Dialog.notification", heading=heading, message=message, icon=icon, time=time, sound=sound)

    def ok(self, heading: str, message: str, *lines: str) -> bool:
        return bool(request(
            "xbmcgui.Dialog.ok",
            default=True,
            heading=heading,
            message="\n".join([message, *lines]).strip(),
        ))

    def yesno(self, heading: str, message: str, *args: Any, **kwargs: Any) -> bool:
        return bool(request("xbmcgui.Dialog.yesno", default=False, heading=heading, message=message))

    def select(self, heading: str, list: Iterable[Any], *args: Any, **kwargs: Any) -> int:
        labels = [item.getLabel() if hasattr(item, "getLabel") else str(item) for item in list]
        value = request("xbmcgui.Dialog.select", default=-1, heading=heading, options=labels)
        try:
            return int(value)
        except (TypeError, ValueError):
            return -1

    def contextmenu(self, list: Iterable[str]) -> int:
        value = request(
            "xbmcgui.Dialog.contextmenu",
            default=-1,
            options=[str(item) for item in list],
        )
        try:
            return int(value)
        except (TypeError, ValueError):
            return -1

    def input(self, heading: str, defaultt: str = "", type: int = INPUT_ALPHANUM, option: int = 0, *args: Any, **kwargs: Any) -> str:
        value = request(
            "xbmcgui.Dialog.input",
            default=defaultt,
            heading=heading,
            default_text=defaultt,
            input_type=type,
            option=option,
        )
        return defaultt if value is None else str(value)

    def textviewer(self, heading: str, text: str, usemono: bool = False) -> None:
        request(
            "xbmcgui.Dialog.textviewer",
            default=True,
            heading=heading,
            text=text,
            usemono=usemono,
        )


class DialogProgress:
    def __init__(self) -> None:
        self._canceled = False

    def create(self, heading: str, message: str = "", *lines: str) -> None:
        emit("xbmcgui.DialogProgress.create", heading=heading, message=message)

    def update(self, percent: int, message: str = "", *lines: str) -> None:
        emit("xbmcgui.DialogProgress.update", percent=percent, message=message)

    def close(self) -> None:
        emit("xbmcgui.DialogProgress.close")

    def iscanceled(self) -> bool:
        return self._canceled


class DialogProgressBG(DialogProgress):
    pass


class Keyboard:
    def __init__(self, default: str = "", heading: str = "", hidden: bool = False) -> None:
        self._text = default
        self._heading = heading
        self._hidden = hidden
        self._confirmed = False

    def doModal(self, autoclose: int = 0) -> None:
        value = request(
            "xbmcgui.Keyboard.doModal",
            default={"confirmed": False, "text": self._text},
            heading=self._heading,
            default_text=self._text,
            hidden=self._hidden,
            autoclose=autoclose,
        )
        if isinstance(value, dict):
            self._confirmed = bool(value.get("confirmed", False))
            self._text = str(value.get("text", self._text))

    def isConfirmed(self) -> bool:
        return self._confirmed

    def getText(self) -> str:
        return self._text

    def setDefault(self, value: str) -> None:
        self._text = value

    def setHeading(self, value: str) -> None:
        self._heading = value

    def setHiddenInput(self, value: bool) -> None:
        self._hidden = value
