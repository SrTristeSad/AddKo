import 'dart:ffi';
import 'package:xml/xml.dart';
import '../../addons/domain/addon_manifest.dart';
import '../../addons/infrastructure/addon_manifest_parser.dart';
import '../domain/repository_catalog.dart';
class RepositoryIndexFormatException implements Exception { const RepositoryIndexFormatException(this.message); final String message; @override String toString()=>'RepositoryIndexFormatException: $message'; }
class RepositoryIndexParseResult { const RepositoryIndexParseResult({required this.addons,required this.skippedAddons}); final List<RepositoryAddonEntry> addons; final int skippedAddons; }
class RepositoryIndexParser {
 const RepositoryIndexParser({this.addonManifestParser=const AddonManifestParser()}); final AddonManifestParser addonManifestParser;
 RepositoryIndexParseResult parse(String source,{Uri? packageBaseUri}){
  final XmlDocument document; try{document=XmlDocument.parse(source);}on XmlParserException catch(e){throw RepositoryIndexFormatException('XML inválido: ${e.message}');}
  final root=document.rootElement; if(root.name.local!='addons')throw const RepositoryIndexFormatException('O índice do repositório precisa usar <addons> como elemento raiz.');
  final entries=<RepositoryAddonEntry>[]; var skipped=0;
  for(final element in root.findElements('addon')){try{final manifest=addonManifestParser.parse(element.toXmlString());if(!_matchesCurrentKodiPlatform(packageBaseUri,element,manifest))continue;entries.add(RepositoryAddonEntry(manifest:manifest,category:_categoryFor(manifest),packageUri:_packageUriFor(packageBaseUri,manifest),iconUri:_iconUriFor(packageBaseUri,manifest)));}on AddonManifestFormatException{skipped++;}}
  entries.sort((a,b)=>a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase())); return RepositoryIndexParseResult(addons:List.unmodifiable(entries),skippedAddons:skipped);
 }
 RepositoryAddonCategory _categoryFor(AddonManifest manifest){
  for(final extension in manifest.extensions){final point=extension.point.toLowerCase();final provides=extension.provides.map((v)=>v.toLowerCase());
   if(point.contains('inputstream'))return RepositoryAddonCategory.inputStream; if(point.contains('pvrclient')||point.contains('.pvr'))return RepositoryAddonCategory.pvr; if(point=='xbmc.addon.repository')return RepositoryAddonCategory.repositories; if(point=='xbmc.python.module')return RepositoryAddonCategory.modules; if(point=='xbmc.service')return RepositoryAddonCategory.services; if(point=='xbmc.subtitle.module')return RepositoryAddonCategory.subtitles;
   if(point=='xbmc.python.pluginsource'){if(provides.contains('video'))return RepositoryAddonCategory.video;if(provides.contains('audio'))return RepositoryAddonCategory.audio;if(provides.contains('image')||provides.contains('images'))return RepositoryAddonCategory.images;return RepositoryAddonCategory.programs;} if(point=='xbmc.python.script')return RepositoryAddonCategory.programs;
  } return RepositoryAddonCategory.other;
 }
 Uri? _packageUriFor(Uri? base,AddonManifest manifest){if(base==null)return null;final b=_directoryUri(base);final dir=_packageDirectoryName(b,manifest);return b.resolve('${Uri.encodeComponent(dir)}/${Uri.encodeComponent(manifest.id)}-${Uri.encodeComponent(manifest.version)}.zip');}
 Uri? _iconUriFor(Uri? base,AddonManifest manifest){if(base==null)return null;final b=_directoryUri(base);final dir=_packageDirectoryName(b,manifest);final icon=manifest.iconPath?.trim();return b.resolve('${Uri.encodeComponent(dir)}/${icon!=null&&icon.isNotEmpty?icon:'icon.png'}');}
 String _packageDirectoryName(Uri base,AddonManifest manifest){if(!_isKodiOfficialRepository(base)||!_isBinaryAddon(manifest))return manifest.id;final platform=_kodiPlatformSuffix();return platform==null?manifest.id:'${manifest.id}+$platform';}
 bool _matchesCurrentKodiPlatform(Uri? base,XmlElement element,AddonManifest manifest){if(base==null||!_isKodiOfficialRepository(base)||!_isBinaryAddon(manifest))return true;final current=_kodiPlatformSuffix();if(current==null)return true;final platforms=element.findElements('extension').where((e)=>e.getAttribute('point')=='xbmc.addon.metadata').expand((e)=>e.findElements('platform')).expand((e)=>e.innerText.split(RegExp(r'[\s,]+')).map((v)=>v.trim().toLowerCase()).where((v)=>v.isNotEmpty)).toSet();return platforms.isEmpty||platforms.contains('all')||platforms.contains(current.toLowerCase());}
 bool _isBinaryAddon(AddonManifest manifest)=>manifest.dependencies.any((d)=>d.id.toLowerCase().startsWith('kodi.binary.'));
 bool _isKodiOfficialRepository(Uri uri)=>uri.host.toLowerCase()=='mirrors.kodi.tv'&&uri.path.toLowerCase().contains('/addons/');
 String? _kodiPlatformSuffix(){final abi=Abi.current();if(abi==Abi.androidArm64)return 'android-aarch64';if(abi==Abi.androidArm)return 'android-armv7';if(abi==Abi.androidX64)return 'android-x86_64';if(abi==Abi.windowsX64)return 'windows-x86_64';if(abi==Abi.windowsIA32)return 'windows-i686';if(abi==Abi.macosArm64)return 'osx-arm64';if(abi==Abi.macosX64)return 'osx-x86_64';return null;}
 Uri _directoryUri(Uri uri)=>uri.path.endsWith('/')?uri:uri.replace(path:'${uri.path}/');
}
