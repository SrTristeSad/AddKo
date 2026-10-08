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

# Kodi notification icons.
NOTIFICATION_INFO = "info"
NOTIFICATION_WARNING = "warning"
NOTIFICATION_ERROR = "error"
NOTIFICATION_DEFAULT = "default"

# Kodi Dialog input constants. These values come from
# xbmc/interfaces/legacy/Dialog.h.
INPUT_ALPHANUM = 0
INPUT_NUMERIC = 1
INPUT_DATE = 2
INPUT_TIME = 3
INPUT_IPADDRESS = 4
INPUT_PASSWORD = 5
PASSWORD_VERIFY = 1
ALPHANUM_HIDE_INPUT = 2

# Kodi EditControl input constants. These values mirror
# CGUIEditControl::INPUT_TYPE in guilib/GUIEditControl.h.
INPUT_TYPE_READONLY = -1
INPUT_TYPE_TEXT = 0
INPUT_TYPE_NUMBER = 1
INPUT_TYPE_SECONDS = 2
INPUT_TYPE_TIME = 3
INPUT_TYPE_DATE = 4
INPUT_TYPE_IPADDRESS = 5
INPUT_TYPE_PASSWORD = 6
INPUT_TYPE_PASSWORD_MD5 = 7
INPUT_TYPE_SEARCH = 8
INPUT_TYPE_FILTER = 9
INPUT_TYPE_PASSWORD_NUMBER_VERIFY_NEW = 10

# Orientation constants exported by xbmcgui.
HORIZONTAL = 0
VERTICAL = 1

# Common overlay constants used by older addons. Kodi exposes these values as
# SWIG constants; addons normally only compare/pass them back to ListItem.
ICON_OVERLAY_NONE = 0
ICON_OVERLAY_RAR = 1
ICON_OVERLAY_ZIP = 2
ICON_OVERLAY_LOCKED = 3
ICON_OVERLAY_UNWATCHED = 4
ICON_OVERLAY_WATCHED = 5
ICON_OVERLAY_HD = 6

# Common yes/no default-button constants used by modern Kodi addons.
DLG_YESNO_NO_BTN = 0
DLG_YESNO_YES_BTN = 1
DLG_YESNO_CUSTOM_BTN = 2


def getCurrentWindowId() -> int:
    value = request("xbmcgui.getCurrentWindowId", default=10000)
    try:
        return int(value)
    except (TypeError, ValueError):
        return 10000


def getCurrentWindowDialogId() -> int:
    value = request("xbmcgui.getCurrentWindowDialogId", default=0)
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def getScreenWidth() -> int:
    value = request("xbmcgui.getScreenWidth", default=1920)
    try:
        return int(value)
    except (TypeError, ValueError):
        return 1920


def getScreenHeight() -> int:
    value = request("xbmcgui.getScreenHeight", default=1080)
    try:
        return int(value)
    except (TypeError, ValueError):
        return 1080


class _InfoTag:
    def __init__(self) -> None:
        self.values: dict[str, Any] = {}

    def _set(self, key: str, value: Any) -> None:
        self.values[key] = value

    def setTitle(self, value: str) -> None:
        self._set("title", value)

    def setOriginalTitle(self, value: str) -> None:
        self._set("originaltitle", value)

    def setSortTitle(self, value: str) -> None:
        self._set("sorttitle", value)

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

    def setPlaycount(self, value: int) -> None:
        self._set("playcount", value)

    def setMpaa(self, value: str) -> None:
        self._set("mpaa", value)

    def setTrailer(self, value: str) -> None:
        self._set("trailer", value)

    def setTvShowTitle(self, value: str) -> None:
        self._set("tvshowtitle", value)

    def setIMDBNumber(self, value: str) -> None:
        self._set("imdbnumber", value)

    def setRating(
        self,
        value: float,
        votes: int = 0,
        type: str = "default",
        isDefault: bool = False,
    ) -> None:
        self._set("rating", value)
        self._set("votes", votes)
        self._set("rating_type", type)
        self._set("rating_default", bool(isDefault))

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
    def __init__(
        self,
        label: str = "",
        label2: str = "",
        path: str = "",
        offscreen: bool = False,
    ) -> None:
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
        self._selected = False

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

    def clearProperties(self) -> None:
        self.properties.clear()

    def setMimeType(self, value: str) -> None:
        self.mime_type = value

    def setContentLookup(self, enable: bool) -> None:
        self.properties["ContentLookup"] = "true" if enable else "false"

    def setSubtitles(self, values: Iterable[str]) -> None:
        self.subtitles = [str(value) for value in values]

    def addContextMenuItems(
        self,
        items: Iterable[tuple[str, str]],
        replaceItems: bool = False,
    ) -> None:
        if replaceItems:
            self.context_menu.clear()
        self.context_menu.extend((str(label), str(command)) for label, command in items)

    def addStreamInfo(self, type: str, values: dict[str, Any]) -> None:
        streams = self.info.setdefault("streams", {})
        streams.setdefault(type, []).append(dict(values))

    def setUniqueIDs(self, values: dict[str, str], defaultrating: str = "") -> None:
        self.video_info.setUniqueIDs(values, defaultrating)

    def setRating(
        self,
        type: str,
        rating: float,
        votes: int = 0,
        defaultt: bool = False,
    ) -> None:
        self.info.setdefault("ratings", {})[str(type)] = {
            "rating": rating,
            "votes": votes,
            "default": defaultt,
        }

    def setIsFolder(self, value: bool) -> None:
        self.properties["IsFolder"] = "true" if value else "false"

    def select(self, selected: bool) -> None:
        self._selected = bool(selected)

    def isSelected(self) -> bool:
        return self._selected

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
    def notification(
        self,
        heading: str,
        message: str,
        icon: str = NOTIFICATION_INFO,
        time: int = 5000,
        sound: bool = True,
    ) -> None:
        emit(
            "xbmcgui.Dialog.notification",
            heading=heading,
            message=message,
            icon=icon,
            time=time,
            sound=sound,
        )

    def ok(self, heading: str, message: str, *lines: str) -> bool:
        return bool(
            request(
                "xbmcgui.Dialog.ok",
                default=True,
                heading=heading,
                message="\n".join([message, *lines]).strip(),
            )
        )

    def yesno(
        self,
        heading: str,
        message: str,
        nolabel: str = "",
        yeslabel: str = "",
        autoclose: int = 0,
        defaultbutton: int = DLG_YESNO_NO_BTN,
    ) -> bool:
        return bool(
            request(
                "xbmcgui.Dialog.yesno",
                default=False,
                heading=heading,
                message=message,
                no_label=nolabel,
                yes_label=yeslabel,
                autoclose=autoclose,
                default_button=defaultbutton,
            )
        )

    def yesnocustom(
        self,
        heading: str,
        message: str,
        customlabel: str,
        nolabel: str = "",
        yeslabel: str = "",
        autoclose: int = 0,
        defaultbutton: int = DLG_YESNO_NO_BTN,
    ) -> int:
        value = request(
            "xbmcgui.Dialog.yesnocustom",
            default=-1,
            heading=heading,
            message=message,
            custom_label=customlabel,
            no_label=nolabel,
            yes_label=yeslabel,
            autoclose=autoclose,
            default_button=defaultbutton,
        )
        try:
            return int(value)
        except (TypeError, ValueError):
            return -1

    def select(
        self,
        heading: str,
        list: Iterable[Any],
        autoclose: int = 0,
        preselect: int = -1,
        useDetails: bool = False,
    ) -> int:
        labels = [
            item.getLabel() if hasattr(item, "getLabel") else str(item)
            for item in list
        ]
        value = request(
            "xbmcgui.Dialog.select",
            default=-1,
            heading=heading,
            options=labels,
            autoclose=autoclose,
            preselect=preselect,
            use_details=useDetails,
        )
        try:
            return int(value)
        except (TypeError, ValueError):
            return -1

    def multiselect(
        self,
        heading: str,
        options: Iterable[Any],
        autoclose: int = 0,
        preselect: Iterable[int] | None = None,
        useDetails: bool = False,
    ) -> list[int] | None:
        labels = [
            item.getLabel() if hasattr(item, "getLabel") else str(item)
            for item in options
        ]
        value = request(
            "xbmcgui.Dialog.multiselect",
            default=None,
            heading=heading,
            options=labels,
            autoclose=autoclose,
            preselect=list(preselect or []),
            use_details=useDetails,
        )
        if value is None:
            return None
        if isinstance(value, (list, tuple)):
            result: list[int] = []
            for item in value:
                try:
                    result.append(int(item))
                except (TypeError, ValueError):
                    continue
            return result
        return None

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

    def input(
        self,
        heading: str,
        defaultt: str = "",
        type: int = INPUT_ALPHANUM,
        option: int = 0,
        autoclose: int = 0,
    ) -> str:
        hidden = type == INPUT_PASSWORD or (
            type == INPUT_ALPHANUM and (option & ALPHANUM_HIDE_INPUT) != 0
        )
        value = request(
            "xbmcgui.Dialog.input",
            default=defaultt,
            heading=heading,
            default_text=defaultt,
            input_type=type,
            option=option,
            autoclose=autoclose,
            hidden=hidden,
        )
        return defaultt if value is None else str(value)

    def browse(
        self,
        type: int,
        heading: str,
        shares: str,
        mask: str = "",
        useThumbs: bool = False,
        treatAsFolder: bool = False,
        defaultt: str = "",
        enableMultiple: bool = False,
    ) -> Any:
        value = request(
            "xbmcgui.Dialog.browse",
            default=[] if enableMultiple else defaultt,
            browse_type=type,
            heading=heading,
            shares=shares,
            mask=mask,
            use_thumbs=useThumbs,
            treat_as_folder=treatAsFolder,
            default_value=defaultt,
            enable_multiple=enableMultiple,
        )
        if enableMultiple:
            if isinstance(value, (list, tuple)):
                return tuple(str(item) for item in value)
            return tuple()
        return defaultt if value is None else str(value)

    def numeric(self, type: int, heading: str, defaultt: str = "", bHiddenInput: bool = False) -> str:
        value = request(
            "xbmcgui.Dialog.input",
            default=defaultt,
            heading=heading,
            default_text=defaultt,
            input_type=INPUT_NUMERIC,
            option=0,
            autoclose=0,
            hidden=bHiddenInput,
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
        emit(
            "xbmcgui.DialogProgress.create",
            heading=heading,
            message="\n".join([message, *lines]).strip(),
        )

    def update(self, percent: int, message: str = "", *lines: str) -> None:
        emit(
            "xbmcgui.DialogProgress.update",
            percent=percent,
            message="\n".join([message, *lines]).strip(),
        )

    def close(self) -> None:
        emit("xbmcgui.DialogProgress.close")

    def iscanceled(self) -> bool:
        return self._canceled


class DialogProgressBG(DialogProgress):
    pass


class Keyboard:
    def __init__(
        self,
        default: str = "",
        heading: str = "",
        hidden: bool = False,
    ) -> None:
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
