from __future__ import annotations

from typing import Any, Iterable

from addko_bridge import emit
from kodi_proxy import module_getattr

# Values mirror Kodi's SortMethod enum (xbmc/SortFileItem.h).
SORT_METHOD_NONE = 0
SORT_METHOD_LABEL = 1
SORT_METHOD_LABEL_IGNORE_THE = 2
SORT_METHOD_DATE = 3
SORT_METHOD_SIZE = 4
SORT_METHOD_FILE = 5
SORT_METHOD_DRIVE_TYPE = 6
SORT_METHOD_TRACKNUM = 7
SORT_METHOD_DURATION = 8
SORT_METHOD_TITLE = 9
SORT_METHOD_TITLE_IGNORE_THE = 10
SORT_METHOD_ARTIST = 11
SORT_METHOD_ARTIST_AND_YEAR = 12
SORT_METHOD_ARTIST_IGNORE_THE = 13
SORT_METHOD_ALBUM = 14
SORT_METHOD_ALBUM_IGNORE_THE = 15
SORT_METHOD_GENRE = 16
SORT_METHOD_COUNTRY = 17
SORT_METHOD_YEAR = 18
SORT_METHOD_VIDEO_YEAR = SORT_METHOD_YEAR
SORT_METHOD_VIDEO_RATING = 19
SORT_METHOD_VIDEO_USER_RATING = 20
SORT_METHOD_DATEADDED = 21
SORT_METHOD_PROGRAM_COUNT = 22
SORT_METHOD_PLAYLIST_ORDER = 23
SORT_METHOD_EPISODE = 24
SORT_METHOD_VIDEO_TITLE = 25
SORT_METHOD_VIDEO_SORT_TITLE = 26
SORT_METHOD_VIDEO_SORT_TITLE_IGNORE_THE = 27
SORT_METHOD_PRODUCTIONCODE = 28
SORT_METHOD_SONG_RATING = 29
SORT_METHOD_SONG_USER_RATING = 30
SORT_METHOD_MPAA_RATING = 31
SORT_METHOD_VIDEO_RUNTIME = 32
SORT_METHOD_STUDIO = 33
SORT_METHOD_STUDIO_IGNORE_THE = 34
SORT_METHOD_FULLPATH = 35
SORT_METHOD_LABEL_IGNORE_FOLDERS = 36
SORT_METHOD_LASTPLAYED = 37
SORT_METHOD_PLAYCOUNT = 38
SORT_METHOD_LISTENERS = 39
SORT_METHOD_UNSORTED = 40
SORT_METHOD_CHANNEL = 41
SORT_METHOD_CHANNEL_NUMBER = 42
SORT_METHOD_BITRATE = 43
SORT_METHOD_DATE_TAKEN = 44
SORT_METHOD_CLIENT_CHANNEL_ORDER = 45
SORT_METHOD_TOTAL_DISCS = 46
SORT_METHOD_ORIG_DATE = 47
SORT_METHOD_BPM = 48
SORT_METHOD_VIDEO_ORIGINAL_TITLE = 49
SORT_METHOD_VIDEO_ORIGINAL_TITLE_IGNORE_THE = 50
SORT_METHOD_PROVIDER = 51
SORT_METHOD_USER_PREFERENCE = 52


def _item_dict(listitem: Any) -> dict[str, Any]:
    if hasattr(listitem, "to_addko_dict"):
        return listitem.to_addko_dict()
    raise TypeError("listitem must be an xbmcgui.ListItem")


def addDirectoryItem(
    handle: int,
    url: str,
    listitem: Any,
    isFolder: bool = False,
    totalItems: int = 0,
) -> bool:
    emit(
        "xbmcplugin.addDirectoryItem",
        handle=handle,
        url=url,
        item=_item_dict(listitem),
        is_folder=bool(isFolder),
        total_items=totalItems,
    )
    return True


def addDirectoryItems(handle: int, items: Iterable[Any], totalItems: int = 0) -> bool:
    serialized = []
    for entry in items:
        if not isinstance(entry, (tuple, list)) or len(entry) < 2:
            continue
        url = str(entry[0])
        listitem = entry[1]
        is_folder = bool(entry[2]) if len(entry) > 2 else False
        serialized.append(
            {
                "url": url,
                "item": _item_dict(listitem),
                "is_folder": is_folder,
            }
        )
    emit(
        "xbmcplugin.addDirectoryItems",
        handle=handle,
        items=serialized,
        total_items=totalItems,
    )
    return True


def endOfDirectory(
    handle: int,
    succeeded: bool = True,
    updateListing: bool = False,
    cacheToDisc: bool = True,
) -> None:
    emit(
        "xbmcplugin.endOfDirectory",
        handle=handle,
        succeeded=bool(succeeded),
        update_listing=bool(updateListing),
        cache_to_disc=bool(cacheToDisc),
    )


def setResolvedUrl(handle: int, succeeded: bool, listitem: Any) -> None:
    emit(
        "xbmcplugin.setResolvedUrl",
        handle=handle,
        succeeded=bool(succeeded),
        item=_item_dict(listitem),
    )


def setContent(handle: int, content: str) -> None:
    emit("xbmcplugin.setContent", handle=handle, content=content)


def setPluginCategory(handle: int, category: str) -> None:
    emit("xbmcplugin.setPluginCategory", handle=handle, category=category)


def setPluginFanart(
    handle: int,
    image: str = "",
    color1: str = "",
    color2: str = "",
    color3: str = "",
) -> None:
    emit(
        "xbmcplugin.setPluginFanart",
        handle=handle,
        image=image,
        color1=color1,
        color2=color2,
        color3=color3,
    )


def setProperty(handle: int, key: str, value: str) -> None:
    emit("xbmcplugin.setProperty", handle=handle, key=key, value=value)


def addSortMethod(
    handle: int,
    sortMethod: int,
    labelMask: str = "",
    label2Mask: str = "",
) -> None:
    emit(
        "xbmcplugin.addSortMethod",
        handle=handle,
        sort_method=sortMethod,
        label_mask=labelMask,
        label2_mask=label2Mask,
    )


def getSetting(handle: int, id: str) -> str:
    from xbmcaddon import Addon

    return Addon().getSetting(id)


def setSetting(handle: int, id: str, value: str) -> None:
    from xbmcaddon import Addon

    Addon().setSetting(id, value)


def __getattr__(name: str) -> Any:
    return module_getattr("xbmcplugin", name)
