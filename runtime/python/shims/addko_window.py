from addko_bridge import request
class Control:
    def __init__(self,*a,**k): self.id=int(k.get('id',0) or 0); self.label=''; self.label2=''; self.visible=True; self.enabled=True
    def getId(self): return self.id
    def setVisible(self,v): self.visible=bool(v)
    def setEnabled(self,v): self.enabled=bool(v)
    def setLabel(self,v): self.label=str(v)
    def getLabel(self): return self.label
class ControlLabel(Control): pass
class ControlButton(Control): pass
class ControlImage(Control): pass
class ControlProgress(Control):
    def setPercent(self,v): self.percent=float(v)
class ControlRadioButton(Control):
    def setSelected(self,v): self.selected=bool(v)
    def isSelected(self): return getattr(self,'selected',False)
class ControlSlider(ControlProgress): pass
class ControlEdit(Control):
    def setText(self,v): self.label2=str(v)
    def getText(self): return self.label2
class ControlList(Control):
    def __init__(self,*a,**k): super().__init__(*a,**k); self.items=[]; self.position=0
    def addItem(self,item): self.items.append(item)
    def addItems(self,items): self.items.extend(items)
    def reset(self): self.items=[]
    def getSelectedPosition(self): return self.position
    def getSelectedItem(self): return self.items[self.position] if self.items else None
class WindowXML:
    def __init__(self,xmlFilename='',scriptPath='',defaultSkin='Default',defaultRes='720p',isMedia=False,*a,**k): self.xmlFilename=xmlFilename; self.scriptPath=scriptPath; self.controls={}; self.closed=False
    def onInit(self): pass
    def onClick(self,controlId): pass
    def onAction(self,action): pass
    def onFocus(self,controlId): pass
    def getControl(self,id):
        id=int(id)
        if id not in self.controls:
            c=ControlButton(); c.id=id; self.controls[id]=c
        return self.controls[id]
    def close(self): self.closed=True
    def doModal(self):
        self.onInit()
        if self.closed: return
        controls=[{'id':c.id,'type':'button','label':getattr(c,'label',''),'label2':getattr(c,'label2',''),'visible':getattr(c,'visible',True),'enabled':getattr(c,'enabled',True)} for c in self.controls.values()]
        r=request('xbmcgui.WindowXML.doModal',title='',controls=controls,list_items=[],width=1280,height=720,default={'action':'close'}) or {}
        if r.get('action')=='click': self.onClick(int(r.get('control_id',-1)))
class WindowXMLDialog(WindowXML): pass
