from __future__ import annotations
import itertools,json,os,sys,threading
from pathlib import Path
from typing import Any
PROTOCOL_PREFIX="ADDKO_RPC "
_context_cache:dict[str,Any]|None=None
_context_cache_source:str|None=None
_request_ids=itertools.count(1)
_request_lock=threading.Lock()

def emit(method:str,**params:Any)->None:
    print(PROTOCOL_PREFIX+json.dumps({"method":method,"params":params},ensure_ascii=False),flush=True)

def _context_source()->str|None:
    local=getattr(sys,"_addko_context_file",None)
    if local: return str(local)
    env=os.environ.get("ADDKO_CONTEXT_FILE")
    return str(env) if env else None

def reset_context_cache()->None:
    global _context_cache,_context_cache_source
    _context_cache=None; _context_cache_source=None

def request(method:str,default:Any=None,**params:Any)->Any:
    if not _context_source(): return default
    with _request_lock:
        request_id=next(_request_ids)
        message={"method":method,"params":params,"request_id":request_id,"expects_response":True,"default":default}
        print(PROTOCOL_PREFIX+json.dumps(message,ensure_ascii=False),flush=True)
        line=sys.stdin.readline()
        if not line: return default
        try: response=json.loads(line)
        except json.JSONDecodeError: return default
        if response.get("request_id")!=request_id: return default
        return response.get("result",default)

def context()->dict[str,Any]:
    global _context_cache,_context_cache_source
    source=_context_source()
    if not source: raise RuntimeError("AddKo invocation context is not configured")
    if _context_cache is None or _context_cache_source!=source:
        with Path(source).open("r",encoding="utf-8") as handle: value=json.load(handle)
        if not isinstance(value,dict): raise RuntimeError("AddKo invocation context must be a JSON object")
        _context_cache=value; _context_cache_source=source
    return _context_cache

def special_path(value:str)->str:
    if not value.startswith("special://"): return value
    mappings=context().get("special_paths",{})
    if not isinstance(mappings,dict): return value
    for key,target in sorted(mappings.items(),key=lambda item:len(str(item[0])),reverse=True):
        key=str(key); prefix=key if key.endswith("/") else key+"/"
        if value==key.rstrip("/"): return str(target)
        if value.startswith(prefix): return str(Path(str(target))/value[len(prefix):])
    return value
