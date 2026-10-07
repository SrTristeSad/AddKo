import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AddonDirectories {
  const AddonDirectories();

  Future<Directory> addonsRoot() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'addons'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> addonDataRoot() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'addon_data'));
    await directory.create(recursive: true);
    return directory;
  }
}
