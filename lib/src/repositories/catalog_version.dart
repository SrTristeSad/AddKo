import 'package:pub_semver/pub_semver.dart';

enum CatalogVersionStatus {
  notInstalled,
  installed,
  updateAvailable,
  installedNewer,
  differentVersion,
}

/// Never present a replacement as an upgrade without a valid version order.
/// Non-SemVer strings may still be published but must be shown as different.
CatalogVersionStatus catalogVersionStatus(
  String available,
  String? installed,
) {
  if (installed == null) return CatalogVersionStatus.notInstalled;
  if (installed == available) return CatalogVersionStatus.installed;
  try {
    final remote = Version.parse(available);
    final local = Version.parse(installed);
    if (remote > local) return CatalogVersionStatus.updateAvailable;
    if (remote < local) return CatalogVersionStatus.installedNewer;
    return CatalogVersionStatus.installed;
  } on FormatException {
    return CatalogVersionStatus.differentVersion;
  }
}
