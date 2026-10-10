import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../runtime/kodi/kodi_core.dart';

class AddonDirectories {
  AddonDirectories({Future<Directory> Function()? supportDirectoryProvider})
    : _supportDirectoryProvider =
          supportDirectoryProvider ?? getApplicationSupportDirectory,
      _native = supportDirectoryProvider == null && KodiCore.supported;
  final Future<Directory> Function() _supportDirectoryProvider;
  final bool _native;
  Future<Map<String, String>>? _profile;

  Future<Directory> addonsRoot() async {
    final path = _native
        ? (await (_profile ??= KodiCore.profile()))['addons']!
        : p.join((await _supportDirectoryProvider()).path, 'addons');
    final directory = Directory(path);
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> addonDataRoot() async {
    final path = _native
        ? (await (_profile ??= KodiCore.profile()))['addonData']!
        : p.join((await _supportDirectoryProvider()).path, 'addon_data');
    final directory = Directory(path);
    await directory.create(recursive: true);
    return directory;
  }
}
