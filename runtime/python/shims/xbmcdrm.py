from __future__ import annotations
from typing import Any
from addko_bridge import emit,request
from kodi_proxy import module_getattr
CRYPTO_SESSION_SYSTEM_NONE=0
CRYPTO_SESSION_SYSTEM_WIDEVINE=1
CRYPTO_SESSION_SYSTEM_PLAYREADY=2
class CryptoSession:
    def __init__(self,keySystem:str,cipherAlgorithm:str="",macAlgorithm:str="")->None:
        self.keySystem=keySystem; self.cipherAlgorithm=cipherAlgorithm; self.macAlgorithm=macAlgorithm; self._properties={}
        emit("xbmcdrm.CryptoSession.create",key_system=keySystem,cipher_algorithm=cipherAlgorithm,mac_algorithm=macAlgorithm)
    def GetKeyRequest(self,init:bytes,mimeType:str,offlineKey:bool=False,optionalParameters:dict[str,str]|None=None)->bytes:
        emit("xbmcdrm.CryptoSession.GetKeyRequest",mime_type=mimeType,offline_key=offlineKey,optional_parameters=optionalParameters or {}); return b""
    def GetPropertyString(self,name:str)->str: return self._properties.get(str(name),"")
    def ProvideKeyResponse(self,response:bytes)->str: emit("xbmcdrm.CryptoSession.ProvideKeyResponse",response_size=len(response)); return ""
    def RemoveKeys(self)->None: emit("xbmcdrm.CryptoSession.RemoveKeys")
    def RestoreKeys(self,keySetId:bytes)->None: emit("xbmcdrm.CryptoSession.RestoreKeys",key_set_id_size=len(keySetId))
    def SetPropertyString(self,name:str,value:str)->None: self._properties[str(name)]=str(value); emit("xbmcdrm.CryptoSession.SetPropertyString",name=str(name),value=str(value))
    def Encrypt(self,keyId:bytes,input:bytes,iv:bytes)->bytes: emit("xbmcdrm.CryptoSession.Encrypt",input_size=len(input)); return b""
    def Decrypt(self,keyId:bytes,input:bytes,iv:bytes)->bytes: emit("xbmcdrm.CryptoSession.Decrypt",input_size=len(input)); return b""
    def Sign(self,keyId:bytes,message:bytes)->bytes: emit("xbmcdrm.CryptoSession.Sign",message_size=len(message)); return b""
    def Verify(self,keyId:bytes,message:bytes,signature:bytes)->bool: emit("xbmcdrm.CryptoSession.Verify",message_size=len(message)); return False
def __getattr__(name:str)->Any: return module_getattr("xbmcdrm",name)
