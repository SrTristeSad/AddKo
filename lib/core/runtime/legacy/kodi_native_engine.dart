import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
typedef _StringNative=Pointer<Utf8> Function(); typedef _StringDart=Pointer<Utf8> Function(); typedef _StringArgNative=Pointer<Utf8> Function(Pointer<Utf8>); typedef _StringArgDart=Pointer<Utf8> Function(Pointer<Utf8>); typedef _ProbeBinaryNative=Int32 Function(Pointer<Utf8>); typedef _ProbeBinaryDart=int Function(Pointer<Utf8>);
class KodiNativeEngine {
 KodiNativeEngine._(DynamicLibrary l):_engineVersion=l.lookupFunction<_StringNative,_StringDart>('addko_kodi_engine_version'),_kodiRelease=l.lookupFunction<_StringNative,_StringDart>('addko_kodi_engine_kodi_release'),_capabilityVersion=l.lookupFunction<_StringArgNative,_StringArgDart>('addko_kodi_capability_version'),_probeBinary=l.lookupFunction<_ProbeBinaryNative,_ProbeBinaryDart>('addko_kodi_probe_binary_addon'),_lastError=l.lookupFunction<_StringNative,_StringDart>('addko_kodi_engine_last_error');
 final _StringDart _engineVersion,_kodiRelease,_lastError; final _StringArgDart _capabilityVersion; final _ProbeBinaryDart _probeBinary;
 static KodiNativeEngine? tryOpen(){for(final c in _libraryCandidates()){try{return KodiNativeEngine._(DynamicLibrary.open(c));}on ArgumentError{}}return null;}
 static List<String> _libraryCandidates(){if(Platform.isAndroid||Platform.isLinux)return const ['libaddko_kodi_engine.so'];if(Platform.isWindows)return const ['addko_kodi_engine.dll','libaddko_kodi_engine.dll'];if(Platform.isMacOS||Platform.isIOS)return const ['libaddko_kodi_engine.dylib'];return const [];}
 String _read(Pointer<Utf8> p)=>p==nullptr?'':p.toDartString(); String get engineVersion=>_read(_engineVersion()); String get kodiRelease=>_read(_kodiRelease()); String get lastError=>_read(_lastError());
 String capabilityVersion(String id){final p=id.toNativeUtf8();try{return _read(_capabilityVersion(p));}finally{malloc.free(p);}}
 KodiBinaryProbe probeBinaryAddon(String path){final p=path.toNativeUtf8();try{final f=_probeBinary(p);return KodiBinaryProbe(libraryOpened:f&1!=0,createExported:f&2!=0,typeVersionExported:f&4!=0,typeMinimumVersionExported:f&8!=0,error:lastError);}finally{malloc.free(p);}}
}
class KodiBinaryProbe { const KodiBinaryProbe({required this.libraryOpened,required this.createExported,required this.typeVersionExported,required this.typeMinimumVersionExported,required this.error}); final bool libraryOpened,createExported,typeVersionExported,typeMinimumVersionExported; final String error; bool get isKodiBinaryAddon=>libraryOpened&&createExported&&typeVersionExported; }
