import 'package:addko/core/repositories/infrastructure/repository_descriptor_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = RepositoryDescriptorParser();

  test('parses Kodi repository endpoints', () {
    const xml = '''
<addon id="repository.example" name="Example Repository" version="1.0.0" provider-name="AddKo">
  <extension point="xbmc.addon.repository">
    <dir minversion="19.0.0">
      <info compressed="true">https://example.com/addons.xml.gz</info>
      <checksum>https://example.com/addons.xml.gz.md5</checksum>
      <datadir zip="true">https://example.com/zips/</datadir>
    </dir>
  </extension>
</addon>
''';

    final repository = parser.parse(xml);

    expect(repository.addonId, 'repository.example');
    expect(repository.endpoints, hasLength(1));
    expect(repository.endpoints.first.compressed, isTrue);
    expect(repository.endpoints.first.zipPackages, isTrue);
    expect(repository.endpoints.first.minimumVersion, '19.0.0');
  });
}
