import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/runtime/legacy/legacy_runtime_request.dart';

Future<Object?> showLegacyWindowXml(
  BuildContext context,
  LegacyRuntimeRequest request,
) {
  final width = _number(request.params['width'], 1280).clamp(320, 7680).toDouble();
  final height = _number(request.params['height'], 720).clamp(240, 4320).toDouble();
  final controls = _mapList(request.params['controls']);
  final windowItems = _mapList(request.params['list_items']);
  final title = request.params['title']?.toString() ?? '';

  return showDialog<Object?>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            Navigator.pop(dialogContext, const {'action': 'close'});
          }
        },
        child: Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Text(title.isEmpty ? 'Addon' : title),
              actions: [
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    const {'action': 'close'},
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: Center(
              child: AspectRatio(
                aspectRatio: width / height,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scaleX = constraints.maxWidth / width;
                    final scaleY = constraints.maxHeight / height;
                    return ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          for (final control in controls)
                            ..._renderControl(
                              context,
                              dialogContext,
                              control,
                              windowItems: windowItems,
                              scaleX: scaleX,
                              scaleY: scaleY,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  ).then((value) => value ?? const {'action': 'close'});
}

List<Widget> _renderControl(
  BuildContext context,
  BuildContext dialogContext,
  Map<String, Object?> control, {
  required List<Map<String, Object?>> windowItems,
  required double scaleX,
  required double scaleY,
}) {
  if (control['visible'] == false) {
    return const [];
  }

  final type = control['type']?.toString().toLowerCase() ?? 'control';
  if (type == 'group') {
    final children = _mapList(control['children']);
    return [
      for (final child in children)
        ..._renderControl(
          context,
          dialogContext,
          child,
          windowItems: windowItems,
          scaleX: scaleX,
          scaleY: scaleY,
        ),
    ];
  }

  final id = _number(control['id'], -1).toInt();
  final x = _number(control['x'], 0).toDouble() * scaleX;
  final y = _number(control['y'], 0).toDouble() * scaleY;
  final width = _number(control['width'], 200).toDouble() * scaleX;
  final height = _number(control['height'], 50).toDouble() * scaleY;
  final enabled = control['enabled'] != false;
  final label = control['label']?.toString() ?? '';

  void click({int? listPosition}) {
    Navigator.pop(
      dialogContext,
      {
        'action': 'click',
        'control_id': id,
        if (listPosition != null) 'list_position': listPosition,
      },
    );
  }

  Widget child;
  switch (type) {
    case 'label':
      child = Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      );
      break;
    case 'textbox':
      child = SingleChildScrollView(
        child: Text(label),
      );
      break;
    case 'button':
      child = FilledButton.tonal(
        onPressed: enabled ? click : null,
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
      break;
    case 'radiobutton':
      final selected = control['selected'] == true;
      child = FilledButton.tonalIcon(
        onPressed: enabled ? click : null,
        icon: Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_off_rounded,
        ),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
      break;
    case 'image':
    case 'multiimage':
      child = _KodiTexture(
        source: control['texture']?.toString(),
      );
      break;
    case 'progress':
      final percent = _number(control['percent'], 0)
          .toDouble()
          .clamp(0.0, 100.0)
          .toDouble();
      child = Center(
        child: LinearProgressIndicator(value: percent / 100.0),
      );
      break;
    case 'slider':
      final percent = _number(control['percent'], 0)
          .toDouble()
          .clamp(0.0, 100.0)
          .toDouble();
      child = Slider(
        value: percent,
        min: 0,
        max: 100,
        onChanged: enabled ? (_) => click() : null,
      );
      break;
    case 'edit':
      child = TextField(
        enabled: enabled,
        controller: TextEditingController(
          text: control['label2']?.toString() ?? '',
        ),
        decoration: InputDecoration(
          labelText: label.isEmpty ? null : label,
          border: const OutlineInputBorder(),
        ),
        readOnly: true,
        onTap: enabled ? click : null,
      );
      break;
    case 'list':
    case 'panel':
    case 'fixedlist':
    case 'wraplist':
      final ownItems = _mapList(control['items']);
      final items = ownItems.isEmpty ? windowItems : ownItems;
      final selected = _number(control['selected_position'], 0).toInt();
      child = Material(
        color: Colors.transparent,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: items.length,
          itemBuilder: (_, index) {
            final item = items[index];
            final itemLabel = item['label']?.toString() ?? '';
            final itemLabel2 = item['label2']?.toString() ?? '';
            return ListTile(
              dense: true,
              selected: index == selected,
              title: Text(
                itemLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: itemLabel2.isEmpty
                  ? null
                  : Text(
                      itemLabel2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: enabled ? () => click(listPosition: index) : null,
            );
          },
        ),
      );
      break;
    default:
      child = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Center(
          child: Text(
            label.isEmpty ? type : label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
  }

  return [
    Positioned(
      left: x,
      top: y,
      width: width <= 0 ? 1 : width,
      height: height <= 0 ? 1 : height,
      child: IgnorePointer(
        ignoring: !enabled,
        child: child,
      ),
    ),
  ];
}

class _KodiTexture extends StatelessWidget {
  const _KodiTexture({required this.source});

  final String? source;

  @override
  Widget build(BuildContext context) {
    final value = source?.trim();
    if (value == null || value.isEmpty) {
      return const SizedBox.shrink();
    }

    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return Image.network(
        value,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    final file = File(value);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return const SizedBox.shrink();
  }
}

num _number(Object? value, num fallback) {
  if (value is num) {
    return value;
  }
  return num.tryParse(value?.toString() ?? '') ?? fallback;
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}
