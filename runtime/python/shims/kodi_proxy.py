from __future__ import annotations
from typing import Any, Callable
from addko_bridge import emit, request

def _serialize(value: Any) -> Any:
    if value is None or isinstance(value, (bool, int, float, str)): return value
    if isinstance(value, bytes): return {"__bytes__": True, "length": len(value)}
    if isinstance(value, (list, tuple, set)): return [_serialize(item) for item in value]
    if isinstance(value, dict): return {str(key): _serialize(item) for key, item in value.items()}
    if hasattr(value, "to_addko_dict"):
        try: return value.to_addko_dict()
        except Exception: pass
    return repr(value)

def _default_for(name: str) -> Any:
    lowered=name.lower()
    if lowered.startswith(("is","has","can","was","should")): return False
    if lowered.startswith(("getitems","getlabels","getstreams","getsubtitles")): return []
    if lowered.startswith(("getproperties","getart","getuniqueids","getratings")): return {}
    if lowered.startswith(("getid","getwidth","getheight","getposition","getpercent","getsize","size")): return 0
    if lowered.startswith(("gettime","gettotaltime","getduration","getrating")): return 0.0
    if lowered.startswith(("get","translate","validate","make")): return ""
    if lowered.startswith(("set","add","clear","close","update","remove","reset","select","show","hide","do","on")): return None
    return None

def module_getattr(module_name: str, name: str) -> Any:
    if not name or name.startswith("__"): raise AttributeError(name)
    if name.isupper():
        emit("kodi.compat.missingConstant", module=module_name, name=name, fallback=0); return 0
    if name[:1].isupper(): return _dynamic_class(module_name,name)
    def function(*args: Any, **kwargs: Any) -> Any:
        return request("kodi.compat.call", default=_default_for(name), module=module_name, name=name, args=_serialize(args), kwargs=_serialize(kwargs))
    function.__name__=name; function.__qualname__=f"{module_name}.{name}"; return function

def _dynamic_class(module_name: str, class_name: str) -> type:
    class KodiDynamicObject:
        def __init__(self,*args:Any,**kwargs:Any)->None:
            self._kodi_module=module_name; self._kodi_class=class_name; self._kodi_args=args; self._kodi_kwargs=kwargs
            emit("kodi.compat.create",module=module_name,class_name=class_name,args=_serialize(args),kwargs=_serialize(kwargs))
        def __getattr__(self,method_name:str)->Callable[...,Any]:
            if method_name.startswith("__"): raise AttributeError(method_name)
            def method(*args:Any,**kwargs:Any)->Any:
                return request("kodi.compat.method",default=_default_for(method_name),module=self._kodi_module,class_name=self._kodi_class,method=method_name,constructor_args=_serialize(self._kodi_args),constructor_kwargs=_serialize(self._kodi_kwargs),args=_serialize(args),kwargs=_serialize(kwargs))
            method.__name__=method_name; return method
        def __repr__(self)->str: return f"<{module_name}.{class_name} AddKo compatibility proxy>"
    KodiDynamicObject.__name__=class_name; KodiDynamicObject.__qualname__=class_name; KodiDynamicObject.__module__=module_name
    return KodiDynamicObject
