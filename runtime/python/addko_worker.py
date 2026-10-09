#!/usr/bin/env python3
from __future__ import annotations
import datetime, importlib, json, os, re, sqlite3, sys, traceback
from pathlib import Path
PROTOCOL_PREFIX = "ADDKO_RPC "

def emit(method: str, **params: object) -> None:
    print(PROTOCOL_PREFIX + json.dumps({"method":method,"params":params}, ensure_ascii=False), flush=True)

def _install_kodi_api_fallbacks() -> None:
    from kodi_proxy import module_getattr
    for module_name in ("xbmc","xbmcaddon","xbmcgui","xbmcplugin","xbmcvfs","xbmcdrm","xbmcwsgi"):
        try: module=importlib.import_module(module_name)
        except Exception: continue
        if "__getattr__" in module.__dict__: continue
        def fallback(name:str,_module_name:str=module_name): return module_getattr(_module_name,name)
        module.__getattr__=fallback

def _installed_addons(context:dict[str,object])->dict[str,str]:
    installed={}
    raw=context.get("installed_addons")
    if isinstance(raw,dict):
        for addon_id,version in raw.items():
            value=str(addon_id).strip()
            if value: installed[value]=str(version or "")
    root=Path(str(context.get("addons_root","")))
    if root.is_dir():
        try:
            for child in root.iterdir():
                if child.is_dir() and (child/"addon.xml").is_file(): installed.setdefault(child.name,"")
        except OSError: pass
    return installed

def _install_runtime_overrides(context:dict[str,object])->None:
    try: import xbmc
    except Exception: return
    original=xbmc.getCondVisibility
    rx=re.compile(r"^system\.(?:hasaddon|addonisenabled)\((.+)\)$",re.I)
    def get_cond_visibility(condition:str)->bool:
        m=rx.match(str(condition).strip())
        if m: return m.group(1).strip().strip("\"'").lower() in {x.lower() for x in _installed_addons(context)}
        return bool(original(condition))
    xbmc.getCondVisibility=get_cond_visibility

def _ensure_kodi_addon_database(context:dict[str,object])->None:
    special=context.get("special_paths")
    if not isinstance(special,dict) or not special.get("special://profile"): return
    dbdir=Path(str(special["special://profile"]))/"Database"; dbdir.mkdir(parents=True,exist_ok=True)
    installed=_installed_addons(context); now=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        connection=sqlite3.connect(str(dbdir/"Addons33.db"),timeout=2.0)
        try:
            connection.execute("""CREATE TABLE IF NOT EXISTS installed (id INTEGER PRIMARY KEY, addonID TEXT, enabled BOOLEAN, installDate TEXT, lastUpdated TEXT, lastUsed TEXT, origin TEXT)""")
            columns={str(row[1]) for row in connection.execute("PRAGMA table_info(installed)")}
            for name,typ in (("lastUpdated","TEXT"),("lastUsed","TEXT"),("origin","TEXT")):
                if name not in columns: connection.execute(f"ALTER TABLE installed ADD COLUMN {name} {typ}")
            for addon_id in installed:
                existing=connection.execute("SELECT id FROM installed WHERE addonID=? LIMIT 1",(addon_id,)).fetchone()
                if existing is None:
                    connection.execute("INSERT INTO installed (addonID, enabled, installDate, lastUpdated, origin) VALUES (?, 1, ?, ?, ?)",(addon_id,now,now,"repository.addko"))
                # Preserve the enabled state of existing records.
            connection.commit()
        finally: connection.close()
    except (OSError,sqlite3.Error) as error:
        emit("xbmc.log",level=2,message=f"AddKo Addons33.db compatibility warning: {error}")

def _execute_entrypoint(entrypoint:Path)->None:
    namespace={"__name__":"__main__","__file__":str(entrypoint),"__package__":None,"__cached__":None}
    code=compile(entrypoint.read_bytes(),str(entrypoint),"exec"); exec(code,namespace,namespace)

def _exception_details(error:BaseException,addon_root:Path)->dict[str,object]:
    extracted=traceback.extract_tb(error.__traceback__); frames=[]; addon_location=""
    for frame in extracted:
        source=(frame.line or "").strip(); frames.append({"file":frame.filename,"line":frame.lineno,"function":frame.name,"source":source})
        try: relative=Path(frame.filename).resolve().relative_to(addon_root)
        except (OSError,ValueError): continue
        addon_location=f"{relative}:{frame.lineno} in {frame.name}" + (f" -> {source}" if source else "")
    if not addon_location and frames:
        last=frames[-1]; addon_location=f"{last['file']}:{last['line']} in {last['function']}"
    return {"exception_type":type(error).__name__,"exception_message":str(error),"addon_location":addon_location,"traceback":"".join(traceback.format_exception(type(error),error,error.__traceback__)),"frames":frames}

def main()->int:
    if len(sys.argv)!=2:
        print("usage: addko_worker.py <context.json>",file=sys.stderr); return 2
    context_path=Path(sys.argv[1]).resolve()
    with context_path.open("r",encoding="utf-8") as handle: context=json.load(handle)
    context_was_preconfigured=bool(getattr(sys,"_addko_context_file",None)); sys._addko_context_file=str(context_path)
    search_paths=[context["shims_path"],context["addon_path"],*context.get("python_paths",[])]
    for value in reversed(search_paths):
        if value and value not in sys.path: sys.path.insert(0,value)
    _install_kodi_api_fallbacks(); _install_runtime_overrides(context); _ensure_kodi_addon_database(context)
    custom_argv=context.get("argv")
    if isinstance(custom_argv,list): sys.argv=[str(v) for v in custom_argv]
    else: sys.argv=[context["plugin_url"],str(context["handle"]),context.get("query","")]
    entrypoint=Path(context["entrypoint_path"]).resolve(); addon_root=Path(context["addon_path"]).resolve()
    try: entrypoint.relative_to(addon_root)
    except ValueError: emit("invocation.error",message="Entrypoint outside addon directory.",traceback=""); return 3
    if not entrypoint.is_file(): emit("invocation.error",message=f"Entrypoint not found: {entrypoint}",traceback=""); return 4
    try:
        _execute_entrypoint(entrypoint); emit("invocation.complete",succeeded=True); return 0
    except SystemExit as error:
        code=error.code if isinstance(error.code,int) else (0 if error.code is None else 1)
        if code==0: emit("invocation.complete",succeeded=True); return 0
        emit("invocation.error",message=f"Addon exited with code {code}",exception_type="SystemExit",exception_message=str(error),traceback=""); return code
    except BaseException as error:
        emit("invocation.error",message=f"{type(error).__name__}: {error}",**_exception_details(error,addon_root)); return 1
if __name__=="__main__": raise SystemExit(main())
