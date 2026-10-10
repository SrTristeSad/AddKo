import 'package:flutter/material.dart';

import '../../core/runtime/legacy/kodi_json_rpc_compat.dart';
import '../../core/runtime/legacy/legacy_runtime_request.dart';
import '../../core/ui/kodi_text.dart';
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
            title: KodiText(_string(request, 'heading')),
            content: KodiText(_string(request, 'message')),
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
                title: KodiText(_string(request, 'heading')),
                content: KodiText(_string(request, 'message')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(_buttonLabel(request, 'no_label', 'Não')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(_buttonLabel(request, 'yes_label', 'Sim')),
                  ),
                ],
              ),
            ) ??
            false;
      case 'xbmcgui.Dialog.yesnocustom':
        return await showDialog<int>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: KodiText(_string(request, 'heading')),
                content: KodiText(_string(request, 'message')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, 0),
                    child: Text(_buttonLabel(request, 'no_label', 'Não')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, 2),
                    child: Text(_buttonLabel(request, 'custom_label', 'Outro')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, 1),
                    child: Text(_buttonLabel(request, 'yes_label', 'Sim')),
                  ),
                ],
              ),
            ) ??
            -1;
      case 'xbmcgui.Dialog.select':
        return _showSelection(
          context,
          title: _string(request, 'heading'),
          options: _stringList(request.params['options']),
          preselect: _int(request.params['preselect'], fallback: -1),
        );
      case 'xbmcgui.Dialog.multiselect':
        return _showMultiSelection(
          context,
          title: _string(request, 'heading'),
          options: _stringList(request.params['options']),
          preselect: _intList(request.params['preselect']),
        );
      case 'xbmcgui.Dialog.contextmenu':
        return _showSelection(
          context,
          title: 'Opções',
          options: _stringList(request.params['options']),
        );
      case 'xbmcgui.Dialog.input':
        return showDialog<String>(
          context: context,
          builder: (_) => _TextInputDialog(
            title: KodiMarkup.strip(_string(request, 'heading')),
            initialValue: _string(request, 'default_text'),
            obscureText: request.params['hidden'] == true ||
                _int(request.params['input_type']) == 5,
            allowCancel: true,
            numeric: _int(request.params['input_type']) == 1,
          ),
        );
      case 'xbmcgui.Keyboard.doModal':
        final value = await showDialog<String>(
          context: context,
          builder: (_) => _TextInputDialog(
            title: KodiMarkup.strip(_string(request, 'heading')),
            initialValue: _string(request, 'default_text'),
            obscureText: request.params['hidden'] == true,
            allowCancel: true,
          ),
        );
        return {
          'confirmed': value != null,
          'text': value ?? _string(request, 'default_text'),
        };
      case 'xbmcgui.Dialog.textviewer':
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: KodiText(_string(request, 'heading')),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: SelectableText(
                  KodiMarkup.strip(_string(request, 'text')),
                ),
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
      case 'xbmcgui.Dialog.browse':
        if (request.params['enable_multiple'] == true) {
          return const <String>[];
        }
        return _string(request, 'default_value');
      case 'xbmcgui.getCurrentWindowId':
        return 10000;
      case 'xbmcgui.getCurrentWindowDialogId':
        return 0;
      case 'xbmcgui.getScreenWidth':
        return MediaQuery.sizeOf(context).width.round();
      case 'xbmcgui.getScreenHeight':
        return MediaQuery.sizeOf(context).height.round();
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
    int preselect = -1,
  }) async {
    if (options.isEmpty) {
      return -1;
    }

    return await showDialog<int>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: KodiText(title),
            content: SizedBox(
              width: 620,
              height: 420,
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (_, index) => ListTile(
                  selected: index == preselect,
                  title: KodiText(options[index]),
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

  static Future<List<int>?> _showMultiSelection(
    BuildContext context, {
    required String title,
    required List<String> options,
    required List<int> preselect,
  }) async {
    if (options.isEmpty) {
      return const <int>[];
    }
    return showDialog<List<int>>(
      context: context,
      builder: (_) => _MultiSelectDialog(
        title: title,
        options: options,
        preselect: preselect,
      ),
    );
  }

  static String _string(LegacyRuntimeRequest request, String key) {
    return request.params[key]?.toString() ?? '';
  }

  static String _buttonLabel(
    LegacyRuntimeRequest request,
    String key,
    String fallback,
  ) {
    final raw = _string(request, key);
    if (raw.isEmpty) return fallback;
    return KodiMarkup.strip(raw);
  }

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.map((item) => item.toString()).toList(growable: false);
  }

  static List<int> _intList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => _int(item, fallback: -1))
        .where((item) => item >= 0)
        .toList(growable: false);
  }
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initialValue,
    required this.obscureText,
    required this.allowCancel,
    this.numeric = false,
  });

  final String title;
  final String initialValue;
  final bool obscureText;
  final bool allowCancel;
  final bool numeric;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscureText,
        keyboardType: widget.numeric ? TextInputType.number : TextInputType.text,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        if (widget.allowCancel)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _MultiSelectDialog extends StatefulWidget {
  const _MultiSelectDialog({
    required this.title,
    required this.options,
    required this.preselect,
  });

  final String title;
  final List<String> options;
  final List<int> preselect;

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  late final Set<int> _selected = widget.preselect.toSet();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: KodiText(widget.title),
      content: SizedBox(
        width: 620,
        height: 420,
        child: ListView.builder(
          itemCount: widget.options.length,
          itemBuilder: (_, index) => CheckboxListTile(
            value: _selected.contains(index),
            title: KodiText(widget.options[index]),
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  _selected.add(index);
                } else {
                  _selected.remove(index);
                }
              });
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final result = _selected.toList(growable: false)..sort();
            Navigator.pop(context, result);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
