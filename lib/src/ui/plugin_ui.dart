import 'dart:convert';

import 'package:flutter/material.dart';

class PluginUiDocument {
  const PluginUiDocument({required this.title, required this.body});

  static const int maxNodes = 256;
  static const int maxDepth = 16;
  static const int maxTextLength = 16 * 1024;
  static const int maxActionPayloadBytes = 8 * 1024;

  final String title;
  final PluginUiNode body;

  static PluginUiDocument? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = _stringMap(value);
    if (map['type'] != 'page') return null;
    return fromMap(map);
  }

  factory PluginUiDocument.fromMap(Map<String, Object?> map) {
    if (map['type'] != 'page') {
      throw const PluginUiException('A raiz da UI deve ter type="page".');
    }
    final body = map['body'];
    if (body is! Map) {
      throw const PluginUiException('page.body deve ser um componente.');
    }
    final budget = _UiBudget();
    return PluginUiDocument(
      title: _boundedString(map['title'] ?? 'Mini-app', field: 'page.title', max: 256),
      body: PluginUiNode._parse(_stringMap(body), depth: 1, budget: budget),
    );
  }
}

class PluginUiNode {
  const PluginUiNode._({
    required this.type,
    required this.properties,
    required this.children,
    this.action,
    this.actionArguments = const <Object?>[],
  });

  final String type;
  final Map<String, Object?> properties;
  final List<PluginUiNode> children;
  final String? action;
  final List<Object?> actionArguments;

  String? string(String name) => properties[name] as String?;
  bool? boolean(String name) => properties[name] as bool?;
  num? number(String name) => properties[name] as num?;

  static PluginUiNode _parse(
    Map<String, Object?> map, {
    required int depth,
    required _UiBudget budget,
  }) {
    if (depth > PluginUiDocument.maxDepth) {
      throw const PluginUiException('A árvore de UI excede a profundidade máxima.');
    }
    budget.addNode();

    final type = _boundedString(map['type'], field: 'component.type', max: 32);
    const allowed = <String>{
      'text', 'button', 'image', 'column', 'row', 'list', 'grid', 'card', 'divider', 'spacer',
    };
    if (!allowed.contains(type)) {
      throw PluginUiException('Componente de UI não suportado: $type');
    }

    String? action;
    var actionArguments = const <Object?>[];
    if (map['action'] != null) {
      action = _boundedString(map['action'], field: '$type.action', max: 128);
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(action)) {
        throw PluginUiException('Nome de ação Lua inválido: $action');
      }
      final rawArguments = map['args'];
      if (rawArguments != null) {
        if (rawArguments is! List || rawArguments.length > 32) {
          throw PluginUiException('$type.args é inválido.');
        }
        final bytes = utf8.encode(jsonEncode(rawArguments));
        if (bytes.length > PluginUiDocument.maxActionPayloadBytes) {
          throw PluginUiException('$type.args excede o limite de 8 KiB.');
        }
        actionArguments = List<Object?>.unmodifiable(rawArguments);
      }
    }

    final properties = <String, Object?>{};
    final children = <PluginUiNode>[];

    if (type == 'text') {
      properties['text'] = _boundedString(
        map['text'],
        field: 'text.text',
        max: PluginUiDocument.maxTextLength,
      );
      properties['style'] = _enumString(
        map['style'],
        field: 'text.style',
        fallback: 'body',
        allowed: const <String>{'headline', 'title', 'body', 'caption'},
      );
      properties['align'] = _enumString(
        map['align'],
        field: 'text.align',
        fallback: 'start',
        allowed: const <String>{'start', 'center', 'end'},
      );
    } else if (type == 'button') {
      properties['label'] = _boundedString(map['label'], field: 'button.label', max: 256);
      if (action == null) {
        throw const PluginUiException('button.action é obrigatório.');
      }
      properties['enabled'] = map['enabled'] is bool ? map['enabled'] : true;
      properties['variant'] = _enumString(
        map['variant'],
        field: 'button.variant',
        fallback: 'tonal',
        allowed: const <String>{'primary', 'tonal', 'outline', 'text'},
      );
    } else if (type == 'image') {
      properties['src'] = _boundedString(map['src'], field: 'image.src', max: 2048);
      properties['alt'] = _optionalBoundedString(map['alt'], field: 'image.alt', max: 512);
      properties['fit'] = _enumString(
        map['fit'],
        field: 'image.fit',
        fallback: 'cover',
        allowed: const <String>{'cover', 'contain', 'fill'},
      );
      properties['height'] = _boundedNumber(map['height'], fallback: 220, min: 48, max: 720);
    } else if (type == 'column' || type == 'row' || type == 'list' || type == 'grid') {
      children.addAll(_parseChildren(map['children'], depth: depth, budget: budget));
      if (type == 'grid') {
        properties['columns'] = _boundedNumber(map['columns'], fallback: 2, min: 1, max: 6).toInt();
        properties['ratio'] = _boundedNumber(map['ratio'], fallback: 1.0, min: 0.3, max: 4.0).toDouble();
      }
    } else if (type == 'card') {
      final child = map['child'];
      if (child != null) {
        if (child is! Map) {
          throw const PluginUiException('card.child deve ser um componente.');
        }
        children.add(PluginUiNode._parse(_stringMap(child), depth: depth + 1, budget: budget));
      } else {
        children.addAll(_parseChildren(map['children'], depth: depth, budget: budget));
      }
    } else if (type == 'spacer') {
      properties['size'] = _boundedNumber(map['size'], fallback: 16, min: 0, max: 256).toDouble();
    }

    return PluginUiNode._(
      type: type,
      properties: Map<String, Object?>.unmodifiable(properties),
      children: List<PluginUiNode>.unmodifiable(children),
      action: action,
      actionArguments: actionArguments,
    );
  }

  static List<PluginUiNode> _parseChildren(
    Object? raw, {
    required int depth,
    required _UiBudget budget,
  }) {
    if (raw == null) return const <PluginUiNode>[];
    if (raw is! List || raw.length > 128) {
      throw const PluginUiException('children é inválido.');
    }
    final result = <PluginUiNode>[];
    for (final item in raw) {
      if (item is! Map) {
        throw const PluginUiException('children contém item inválido.');
      }
      result.add(PluginUiNode._parse(_stringMap(item), depth: depth + 1, budget: budget));
    }
    return result;
  }
}

typedef PluginUiAction = Future<Object?> Function(String method, List<Object?> arguments);

class PluginUiPage extends StatefulWidget {
  const PluginUiPage({
    super.key,
    required this.initialDocument,
    required this.onAction,
    required this.allowNetworkImages,
  });

  final PluginUiDocument initialDocument;
  final PluginUiAction onAction;
  final bool allowNetworkImages;

  @override
  State<PluginUiPage> createState() => _PluginUiPageState();
}

class _PluginUiPageState extends State<PluginUiPage> {
  late PluginUiDocument _document;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _document = widget.initialDocument;
  }

  Future<void> _runAction(PluginUiNode node) async {
    final action = node.action;
    if (action == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.onAction(action, node.actionArguments);
      final next = PluginUiDocument.tryParse(result);
      if (next != null && mounted) setState(() => _document = next);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no mini-app: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_document.title)),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _PluginUiNodeView(
                  node: _document.body,
                  onAction: _runAction,
                  allowNetworkImages: widget.allowNetworkImages,
                ),
              ],
            ),
            if (_busy)
              const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

class _PluginUiNodeView extends StatelessWidget {
  const _PluginUiNodeView({
    required this.node,
    required this.onAction,
    required this.allowNetworkImages,
  });

  final PluginUiNode node;
  final Future<void> Function(PluginUiNode node) onAction;
  final bool allowNetworkImages;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (final child in node.children)
        _PluginUiNodeView(node: child, onAction: onAction, allowNetworkImages: allowNetworkImages),
    ];

    switch (node.type) {
      case 'text':
        final style = switch (node.string('style')) {
          'headline' => Theme.of(context).textTheme.headlineMedium,
          'title' => Theme.of(context).textTheme.titleLarge,
          'caption' => Theme.of(context).textTheme.bodySmall,
          _ => Theme.of(context).textTheme.bodyLarge,
        };
        final align = switch (node.string('align')) {
          'center' => TextAlign.center,
          'end' => TextAlign.end,
          _ => TextAlign.start,
        };
        return Text(node.string('text')!, textAlign: align, style: style);
      case 'button':
        final onPressed = node.boolean('enabled') == false ? null : () => onAction(node);
        final label = Text(node.string('label')!);
        return switch (node.string('variant')) {
          'primary' => FilledButton(onPressed: onPressed, child: label),
          'outline' => OutlinedButton(onPressed: onPressed, child: label),
          'text' => TextButton(onPressed: onPressed, child: label),
          _ => FilledButton.tonal(onPressed: onPressed, child: label),
        };
      case 'image':
        return _image(context);
      case 'column':
      case 'list':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(children, 12));
      case 'row':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final child in children)
              Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: child)),
          ],
        );
      case 'grid':
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: (node.number('columns') ?? 2).toInt(),
          childAspectRatio: (node.number('ratio') ?? 1).toDouble(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: children,
        );
      case 'card':
        final content = children.length == 1
            ? children.first
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(children, 10));
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: node.action == null ? null : () => onAction(node),
            child: Padding(padding: const EdgeInsets.all(16), child: content),
          ),
        );
      case 'divider':
        return const Divider();
      case 'spacer':
        return SizedBox(height: (node.number('size') ?? 16).toDouble());
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _image(BuildContext context) {
    final source = node.string('src')!;
    final uri = Uri.tryParse(source);
    final isNetwork = uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
    final height = (node.number('height') ?? 220).toDouble();
    if (!isNetwork || !allowNetworkImages) {
      return Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          allowNetworkImages
              ? 'Fonte de imagem não suportada'
              : 'Imagem de rede bloqueada: permissão network necessária',
          textAlign: TextAlign.center,
        ),
      );
    }

    final fit = switch (node.string('fit')) {
      'contain' => BoxFit.contain,
      'fill' => BoxFit.fill,
      _ => BoxFit.cover,
    };
    final image = Image.network(
      source,
      height: height,
      width: double.infinity,
      fit: fit,
      semanticLabel: node.string('alt'),
      errorBuilder: (context, error, stackTrace) => SizedBox(
        height: height,
        child: const Center(child: Text('Não foi possível carregar a imagem.')),
      ),
    );
    return node.action == null ? image : InkWell(onTap: () => onAction(node), child: image);
  }
}

class PluginUiException implements Exception {
  const PluginUiException(this.message);
  final String message;
  @override
  String toString() => 'PluginUiException: $message';
}

class _UiBudget {
  int nodes = 0;
  void addNode() {
    nodes += 1;
    if (nodes > PluginUiDocument.maxNodes) {
      throw const PluginUiException('A árvore de UI contém componentes demais.');
    }
  }
}

Map<String, Object?> _stringMap(Map raw) {
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw const PluginUiException('Objeto de UI contém chave não textual.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _boundedString(Object? value, {required String field, required int max}) {
  if (value is! String || value.isEmpty || value.length > max) {
    throw PluginUiException('$field é inválido.');
  }
  return value;
}

String? _optionalBoundedString(Object? value, {required String field, required int max}) {
  if (value == null) return null;
  if (value is! String || value.length > max) {
    throw PluginUiException('$field é inválido.');
  }
  return value;
}

String _enumString(
  Object? value, {
  required String field,
  required String fallback,
  required Set<String> allowed,
}) {
  if (value == null) return fallback;
  if (value is! String || !allowed.contains(value)) {
    throw PluginUiException('$field possui valor não suportado.');
  }
  return value;
}

num _boundedNumber(Object? value, {required num fallback, required num min, required num max}) {
  if (value == null) return fallback;
  if (value is! num || !value.isFinite || value < min || value > max) {
    throw const PluginUiException('Valor numérico da UI fora do intervalo.');
  }
  return value;
}

List<Widget> _spaced(List<Widget> children, double spacing) {
  if (children.length < 2) return children;
  final result = <Widget>[];
  for (var index = 0; index < children.length; index++) {
    if (index > 0) result.add(SizedBox(height: spacing));
    result.add(children[index]);
  }
  return result;
}
