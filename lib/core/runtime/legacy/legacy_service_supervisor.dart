import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../addons/application/addon_install_controller.dart';
import '../../addons/domain/installed_addon.dart';
import 'embedded_python_executor.dart';
import 'legacy_plugin_invocation.dart';
import 'legacy_plugin_result.dart';
import 'process_python_executor.dart';
import 'python_runtime_bundle.dart';
typedef LegacyServiceEventHandler=FutureOr<void> Function(String addonId,String method,Map<String,Object?> params);
class LegacyServiceSupervisor extends ChangeNotifier{
 LegacyServiceSupervisor({required this.addonInstallController,this.eventHandler,PythonRuntimeBundle? runtimeBundle,PythonExecutableResolver? pythonResolver}):_bundle=runtimeBundle??PythonRuntimeBundle(),_resolver=pythonResolver??const PythonExecutableResolver();
 final AddonInstallController addonInstallController;LegacyServiceEventHandler? eventHandler;final PythonRuntimeBundle _bundle;final PythonExecutableResolver _resolver;final Map<String,_ServiceState> _running={};final Map<String,String> _errors={};bool _started=false,_stopping=false;
 List<String> get runningAddonIds=>List.unmodifiable(_running.keys);Map<String,String> get errors=>Map.unmodifiable(_errors);bool get started=>_started;
 Future<void>start()async{if(_started)return;await addonInstallController.initialize();_started=true;addonInstallController.addListener(_changed);await reconcile();}
 void _changed(){unawaited(reconcile());}
 Future<void>reconcile()async{if(!_started||_stopping)return;final desired={for(final a in addonInstallController.installedAddons)if(a.manifest.isPythonService&&a.manifest.pythonServiceEntrypoint?.trim().isNotEmpty==true)a.manifest.id:a};for(final id in _running.keys.toList()){if(!desired.containsKey(id)){_running[id]!.stopRequested=true;_running.remove(id);}}for(final a in desired.values){if(_running.containsKey(a.manifest.id))continue;unawaited(_launch(a));}notifyListeners();}
 Future<void>_launch(InstalledAddon addon)async{final entry=addon.manifest.pythonServiceEntrypoint!.trim();final files=await _bundle.materialize();final dirs=await addonInstallController.directories();final profile=p.join(dirs.addonDataRootPath,addon.manifest.id);await Directory(profile).create(recursive:true);final support=p.dirname(dirs.addonsRootPath);final inv=LegacyPluginInvocation(addonId:addon.manifest.id,addonPath:addon.installPath,entrypointPath:p.join(addon.installPath,entry),pluginUrl:'service://${addon.manifest.id}',handle:0,query:'',profilePath:profile,addonsRoot:dirs.addonsRootPath,addonDataRoot:dirs.addonDataRootPath,shimsPath:files.shimsPath,pythonPaths:_pythonPathsFor(addon),specialPaths:{'special://home':support,'special://profile':support,'special://userdata':support,'special://temp':Directory.systemTemp.path},argv:[p.join(addon.installPath,entry)]);final state=_ServiceState();_running[addon.manifest.id]=state;_errors.remove(addon.manifest.id);notifyListeners();LegacyPluginResult result;try{if(Platform.isAndroid){result=await EmbeddedPythonExecutor(workerScriptPath:files.workerPath,eventHandler:(m,p)=>Future<void>.sync(()=>eventHandler?.call(addon.manifest.id,m,p))).invoke(inv);}else{final python=await _resolver.resolve();if(python==null)throw StateError('Python 3 não encontrado.');result=await ProcessPythonExecutor(pythonExecutable:python,workerScriptPath:files.workerPath).invoke(inv);}if(!state.stopRequested&&!result.succeeded)_errors[addon.manifest.id]=result.errorMessage??'Serviço encerrou com falha.';}on Object catch(e){if(!state.stopRequested)_errors[addon.manifest.id]=e.toString();}finally{if(identical(_running[addon.manifest.id],state))_running.remove(addon.manifest.id);notifyListeners();}}
 List<String>_pythonPathsFor(InstalledAddon addon){final r=<String>[];for(final d in addon.manifest.dependencies){final i=addonInstallController.installedById(d.id);if(i==null)continue;final ex=i.manifest.extensions.where((e)=>e.point=='xbmc.python.module');if(ex.isEmpty)r.add(i.installPath);for(final e in ex){if(e.library?.trim().isNotEmpty==true)r.add(p.join(i.installPath,e.library!.trim()));}}return r;}
 Future<void>retry(String id)async{_errors.remove(id);await restart(id);}Future<void>restart(String id)async{_running[id]?.stopRequested=true;_running.remove(id);notifyListeners();await reconcile();}
 Future<void>shutdown()async{if(_stopping)return;_stopping=true;if(_started)addonInstallController.removeListener(_changed);for(final s in _running.values){s.stopRequested=true;}_running.clear();_started=false;notifyListeners();}
 @override void dispose(){unawaited(shutdown());super.dispose();}
}
class _ServiceState{bool stopRequested=false;}
