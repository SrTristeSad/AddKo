from typing import Any, Iterable
from addko_bridge import emit
from kodi_proxy import module_getattr
SORT_METHOD_NONE=0; SORT_METHOD_LABEL=1; SORT_METHOD_DATE=3; SORT_METHOD_SIZE=4; SORT_METHOD_FILE=5; SORT_METHOD_DURATION=8; SORT_METHOD_TITLE=9; SORT_METHOD_YEAR=17; SORT_METHOD_UNSORTED=40; SORT_METHOD_BITRATE=43
def _item_dict(item: Any)->dict:
    if hasattr(item,'to_addko_dict'): return item.to_addko_dict()
    raise TypeError('listitem must be an xbmcgui.ListItem')
def addDirectoryItem(handle:int,url:str,listitem:Any,isFolder:bool=False,totalItems:int=0)->bool:
    emit('xbmcplugin.addDirectoryItem',handle=handle,url=url,item=_item_dict(listitem),is_folder=bool(isFolder),total_items=totalItems); return True
def addDirectoryItems(handle:int,items:Iterable[Any],totalItems:int=0)->bool:
    out=[]
    for e in items:
        if isinstance(e,(tuple,list)) and len(e)>=2: out.append({'url':str(e[0]),'item':_item_dict(e[1]),'is_folder':bool(e[2]) if len(e)>2 else False})
    emit('xbmcplugin.addDirectoryItems',handle=handle,items=out,total_items=totalItems); return True
def endOfDirectory(handle:int,succeeded:bool=True,updateListing:bool=False,cacheToDisc:bool=True)->None: emit('xbmcplugin.endOfDirectory',handle=handle,succeeded=bool(succeeded),update_listing=bool(updateListing),cache_to_disc=bool(cacheToDisc))
def setResolvedUrl(handle:int,succeeded:bool,listitem:Any)->None: emit('xbmcplugin.setResolvedUrl',handle=handle,succeeded=bool(succeeded),item=_item_dict(listitem))
def setContent(handle:int,content:str)->None: emit('xbmcplugin.setContent',handle=handle,content=content)
def setPluginCategory(handle:int,category:str)->None: emit('xbmcplugin.setPluginCategory',handle=handle,category=category)
def setPluginFanart(handle:int,image:str='',color1:str='',color2:str='',color3:str='')->None: emit('xbmcplugin.setPluginFanart',handle=handle,image=image,color1=color1,color2=color2,color3=color3)
def setProperty(handle:int,key:str,value:str)->None: emit('xbmcplugin.setProperty',handle=handle,key=key,value=value)
def addSortMethod(handle:int,sortMethod:int,label2Mask:str='')->None: emit('xbmcplugin.addSortMethod',handle=handle,sort_method=sortMethod,label2_mask=label2Mask)
def getSetting(handle:int,id:str)->str:
    from xbmcaddon import Addon; return Addon().getSetting(id)
def setSetting(handle:int,id:str,value:str)->None:
    from xbmcaddon import Addon; Addon().setSetting(id,value)


def __getattr__(name): return module_getattr("xbmcplugin",name)
