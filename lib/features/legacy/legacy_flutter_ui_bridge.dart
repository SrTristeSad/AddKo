import 'package:flutter/material.dart';

import '../../core/runtime/legacy/kodi_json_rpc_compat.dart';
import '../../core/runtime/legacy/legacy_runtime_request.dart';
import 'legacy_window_xml_dialog.dart';

class LegacyFlutterUiBridge {
  const LegacyFlutterUiBridge._();

  static const KodiJsonRpcCompat _jsonRpc = KodiJsonRpcCompat();

  static Future<Object?> handle(
    BuildContext context,
    LegacyRuntimeRequest request,
  ) async {
    if (!context.mounted) {
      return request.defaultValue;
    }

    switch (request.method) {
      case 'xbmc.executeJSONRPC':
        return _jsonRpc.handle(_string(request, 'request'));
      case 'xbmcgui.Dialog.ok':
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_string(request, 'heading')),
            content: Text(_string(request, 'message')),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return true;
      case 'xbmcgui.Dialog.yesno':
        return await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(_string(request, 'heading')),
                content: Text(_string(request, 'message')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Não'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Sim'),
                  ),
                ],
              ),
            ) ??
            false;
      case 'xbmcgui.Dialog.select':
        return _showSelection(
          context,
          title: _string(request, 'heading'),
          options: _stringList(request.params['options']),
        );
      case 'xbmcgui.Dialog.contextmenu':
        return _showSelection(
          context,
          title: 'Opções',
          options: _stringList(request.params['options']),
        );
      case 'xbmcgui.Dialog.input':
        return _showInput(
          context,
          title: _string(request, 'heading'),
          initialValue: _string(request, 'default_text'),
          obscureText: false,
        );
      case 'xbmcgui.Keyboard.doModal':
        final value = await _showInput(
          context,
          title: _string(request, 'heading'),
          initialValue: _string(request, 'default_text'),
          obscureText: request.params['hidden'] == true,
          allowCancel: true,
        );
        return {
          'confirmed': value != null,
          'text': value ?? _string(request, 'default_text'),
        };
      case 'xbmcgui.Dialog.textviewer':
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_string(request, 'heading')),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: SelectableText(_string(request, 'text')),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fechar'),
              ),
            ],
          ),
        );
        return true;
      case 'xbmcgui.WindowXML.doModal':
        return showLegacyWindowXml(context, request);
      default:
        return request.defaultValue;
    }
  }

  static Future<int> _showSelection(
    BuildContext context, {
    required String title,
    required List<String> options,
  }) async {
    if (options.isEmpty) {
      return -1;
    }

    return await showDialog<int>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 620,
              height: 420,
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (_, index) => ListTile(
                  title: Text(options[index]),
                  onTap: () => Navigator.pop(dialogContext, index),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, -1),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ) ??
        -1;
  }

  static Future<String?> _showInput(
    BuildContext context, {
    required String title,
    required String initialValue,
    required bool obscureText,
    bool allowCancel = false,
  }) async {
    final controller = TextEditingController(text: initialValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: obscureText,
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            if (allowCancel)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  static String _string(LegacyRuntimeRequest request, String key) {
    return request.params[key]?.toString() ?? '';
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.map((item) => item.toString()).toList(growable: false);
  }
}
