import 'package:xml/xml.dart';
import '../domain/addon_dependency.dart';
import '../domain/addon_manifest.dart';
class AddonManifestFormatException implements Exception { const AddonManifestFormatException(this.message); final String message; @override String toString()=>'AddonManifestFormatException: $message'; }
class AddonManifestParser {
 const AddonManifestParser();
 AddonManifest parse(String source){
  final XmlDocument document; try{document=XmlDocument.parse(source);} on XmlParserException catch(error){throw AddonManifestFormatException('XML inválido: ${error.message}');}
  final root=document.rootElement; if(root.name.local!='addon') throw const AddonManifestFormatException('O elemento raiz precisa ser <addon>.');
  final id=_requiredAttribute(root,'id'), name=_requiredAttribute(root,'name'), version=_requiredAttribute(root,'version'); final providerName=root.getAttribute('provider-name')??'';
  final dependencies=<AddonDependency>[]; final requires=root.getElement('requires'); if(requires!=null){for(final element in requires.findElements('import')){final dep=element.getAttribute('addon');if(dep==null||dep.trim().isEmpty)continue;dependencies.add(AddonDependency(id:dep.trim(),version:_nullableTrimmed(element.getAttribute('version')),optional:_parseBool(element.getAttribute('optional'))));}}
  final extensions=<AddonExtension>[]; for(final element in root.findElements('extension')){final point=element.getAttribute('point');if(point==null||point.trim().isEmpty)continue;final attrs=<String,String>{};for(final a in element.attributes){attrs[a.name.local]=a.value;}final provides=element.findElements('provides').expand((e)=>e.innerText.split(RegExp(r'\s+')).map((v)=>v.trim()).where((v)=>v.isNotEmpty)).toList(growable:false);extensions.add(AddonExtension(point:point.trim(),library:_nullableTrimmed(element.getAttribute('library')),attributes:Map.unmodifiable(attrs),provides:List.unmodifiable(provides)));}
  final metadata=root.findElements('extension').where((e)=>e.getAttribute('point')=='xbmc.addon.metadata'); final meta=metadata.isEmpty?null:metadata.first; final assets=meta?.getElement('assets');
  return AddonManifest(id:id,name:name,version:version,providerName:providerName,dependencies:List.unmodifiable(dependencies),extensions:List.unmodifiable(extensions),summary:_firstLocalizedText(meta,'summary'),description:_firstLocalizedText(meta,'description'),iconPath:_nullableTrimmed(assets?.getElement('icon')?.innerText),fanartPath:_nullableTrimmed(assets?.getElement('fanart')?.innerText));
 }
 String _requiredAttribute(XmlElement e,String name){final v=e.getAttribute(name);if(v==null||v.trim().isEmpty)throw AddonManifestFormatException('Atributo obrigatório "$name" não encontrado.');return v.trim();}
 String? _firstLocalizedText(XmlElement? p,String name){if(p==null)return null;final values=p.findElements(name);return values.isEmpty?null:_nullableTrimmed(values.first.innerText);}
 String? _nullableTrimmed(String? v){if(v==null)return null;final t=v.trim();return t.isEmpty?null:t;}
 bool _parseBool(String? v)=>v!=null&&(v.toLowerCase()=='true'||v=='1');
}
