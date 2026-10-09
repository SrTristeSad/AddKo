import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../domain/installed_addon.dart';
import '../infrastructure/addon_manifest_parser.dart';
class InstalledAddonRegistry extends ChangeNotifier {
 InstalledAddonRegistry({required this.addonsRoot,this.manifestParser=const AddonManifestParser()}); final Directory addonsRoot; final AddonManifestParser manifestParser; final Map<String,InstalledAddon> _addons={}; bool _initialized=false;
 bool get initialized=>_initialized; List<InstalledAddon> get addons=>List.unmodifiable(_addons.values); InstalledAddon? byId(String id)=>_addons[id];
 Future<void> initialize() async {if(_initialized)return;await refresh();_initialized=true;}
 Future<void> refresh() async {await addonsRoot.create(recursive:true);final found=<String,InstalledAddon>{};await for(final e in addonsRoot.list(followLinks:false)){if(e is! Directory)continue;final name=p.basename(e.path);if(name.startsWith('.staging-')||name.startsWith('.backup-'))continue;final f=File(p.join(e.path,'addon.xml'));if(!await f.exists())continue;try{final m=manifestParser.parse(await f.readAsString());found[m.id]=InstalledAddon(manifest:m,installPath:e.path);}on Object{/* skip broken */}}_addons..clear()..addAll(found);notifyListeners();}
 Future<void> remove(String id) async {final a=_addons[id];if(a==null)return;final d=Directory(a.installPath);if(await d.exists())await d.delete(recursive:true);_addons.remove(id);notifyListeners();}
}
