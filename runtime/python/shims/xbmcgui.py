from __future__ import annotations
from addko_bridge import request, emit
from kodi_proxy import module_getattr
INPUT_ALPHANUM=0; INPUT_NUMERIC=1; INPUT_DATE=2; INPUT_TIME=3; INPUT_IPADDRESS=4; INPUT_PASSWORD=5
PASSWORD_VERIFY=1
ALPHANUM_HIDE_INPUT=2
INPUT_TYPE_READONLY=-1; INPUT_TYPE_TEXT=0; INPUT_TYPE_NUMBER=1; INPUT_TYPE_SECONDS=2; INPUT_TYPE_TIME=3; INPUT_TYPE_DATE=4; INPUT_TYPE_IPADDRESS=5; INPUT_TYPE_PASSWORD=6; INPUT_TYPE_PASSWORD_MD5=7; INPUT_TYPE_SEARCH=8; INPUT_TYPE_FILTER=9; INPUT_TYPE_PASSWORD_NUMBER_VERIFY_NEW=10
class ListItem:
    def __init__(self,label='',label2='',path='',offscreen=False): self.label=str(label); self.label2=str(label2); self.path=str(path); self.art={}; self.properties={}; self.info={}; self.video_info={}; self.audio_info={}; self.mime_type=None; self.subtitles=[]; self.context_menu=[]
    def setLabel(self,v): self.label=str(v)
    def getLabel(self): return self.label
    def setLabel2(self,v): self.label2=str(v)
    def getLabel2(self): return self.label2
    def setPath(self,v): self.path=str(v)
    def getPath(self): return self.path
    def setArt(self,v): self.art.update({str(k):str(x) for k,x in dict(v).items()})
    def setProperty(self,k,v): self.properties[str(k)]=str(v)
    def getProperty(self,k): return self.properties.get(str(k),'')
    def setInfo(self,type,infoLabels): self.info.update(dict(infoLabels))
    def setMimeType(self,v): self.mime_type=str(v)
    def setSubtitles(self,v): self.subtitles=[str(x) for x in v]
    def addContextMenuItems(self,items,replaceItems=False):
        if replaceItems: self.context_menu=[]
        for label,cmd in items: self.context_menu.append({'label':str(label),'command':str(cmd)})
    def setContentLookup(self,*a,**k): pass
    def setUniqueIDs(self,*a,**k): pass
    def setRatings(self,*a,**k): pass
    def addStreamInfo(self,*a,**k): pass
    def to_addko_dict(self): return {'label':self.label,'label2':self.label2,'path':self.path,'art':self.art,'properties':self.properties,'info':self.info,'video_info':self.video_info,'audio_info':self.audio_info,'mime_type':self.mime_type,'subtitles':self.subtitles,'context_menu':self.context_menu}
class Dialog:
    def ok(self,heading,message,*lines): return bool(request('xbmcgui.Dialog.ok',heading=str(heading),message='\n'.join([str(message),*[str(x) for x in lines if x]]),default=True))
    def yesno(self,heading,message,*a,**k): return bool(request('xbmcgui.Dialog.yesno',heading=str(heading),message=str(message),default=False))
    def select(self,heading,list,*a,**k): return int(request('xbmcgui.Dialog.select',heading=str(heading),options=[str(x) for x in list],default=-1))
    def contextmenu(self,list): return int(request('xbmcgui.Dialog.contextmenu',options=[str(x) for x in list],default=-1))
    def input(self,heading,defaultt='',type=INPUT_ALPHANUM,option=0,*a,**k): return str(request('xbmcgui.Dialog.input',heading=str(heading),default_text=str(defaultt),default=str(defaultt)))
    def textviewer(self,heading,text,*a,**k): return request('xbmcgui.Dialog.textviewer',heading=str(heading),text=str(text),default=True)
    def notification(self,heading,message,icon='',time=5000,sound=True): emit('xbmcgui.Dialog.notification',heading=str(heading),message=str(message),icon=str(icon),time=int(time),sound=bool(sound))
class Keyboard:
    def __init__(self,default='',heading='',hidden=False): self._text=str(default); self.heading=str(heading); self.hidden=hidden; self.confirmed=False
    def doModal(self,*a,**k):
        r=request('xbmcgui.Keyboard.doModal',heading=self.heading,default_text=self._text,hidden=self.hidden,default={'confirmed':False,'text':self._text}) or {}; self.confirmed=bool(r.get('confirmed')); self._text=str(r.get('text',self._text))
    def isConfirmed(self): return self.confirmed
    def getText(self): return self._text
    def setDefault(self,v): self._text=str(v)
    def setHeading(self,v): self.heading=str(v)
    def setHiddenInput(self,v): self.hidden=bool(v)
class DialogProgress:
    def create(self,*a,**k): pass
    def update(self,*a,**k): pass
    def close(self): pass
    def iscanceled(self): return False
class Window:
    _props={}
    def __init__(self,id=0): self.id=id
    def setProperty(self,k,v): self._props[str(k)]=str(v)
    def getProperty(self,k): return self._props.get(str(k),'')
    def clearProperty(self,k): self._props.pop(str(k),None)
    def clearProperties(self): self._props.clear()
try:
    from addko_window import WindowXML, WindowXMLDialog, Control, ControlLabel, ControlButton, ControlImage, ControlList, ControlProgress, ControlRadioButton, ControlSlider, ControlEdit
except Exception:
    class WindowXML: pass
    class WindowXMLDialog(WindowXML): pass


def getCurrentWindowId(): return int(request("xbmcgui.getCurrentWindowId",default=10000) or 10000)
def getCurrentWindowDialogId(): return int(request("xbmcgui.getCurrentWindowDialogId",default=9999) or 9999)
def getScreenWidth(): return int(request("xbmcgui.getScreenWidth",default=1920) or 1920)
def getScreenHeight(): return int(request("xbmcgui.getScreenHeight",default=1080) or 1080)
def __getattr__(name): return module_getattr("xbmcgui",name)
