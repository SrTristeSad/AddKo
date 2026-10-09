import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../repositories/domain/repository_catalog.dart';
import '../domain/installed_addon.dart';
import '../infrastructure/addon_directories.dart';
import '../infrastructure/addon_package_installer.dart';
import 'addon_dependency_resolver.dart';
import 'installed_addon_registry.dart';
class AddonInstallController extends ChangeNotifier {
 AddonInstallController({AddonDirectories? directories,AddonPackageInstaller? installer,this.dependencyResolver=const AddonDependencyResolver()}):_directories=directories??AddonDirectories(),_installer=installer??AddonPackageInstaller(),_ownsInstaller=installer==null;
 final AddonDirectories _directories;final AddonPackageInstaller _installer;final bool _ownsInstaller;final AddonDependencyResolver dependencyResolver;InstalledAddonRegistry? _registry;Future<void>? _initialization;final Set<String> _installing={};String? _initializationError;
 bool get initialized=>_registry?.initialized??false;String? get initializationError=>_initializationError;List<InstalledAddon> get installedAddons=>_registry?.addons??const [];InstalledAddon? installedById(String id)=>_registry?.byId(id);bool isInstalling(String id)=>_installing.contains(id);
 Future<void> initialize()=>_initialization??=_initializeInternal();Future<void> _initializeInternal() async {try{final root=await _directories.addonsRoot();final r=InstalledAddonRegistry(addonsRoot:root);r.addListener(_relayRegistryChange);await r.initialize();_registry=r;_initializationError=null;}on Object catch(e){_initializationError=e.toString();}notifyListeners();}
 Future<void> refreshInstalled() async {await initialize();final r=_registry;if(r==null)throw AddonInstallException(_initializationError??'O registro local de addons não foi iniciado.');await r.refresh();}
 Future<DirectoryInfo> directories() async {final a=await _directories.addonsRoot(),d=await _directories.addonDataRoot();return DirectoryInfo(addonsRootPath:a.path,addonDataRootPath:d.path);}
 AddonInstallPlan buildPlan({required RepositoryAddonEntry addon,required Iterable<RepositoryCatalog> catalogs})=>dependencyResolver.resolve(root:addon,catalogs:catalogs,installedAddons:installedAddons);
 Future<AddonInstallPlan> install({required RepositoryAddonEntry addon,required Iterable<RepositoryCatalog> catalogs}) async {await initialize();final r=_requireRegistry();final plan=buildPlan(addon:addon,catalogs:catalogs);if(!plan.canInstall)return plan;await _installPlan(plan,r);return plan;}
 Future<LocalPackageInstallResult> installLocalPackage({required List<int> bytes,required Iterable<RepositoryCatalog> catalogs}) async {await initialize();final r=_requireRegistry();final installed=await _installer.installBytes(bytes:bytes,addonsRoot:r.addonsRoot);await r.refresh();final root=RepositoryAddonEntry(manifest:installed.manifest,category:RepositoryAddonCategory.other);final plan=dependencyResolver.resolve(root:root,catalogs:catalogs,installedAddons:installedAddons,installRoot:false);if(plan.canInstall)await _installPlan(plan,r);return LocalPackageInstallResult(addon:r.byId(installed.manifest.id)??installed,dependencyPlan:plan);}
 Future<void> _installPlan(AddonInstallPlan plan,InstalledAddonRegistry r) async {try{for(final e in plan.installOrder){_installing.add(e.manifest.id);notifyListeners();await _installer.installFromUri(packageUri:e.packageUri!,addonsRoot:r.addonsRoot,expectedAddonId:e.manifest.id,expectedVersion:e.manifest.version);await r.refresh();}}finally{for(final e in plan.installOrder){_installing.remove(e.manifest.id);}notifyListeners();}}
 InstalledAddonRegistry _requireRegistry(){final r=_registry;if(r==null)throw AddonInstallException(_initializationError??'O registro local de addons não foi iniciado.');return r;}
 List<InstalledAddon> requiredBy(String id){final a=installedAddons.where((x)=>x.manifest.dependencies.any((d)=>!d.optional&&d.id==id)).toList(growable:false)..sort((a,b)=>a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase()));return a;}
 Future<void> uninstall(String id,{bool removeData=false,bool force=false}) async {await initialize();final r=_requireRegistry();final a=r.byId(id);if(a==null)return;final deps=requiredBy(id);if(!force&&deps.isNotEmpty)throw AddonInstallException('${a.manifest.name} é necessário para: ${deps.map((e)=>e.manifest.name).take(4).join(', ')}. Remova esses addons primeiro.');await r.remove(id);if(removeData){final root=await _directories.addonDataRoot();final d=Directory(p.join(root.path,id));if(await d.exists())await d.delete(recursive:true);}}
 void _relayRegistryChange()=>notifyListeners();@override void dispose(){final r=_registry;if(r!=null){r.removeListener(_relayRegistryChange);r.dispose();}if(_ownsInstaller)_installer.close();super.dispose();}
}
class LocalPackageInstallResult{const LocalPackageInstallResult({required this.addon,required this.dependencyPlan});final InstalledAddon addon;final AddonInstallPlan dependencyPlan;bool get dependenciesResolved=>dependencyPlan.canInstall;}
class DirectoryInfo{const DirectoryInfo({required this.addonsRootPath,required this.addonDataRootPath});final String addonsRootPath;final String addonDataRootPath;}
