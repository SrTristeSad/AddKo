import 'dart:convert';
import 'dart:io';

import 'package:addko/core/repositories/domain/repository_source.dart';
import 'package:addko/core/repositories/infrastructure/repository_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads a repository descriptor and its addons.xml index', () async {
    const indexXml = '''
<addons>
  <addon id="plugin.video.demo" name="Demo" version="1.0.0" provider-name="AddKo">
    <extension point="xbmc.python.pluginsource" library="default.py">
      <provides>video</provides>
    </extension>
  </addon>
</addons>
''';
    final indexDigest = md5.convert(utf8.encode(indexXml)).toString();

    final client = MockClient((request) async {
      if (request.url.toString() == 'https://repo.example/addon.xml') {
        return http.Response(
          '''
<addon id="repository.demo" name="Demo Repo" version="1.0.0" provider-name="AddKo">
  <extension point="xbmc.addon.repository">
    <dir>
      <info compressed="false">https://repo.example/addons.xml</info>
      <checksum>https://repo.example/addons.xml.md5</checksum>
      <datadir zip="true">https://repo.example/zips/</datadir>
    </dir>
  </extension>
</addon>
''',
          200,
          headers: {'content-type': 'application/xml'},
        );
      }

      if (request.url.toString() == 'https://repo.example/addons.xml') {
        return http.Response(
          indexXml,
          200,
          headers: {'content-type': 'application/xml'},
        );
      }

      if (request.url.toString() == 'https://repo.example/addons.xml.md5') {
        return http.Response(
          '$indexDigest  addons.xml\n',
          200,
          headers: {'content-type': 'text/plain'},
        );
      }

      return http.Response('not found', 404);
    });

    final repositoryClient = RepositoryClient(client: client);
    final catalog = await repositoryClient.synchronize(
      RepositorySource(
        uri: Uri.parse('https://repo.example/addon.xml'),
        enabled: true,
      ),
    );

    expect(catalog.repositoryName, 'Demo Repo');
    expect(catalog.addons, hasLength(1));
    expect(
      catalog.addons.single.packageUri.toString(),
      'https://repo.example/zips/plugin.video.demo/plugin.video.demo-1.0.0.zip',
    );
  });

  test('accepts gzip-compressed addons.xml', () async {
    const xml = '''
<addons>
  <addon id="script.module.demo" name="Module" version="1.0.0" provider-name="AddKo">
    <extension point="xbmc.python.module" library="lib" />
  </addon>
</addons>
''';
    final compressed = gzip.encode(utf8.encode(xml));

    final client = MockClient((request) async {
      return http.Response.bytes(
        compressed,
        200,
        headers: {'content-type': 'application/gzip'},
      );
    });

    final repositoryClient = RepositoryClient(client: client);
    final catalog = await repositoryClient.synchronize(
      RepositorySource(
        uri: Uri.parse('https://repo.example/addons.xml.gz'),
        enabled: true,
      ),
    );

    expect(catalog.addons.single.manifest.id, 'script.module.demo');
  });

  test('uses package base stored from an installed repository zip', () async {
    final client = MockClient((request) async {
      if (request.url.toString() == 'https://repo.example/kodi/addons.xml') {
        return http.Response(
          '''
<addons>
  <addon id="plugin.video.fromzip" name="From ZIP" version="2.1.0" provider-name="AddKo">
    <extension point="xbmc.python.pluginsource" library="default.py">
      <provides>video</provides>
    </extension>
  </addon>
</addons>
''',
          200,
          headers: {'content-type': 'application/xml'},
        );
      }
      return http.Response('not found', 404);
    });

    final repositoryClient = RepositoryClient(client: client);
    final catalog = await repositoryClient.synchronize(
      RepositorySource(
        uri: Uri.parse('https://repo.example/kodi/addons.xml'),
        packageBaseUri: Uri.parse('https://cdn.example/zips/'),
        name: 'Installed Repo',
        enabled: true,
      ),
    );

    expect(catalog.repositoryName, 'Installed Repo');
    expect(catalog.addons.single.manifest.id, 'plugin.video.fromzip');
    expect(
      catalog.addons.single.packageUri,
      Uri.parse(
        'https://cdn.example/zips/plugin.video.fromzip/plugin.video.fromzip-2.1.0.zip',
      ),
    );
  });
}
