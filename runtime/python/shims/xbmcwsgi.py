from __future__ import annotations
from typing import Any, Iterable, Iterator
from addko_bridge import emit
class WsgiErrorStream:
    def flush(self)->None: return None
    def write(self,value:str)->None:
        message=str(value).rstrip("\n")
        if message: emit("xbmc.log",message=message,level=3)
    def writelines(self,seq:Iterable[str])->None: self.write("".join(str(v) for v in seq))
class WsgiInputStreamIterator:
    def __init__(self,data:str|bytes=b"")->None:
        if isinstance(data,bytes): data=data.decode("latin-1")
        self._data=str(data); self._offset=0
    def read(self,size:int=0)->str:
        if self._offset>=len(self._data): return ""
        if size is None or int(size)<=0:
            result=self._data[self._offset:]; self._offset=len(self._data); return result
        end=min(len(self._data),self._offset+int(size)); result=self._data[self._offset:end]; self._offset=end; return result
    def readline(self,size:int=0)->str:
        if self._offset>=len(self._data): return ""
        newline=self._data.find("\n",self._offset); end=len(self._data) if newline<0 else newline+1
        if size is not None and int(size)>0: end=min(end,self._offset+int(size))
        result=self._data[self._offset:end]; self._offset=end; return result
    def readlines(self,sizehint:int=0)->list[str]:
        lines=[]; consumed=0
        while self._offset<len(self._data):
            line=self.readline()
            if not line: break
            lines.append(line); consumed+=len(line)
            if sizehint is not None and int(sizehint)>0 and consumed>=int(sizehint): break
        return lines
    def __iter__(self)->Iterator[str]: return self
    def __next__(self)->str:
        value=self.readline()
        if not value: raise StopIteration
        return value
class WsgiInputStream(WsgiInputStreamIterator): pass
class WsgiResponseBody:
    def __init__(self)->None: self._chunks=[]
    def __call__(self,data:str)->None: self._chunks.append(str(data))
    @property
    def data(self)->str: return "".join(self._chunks)
class WsgiResponse:
    def __init__(self)->None:
        self.called=False; self.status="500 Internal Server Error"; self.response_headers=[]; self.body=WsgiResponseBody()
    def __call__(self,status:str,response_headers:Iterable[tuple[str,str]],exc_info:Any=None)->WsgiResponseBody:
        if self.called and exc_info is None: raise RuntimeError("start_response called twice without exc_info")
        normalized=str(status)
        if len(normalized)<4 or not normalized[:3].isdigit(): raise ValueError(f"invalid WSGI status: {normalized!r}")
        headers=[]
        for header in response_headers:
            if not isinstance(header,(tuple,list)) or len(header)!=2: raise TypeError("response_headers must contain (name, value) pairs")
            headers.append((str(header[0]),str(header[1])))
        self.called=True; self.status=normalized; self.response_headers=headers
        emit("xbmcwsgi.WsgiResponse.start",status=self.status,headers=[list(h) for h in headers]); return self.body
__all__=["WsgiErrorStream","WsgiInputStreamIterator","WsgiInputStream","WsgiResponseBody","WsgiResponse"]
