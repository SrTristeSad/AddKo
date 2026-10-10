import 'package:path/path.dart' as p;

class AddonPathGuard {
  const AddonPathGuard._();

  static String? resolveInside(String addonRoot, String relativePath) {
    final raw = relativePath.trim();
    if (raw.isEmpty || p.isAbsolute(raw)) {
      return null;
    }

    final root = p.normalize(p.absolute(addonRoot));
    final candidate = p.normalize(p.absolute(p.join(root, raw)));
    if (candidate == root || p.isWithin(root, candidate)) {
      return candidate;
    }
    return null;
  }
}
