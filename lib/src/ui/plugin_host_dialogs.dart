import 'package:flutter/material.dart';

int _nextProgressHandle = 0;

Future<Object?> handlePluginHostUi(
  BuildContext context,
  String operation,
  Map<String, Object?> arguments,
) async {
  if (!context.mounted) {
    return _fallback(operation, arguments);
  }

  switch (operation) {
    case 'ui.refresh':
    case 'ui.navigate':
      return true;
    case 'ui.notify':
      final title = arguments['title']?.toString().trim() ?? '';
      final message = arguments['message']?.toString().trim() ?? '';
      final text = <String>[
        if (title.isNotEmpty) title,
        if (message.isNotEmpty) message,
      ].join(' — ');
      if (text.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text)),
        );
      }
      return true;
    case 'ui.alert':
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(arguments['title']?.toString() ?? 'AddKo'),
          content: Text(arguments['message']?.toString() ?? ''),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return true;
    case 'ui.confirm':
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: Text(arguments['title']?.toString() ?? 'Confirmar'),
              content: Text(arguments['message']?.toString() ?? ''),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Confirmar'),
                ),
              ],
            ),
          ) ??
          false;
    case 'ui.input':
      final controller = TextEditingController(
        text: arguments['value']?.toString() ?? '',
      );
      try {
        return await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(arguments['title']?.toString() ?? 'Entrada'),
            content: TextField(
              controller: controller,
              autofocus: true,
              obscureText: arguments['password'] == true,
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(controller.text),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } finally {
        controller.dispose();
      }
    case 'ui.select':
      final rawItems = arguments['items'];
      final items = rawItems is List ? rawItems : const <Object?>[];
      if (items.isEmpty) return -1;

      final selected = _asInt(arguments['selected']);
      return await showDialog<int>(
            context: context,
            builder: (dialogContext) => SimpleDialog(
              title: Text(arguments['title']?.toString() ?? 'Selecionar'),
              children: [
                for (var index = 0; index < items.length; index += 1)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(dialogContext).pop(index),
                    child: Row(
                      children: [
                        if (selected == index) ...[
                          const Icon(Icons.check_rounded, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: Text(_itemLabel(items[index]))),
                      ],
                    ),
                  ),
              ],
            ),
          ) ??
          -1;
    case 'ui.pick_file':
      // Generic file picking will get its own host API. Returning an empty
      // path matches the cancellation behavior expected by current plugins.
      return '';
    case 'ui.progress_create':
      _nextProgressHandle += 1;
      return _nextProgressHandle;
    case 'ui.progress_update':
    case 'ui.progress_close':
      return true;
    case 'ui.progress_is_cancelled':
      return false;
    default:
      throw StateError('Operação de UI desconhecida: $operation');
  }
}

Object? _fallback(String operation, Map<String, Object?> arguments) {
  return switch (operation) {
    'ui.input' => arguments['value']?.toString() ?? '',
    'ui.confirm' => false,
    'ui.select' => -1,
    'ui.pick_file' => '',
    'ui.progress_create' => 0,
    'ui.progress_is_cancelled' => false,
    _ => true,
  };
}

int? _asInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _itemLabel(Object? value) {
  if (value is Map) {
    for (final key in const <String>['label', 'title', 'name', 'text']) {
      final candidate = value[key];
      if (candidate != null && candidate.toString().isNotEmpty) {
        return candidate.toString();
      }
    }
  }
  return value?.toString() ?? '';
}
