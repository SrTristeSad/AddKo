import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/basic_plugin_host.dart';
import 'package:addko/src/runtime/plugin_player.dart';

class MediaPluginHost extends BasicPluginHost {
  MediaPluginHost({
    required super.manifest,
    required super.pluginDirectory,
    required super.dataDirectory,
    required this.player,
  });

  final PluginPlayer player;

  bool get _media => manifest.permissions.contains(PluginPermission.media);

  @override
  Map<String, bool> get capabilities => <String, bool>{
        ...super.capabilities,
        'player': _media,
      };

  @override
  Future<Object?> invoke(String operation, Object? arguments) async {
    if (!operation.startsWith('player.')) {
      return super.invoke(operation, arguments);
    }

    if (!_media) {
      throw const PluginHostException('Plugin não possui capacidade media.');
    }

    final args = _map(arguments);
    switch (operation) {
      case 'player.play':
        return player.play(args['item']);
      case 'player.current_url':
        return player.currentUrl;
      case 'player.is_playing':
        return player.isPlaying;
      case 'player.is_paused':
        return player.isPaused;
      case 'player.times':
        return player.times;
      case 'player.seek':
        final seconds = _double(args['seconds']);
        await player.seek(seconds);
        return true;
      case 'player.subtitles':
        return player.subtitles;
      case 'player.set_subtitles':
        final raw = args['urls'];
        final urls = raw is List
            ? raw.map((value) => value.toString()).toList(growable: false)
            : const <String>[];
        await player.setSubtitles(urls);
        return true;
      default:
        throw PluginHostException('Operação de player desconhecida: $operation');
    }
  }
}

Map<String, Object?> _map(Object? value) {
  if (value == null) return <String, Object?>{};
  if (value is! Map) {
    throw const PluginHostException('Argumentos da operação devem ser objeto.');
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  final parsed = double.tryParse(value?.toString() ?? '');
  if (parsed == null || !parsed.isFinite) {
    throw PluginHostException('Número inválido: $value');
  }
  return parsed;
}
