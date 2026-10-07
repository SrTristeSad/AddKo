from __future__ import annotations

from typing import Any, Iterable

from addko_bridge import emit

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
SORT_METHOD_ARTIST_IGNORE_THE = 12
SORT_METHOD_ALBUM = 13
SORT_METHOD_ALBUM_IGNORE_THE = 14
SORT_METHOD_GENRE = 15
SORT_METHOD_COUNTRY = 16
SORT_METHOD_YEAR = 17
SORT_METHOD_VIDEO_RATING = 18
SORT_METHOD_PROGRAM_COUNT = 19
SORT_METHOD_PLAYLIST_ORDER = 20
SORT_METHOD_EPISODE = 21
SORT_METHOD_VIDEO_TITLE = 22
SORT_METHOD_VIDEO_SORT_TITLE = 23
SORT_METHOD_VIDEO_SORT_TITLE_IGNORE_THE = 24
SORT_METHOD_PRODUCTIONCODE = 25
SORT_METHOD_SONG_RATING = 26
SORT_METHOD_MPAA_RATING = 27
SORT_METHOD_VIDEO_RUNTIME = 28
SORT_METHOD_STUDIO = 29
SORT_METHOD_STUDIO_IGNORE_THE = 30
SORT_METHOD_UNSORTED = 40


def _item_dict(listitem: Any) -> dict[str, Any]:
    if hasattr(listitem, "to_addko_dict"):
        return listitem.to_addko_dict()
    raise TypeError("listitem must be an xbmcgui.ListItem")


def addDirectoryItem(handle: int, url: str, listitem: Any, isFolder: bool = False, totalItems: int = 0) -> bool:
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


def endOfDirectory(handle: int, succeeded: bool = True, updateListing: bool = False, cacheToDisc: bool = True) -> None:
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


def setPluginFanart(handle: int, image: str = "", color1: str = "", color2: str = "", color3: str = "") -> None:
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


def addSortMethod(handle: int, sortMethod: int, label2Mask: str = "") -> None:
    emit(
        "xbmcplugin.addSortMethod",
        handle=handle,
        sort_method=sortMethod,
        label2_mask=label2Mask,
    )


def getSetting(handle: int, id: str) -> str:
    from xbmcaddon import Addon

    return Addon().getSetting(id)


def setSetting(handle: int, id: str, value: str) -> None:
    from xbmcaddon import Addon

    Addon().setSetting(id, value)
