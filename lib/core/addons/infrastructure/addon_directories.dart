import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AddonDirectories {
  AddonDirectories({
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectoryProvider;

  Future<Directory> addonsRoot() async {
    final support = await _supportDirectoryProvider();
    final directory = Directory(p.join(support.path, 'addons'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> addonDataRoot() async {
    final support = await _supportDirectoryProvider();
    final directory = Directory(p.join(support.path, 'addon_data'));
    await directory.create(recursive: true);
    return directory;
  }
}
