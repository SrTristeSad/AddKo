import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _StringNative = Pointer<Utf8> Function();
typedef _StringDart = Pointer<Utf8> Function();
typedef _StringArgNative = Pointer<Utf8> Function(Pointer<Utf8> value);
typedef _StringArgDart = Pointer<Utf8> Function(Pointer<Utf8> value);
typedef _ProbeBinaryNative = Int32 Function(Pointer<Utf8> path);
typedef _ProbeBinaryDart = int Function(Pointer<Utf8> path);

class KodiNativeEngine {
  KodiNativeEngine._(DynamicLibrary library)
      : _engineVersion = library.lookupFunction<_StringNative, _StringDart>(
          'addko_kodi_engine_version',
        ),
        _kodiRelease = library.lookupFunction<_StringNative, _StringDart>(
          'addko_kodi_engine_kodi_release',
        ),
        _capabilityVersion =
            library.lookupFunction<_StringArgNative, _StringArgDart>(
          'addko_kodi_capability_version',
        ),
        _probeBinary =
            library.lookupFunction<_ProbeBinaryNative, _ProbeBinaryDart>(
          'addko_kodi_probe_binary_addon',
        ),
        _lastError = library.lookupFunction<_StringNative, _StringDart>(
          'addko_kodi_engine_last_error',
        );

  final _StringDart _engineVersion;
  final _StringDart _kodiRelease;
  final _StringArgDart _capabilityVersion;
  final _ProbeBinaryDart _probeBinary;
  final _StringDart _lastError;

  static KodiNativeEngine? tryOpen() {
    for (final candidate in _libraryCandidates()) {
      try {
        return KodiNativeEngine._(DynamicLibrary.open(candidate));
      } on ArgumentError {
        continue;
      }
    }
    return null;
  }

  static List<String> _libraryCandidates() {
    if (Platform.isAndroid || Platform.isLinux) {
      return const ['libaddko_kodi_engine.so'];
    }
    if (Platform.isWindows) {
      return const ['addko_kodi_engine.dll', 'libaddko_kodi_engine.dll'];
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return const ['libaddko_kodi_engine.dylib'];
    }
    return const [];
  }

  String get engineVersion => _read(_engineVersion());
  String get kodiRelease => _read(_kodiRelease());
  String get lastError => _read(_lastError());

  String capabilityVersion(String addonId) {
    final pointer = addonId.toNativeUtf8();
    try {
      return _read(_capabilityVersion(pointer));
    } finally {
      malloc.free(pointer);
    }
  }

  KodiBinaryProbe probeBinaryAddon(String path) {
    final pointer = path.toNativeUtf8();
    try {
      final flags = _probeBinary(pointer);
      return KodiBinaryProbe(
        libraryOpened: flags & 0x01 != 0,
        createExported: flags & 0x02 != 0,
        typeVersionExported: flags & 0x04 != 0,
        typeMinimumVersionExported: flags & 0x08 != 0,
        error: lastError,
      );
    } finally {
      malloc.free(pointer);
    }
  }

  String _read(Pointer<Utf8> pointer) {
    if (pointer == nullptr) return '';
    return pointer.toDartString();
  }
}

class KodiBinaryProbe {
  const KodiBinaryProbe({
    required this.libraryOpened,
    required this.createExported,
    required this.typeVersionExported,
    required this.typeMinimumVersionExported,
    required this.error,
  });

  final bool libraryOpened;
  final bool createExported;
  final bool typeVersionExported;
  final bool typeMinimumVersionExported;
  final String error;

  bool get isKodiBinaryAddon =>
      libraryOpened && createExported && typeVersionExported;
}

class KodiNativeEngineProbe {
  const KodiNativeEngineProbe({
    required this.loaded,
    required this.engineVersion,
    required this.kodiRelease,
    required this.mainAbi,
    required this.guiAbi,
    required this.inputStreamAbi,
  });

  final bool loaded;
  final String engineVersion;
  final String kodiRelease;
  final String mainAbi;
  final String guiAbi;
  final String inputStreamAbi;

  factory KodiNativeEngineProbe.read() {
    final engine = KodiNativeEngine.tryOpen();
    if (engine == null) {
      return const KodiNativeEngineProbe(
        loaded: false,
        engineVersion: '',
        kodiRelease: '',
        mainAbi: '',
        guiAbi: '',
        inputStreamAbi: '',
      );
    }

    return KodiNativeEngineProbe(
      loaded: true,
      engineVersion: engine.engineVersion,
      kodiRelease: engine.kodiRelease,
      mainAbi: engine.capabilityVersion('kodi.binary.global.main'),
      guiAbi: engine.capabilityVersion('kodi.binary.global.gui'),
      inputStreamAbi:
          engine.capabilityVersion('kodi.binary.instance.inputstream'),
    );
  }
}
