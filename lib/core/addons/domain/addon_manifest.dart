import 'addon_dependency.dart';
class AddonManifest {
  const AddonManifest({required this.id,required this.name,required this.version,required this.providerName,required this.dependencies,required this.extensions,this.summary,this.description,this.iconPath,this.fanartPath});
  static const Set<String> pythonExecutableExtensionPoints={'xbmc.python.pluginsource','xbmc.python.script','xbmc.python.weather','xbmc.python.lyrics','xbmc.python.library','xbmc.subtitle.module','xbmc.service'};
  static const Set<String> binaryExtensionPoints={'kodi.audiodecoder','kodi.audioencoder','kodi.gameclient','kodi.imagedecoder','kodi.inputstream','kodi.peripheral','kodi.pvrclient','kodi.vfs','xbmc.player.musicviz','xbmc.ui.screensaver'};
  final String id,name,version,providerName; final List<AddonDependency> dependencies; final List<AddonExtension> extensions; final String? summary,description,iconPath,fanartPath;
  bool get isRepository=>extensions.any((e)=>e.point=='xbmc.addon.repository');
  bool get isPythonPlugin=>extensions.any((e)=>e.point=='xbmc.python.pluginsource');
  bool get isPythonScript=>extensions.any((e)=>e.point=='xbmc.python.script');
  bool get isPythonModule=>extensions.any((e)=>e.point=='xbmc.python.module');
  bool get isPythonService=>extensions.any((e)=>e.point=='xbmc.service');
  bool get isPythonExecutable=>extensions.any((e)=>pythonExecutableExtensionPoints.contains(e.point));
  bool get isWebInterface=>extensions.any((e)=>e.point=='xbmc.webinterface');
  bool get isBinaryAddon=>extensions.any((e)=>binaryExtensionPoints.contains(e.point));
  Iterable<AddonExtension> get pythonExecutableExtensions=>extensions.where((e)=>pythonExecutableExtensionPoints.contains(e.point));
  Iterable<AddonExtension> get binaryExtensions=>extensions.where((e)=>binaryExtensionPoints.contains(e.point));
  AddonExtension? extensionFor(String point){for(final e in extensions){if(e.point==point)return e;}return null;}
  String? pythonEntrypointFor(String point)=>extensionFor(point)?.library;
  String? get pythonEntrypoint=>pythonEntrypointFor('xbmc.python.pluginsource');
  String? get pythonScriptEntrypoint=>pythonEntrypointFor('xbmc.python.script');
  String? get pythonServiceEntrypoint=>pythonEntrypointFor('xbmc.service');
  String? get pythonServiceStartMode=>extensionFor('xbmc.service')?.attributes['start'];
  String? binaryLibraryFor(AddonExtension extension,{required String platform}){
    if(!binaryExtensionPoints.contains(extension.point))return null;
    final specific=extension.attributes['library_$platform']?.trim(); if(specific!=null&&specific.isNotEmpty)return specific;
    final generic=extension.library?.trim(); return generic!=null&&generic.isNotEmpty?generic:null;
  }
}
class AddonExtension { const AddonExtension({required this.point,required this.attributes,required this.provides,this.library}); final String point; final String? library; final Map<String,String> attributes; final List<String> provides; }
