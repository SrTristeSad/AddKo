import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _ProbeNative = Int32 Function();
typedef _ProbeDart = int Function();
typedef _ConfigureNative = Int32 Function(Pointer<Utf8> home);
typedef _ConfigureDart = int Function(Pointer<Utf8> home);
typedef _InitializeNative = Int32 Function();
typedef _InitializeDart = int Function();
typedef _IsInitializedNative = Int32 Function();
typedef _IsInitializedDart = int Function();
typedef _ExecNative = Int32 Function(Pointer<Utf8> code);
typedef _ExecDart = int Function(Pointer<Utf8> code);
typedef _ShutdownNative = Int32 Function();
typedef _ShutdownDart = int Function();
typedef _StringNative = Pointer<Utf8> Function();
typedef _StringDart = Pointer<Utf8> Function();

class EmbeddedPythonHost {
  EmbeddedPythonHost._(this._library)
      : _probe = _library.lookupFunction<_ProbeNative, _ProbeDart>(
          'addko_python_probe',
        ),
        _configure = _library.lookupFunction<_ConfigureNative, _ConfigureDart>(
          'addko_python_configure',
        ),
        _initialize = _library.lookupFunction<_InitializeNative, _InitializeDart>(
          'addko_python_initialize',
        ),
        _isInitialized = _library
            .lookupFunction<_IsInitializedNative, _IsInitializedDart>(
          'addko_python_is_initialized',
        ),
        _exec = _library.lookupFunction<_ExecNative, _ExecDart>(
          'addko_python_exec',
        ),
        _shutdown = _library.lookupFunction<_ShutdownNative, _ShutdownDart>(
          'addko_python_shutdown',
        ),
        _version = _library.lookupFunction<_StringNative, _StringDart>(
          'addko_python_version',
        ),
        _home = _library.lookupFunction<_StringNative, _StringDart>(
          'addko_python_home',
        ),
        _lastError = _library.lookupFunction<_StringNative, _StringDart>(
          'addko_python_last_error',
        );

  final DynamicLibrary _library;
  final _ProbeDart _probe;
  final _ConfigureDart _configure;
  final _InitializeDart _initialize;
  final _IsInitializedDart _isInitialized;
  final _ExecDart _exec;
  final _ShutdownDart _shutdown;
  final _StringDart _version;
  final _StringDart _home;
  final _StringDart _lastError;

  static EmbeddedPythonHost? tryOpen() {
    for (final candidate in _libraryCandidates()) {
      try {
        return EmbeddedPythonHost._(DynamicLibrary.open(candidate));
      } on ArgumentError {
        continue;
      }
    }
    return null;
  }

  static List<String> _libraryCandidates() {
    if (Platform.isAndroid || Platform.isLinux) {
      return const ['libaddko_python_host.so'];
    }
    if (Platform.isWindows) {
      return const ['addko_python_host.dll', 'libaddko_python_host.dll'];
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return const ['libaddko_python_host.dylib'];
    }
    return const [];
  }

  bool get hasBundledPython => _probe() == 1;

  bool get isInitialized => _isInitialized() == 1;

  String get version => _readString(_version());

  String get home => _readString(_home());

  String get lastError => _readString(_lastError());

  int configure(String home) {
    final pointer = home.toNativeUtf8();
    try {
      return _configure(pointer);
    } finally {
      malloc.free(pointer);
    }
  }

  int initialize() => _initialize();

  int execute(String code) {
    final pointer = code.toNativeUtf8();
    try {
      return _exec(pointer);
    } finally {
      malloc.free(pointer);
    }
  }

  int shutdown() => _shutdown();

  String _readString(Pointer<Utf8> pointer) {
    if (pointer == nullptr) return '';
    return pointer.toDartString();
  }
}

class EmbeddedPythonProbe {
  const EmbeddedPythonProbe({
    required this.hostLibraryLoaded,
    required this.pythonLibraryLoaded,
    required this.initialized,
    required this.version,
    required this.home,
    required this.error,
  });

  final bool hostLibraryLoaded;
  final bool pythonLibraryLoaded;
  final bool initialized;
  final String version;
  final String home;
  final String error;

  factory EmbeddedPythonProbe.read() {
    final host = EmbeddedPythonHost.tryOpen();
    if (host == null) {
      return const EmbeddedPythonProbe(
        hostLibraryLoaded: false,
        pythonLibraryLoaded: false,
        initialized: false,
        version: '',
        home: '',
        error: 'Host nativo do CPython não está disponível nesta plataforma.',
      );
    }

    final available = host.hasBundledPython;
    return EmbeddedPythonProbe(
      hostLibraryLoaded: true,
      pythonLibraryLoaded: available,
      initialized: available && host.isInitialized,
      version: available ? host.version : '',
      home: host.home,
      error: available ? '' : host.lastError,
    );
  }
}
