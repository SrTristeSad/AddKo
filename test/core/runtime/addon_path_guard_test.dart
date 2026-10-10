import 'dart:io';

import 'package:addko/core/runtime/legacy/addon_path_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('resolves paths that stay inside the addon directory', () async {
    final root = await Directory.systemTemp.createTemp('addko-path-guard-');
    addTearDown(() => root.delete(recursive: true));

    final resolved = AddonPathGuard.resolveInside(root.path, 'resources/lib/main.py');

    expect(resolved, p.normalize(p.join(root.path, 'resources/lib/main.py')));
  });

  test('rejects traversal outside the addon directory', () async {
    final root = await Directory.systemTemp.createTemp('addko-path-guard-');
    addTearDown(() => root.delete(recursive: true));

    expect(AddonPathGuard.resolveInside(root.path, '../evil.py'), isNull);
    expect(AddonPathGuard.resolveInside(root.path, '../../outside.py'), isNull);
  });

  test('rejects absolute paths', () async {
    final root = await Directory.systemTemp.createTemp('addko-path-guard-');
    addTearDown(() => root.delete(recursive: true));

    final absolute = p.absolute(p.join(root.parent.path, 'evil.py'));
    expect(AddonPathGuard.resolveInside(root.path, absolute), isNull);
  });
}
