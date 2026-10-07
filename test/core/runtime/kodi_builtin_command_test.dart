import 'package:addko/core/runtime/legacy/kodi_builtin_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses common Kodi built-ins', () {
    final command = KodiBuiltinCommand.parse(
      'Container.Update("plugin://plugin.video.demo/?action=list",replace)',
    );

    expect(command.normalizedName, 'container.update');
    expect(command.arguments, [
      'plugin://plugin.video.demo/?action=list',
      'replace',
    ]);
  });

  test('keeps commas inside quoted arguments and nested calls', () {
    final command = KodiBuiltinCommand.parse(
      'Notification("Olá, mundo","RunPlugin(plugin://demo)",5000)',
    );

    expect(command.normalizedName, 'notification');
    expect(command.argument(0), 'Olá, mundo');
    expect(command.argument(1), 'RunPlugin(plugin://demo)');
    expect(command.argument(2), '5000');
  });

  test('accepts built-ins without arguments', () {
    final command = KodiBuiltinCommand.parse('Container.Refresh');

    expect(command.normalizedName, 'container.refresh');
    expect(command.arguments, isEmpty);
  });
}
