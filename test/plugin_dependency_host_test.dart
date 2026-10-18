import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/plugin_dependency_host.dart';
import 'package:addko/src/runtime/plugin_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('declared dependency can receive a generic service call', () async {
    final calls = <Object?>[];
    final host = PluginDependencyHost(
      inner: _FakeHost(),
      manifest: const PluginManifest(
        id: 'com.addko.catalog',
        name: 'Catalog',
        version: '1.0.0',
        entry: 'main.lua',
        permissions: <PluginPermission>{},
        dependencies: <String>{'io.addko.luelement'},
      ),
      caller: (id, method, arguments) async {
        calls.add(<Object?>[id, method, arguments]);
        return <String, Object?>{'ok': true};
      },
    );
    addTearDown(host.close);

    expect(host.capabilities['plugins'], isTrue);
    final result = await host.invoke('plugins.call', <String, Object?>{
      'id': 'io.addko.luelement',
      'method': 'health',
      'args': const <String, Object?>{},
    });

    expect(result, <String, Object?>{'ok': true});
    expect(calls, hasLength(1));
  });

  test('undeclared dependency is rejected before broker call', () async {
    var called = false;
    final host = PluginDependencyHost(
      inner: _FakeHost(),
      manifest: const PluginManifest(
        id: 'com.addko.catalog',
        name: 'Catalog',
        version: '1.0.0',
        entry: 'main.lua',
        permissions: <PluginPermission>{},
        dependencies: <String>{'io.addko.luelement'},
      ),
      caller: (id, method, arguments) async {
        called = true;
        return true;
      },
    );
    addTearDown(host.close);

    await expectLater(
      host.invoke('plugins.call', <String, Object?>{
        'id': 'com.example.other',
        'method': 'health',
      }),
      throwsA(isA<PluginDependencyException>()),
    );
    expect(called, isFalse);
  });

  test('non dependency operations still pass through to inner host', () async {
    final inner = _FakeHost();
    final host = PluginDependencyHost(
      inner: inner,
      manifest: const PluginManifest(
        id: 'com.addko.catalog',
        name: 'Catalog',
        version: '1.0.0',
        entry: 'main.lua',
        permissions: <PluginPermission>{},
        dependencies: <String>{'io.addko.luelement'},
      ),
      caller: (id, method, arguments) async => null,
    );
    addTearDown(host.close);

    final result = await host.invoke('echo', <String, Object?>{'value': 7});
    expect(result, <String, Object?>{'value': 7});
    expect(inner.lastOperation, 'echo');
  });
}

class _FakeHost extends PluginHost {
  String? lastOperation;

  @override
  Map<String, bool> get capabilities => const <String, bool>{
        'http': true,
      };

  @override
  Future<Object?> invoke(String operation, Object? arguments) async {
    lastOperation = operation;
    return arguments;
  }

  @override
  void bindEventDispatcher(PluginEventDispatcher dispatcher) {}

  @override
  Future<void> close() async {}
}
