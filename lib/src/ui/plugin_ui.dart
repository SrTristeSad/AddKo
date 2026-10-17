import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

class PluginUiDocument {
  const PluginUiDocument({required this.title, required this.body});

  static const int maxNodes = 256;
  static const int maxDepth = 16;
  static const int maxFields = 64;
  static const int maxNavigationDepth = 32;
  static const int maxTabs = 8;
  static const int maxTextLength = 16 * 1024;
  static const int maxActionPayloadBytes = 8 * 1024;
  static const int maxFormPayloadBytes = 64 * 1024;

  final String title;
  final PluginUiNode body;

  static PluginUiDocument? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = _stringMap(value);
    if (map['type'] != 'page') return null;
    return PluginUiDocument.fromMap(map);
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
      title: _boundedString(
        map['title'] ?? 'Mini-app',
        field: 'page.title',
        max: 256,
      ),
      body: PluginUiNode._parse(
        _stringMap(body),
        depth: 1,
        budget: budget,
      ),
    );
  }

  Map<String, Object?> get initialFormValues {
    final values = <String, Object?>{};
    body._collectInitialFormValues(values);
    return Map<String, Object?>.unmodifiable(values);
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
  List<String> strings(String name) =>
      properties[name] as List<String>? ?? const <String>[];

  void _collectInitialFormValues(Map<String, Object?> values) {
    final name = string('name');
    if (name != null && properties.containsKey('value')) {
      values[name] = properties['value'];
    }
    for (final child in children) {
      child._collectInitialFormValues(values);
    }
  }

  static PluginUiNode _parse(
    Map<String, Object?> map, {
    required int depth,
    required _UiBudget budget,
  }) {
    if (depth > PluginUiDocument.maxDepth) {
      throw const PluginUiException(
        'A árvore de UI excede a profundidade máxima.',
      );
    }
    budget.addNode();

    final type = _boundedString(
      map['type'],
      field: 'component.type',
      max: 32,
    );
    const allowed = <String>{
      'text',
      'button',
      'image',
      'column',
      'row',
      'list',
      'grid',
      'card',
      'divider',
      'spacer',
      'input',
      'textarea',
      'search',
      'checkbox',
      'switch',
      'select',
      'tabs',
    };
    if (!allowed.contains(type)) {
      throw PluginUiException('Componente de UI não suportado: $type');
    }

    String? action;
    var actionArguments = const <Object?>[];
    if (map['action'] != null) {
      action = _boundedString(
        map['action'],
        field: '$type.action',
        max: 128,
      );
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(action)) {
        throw PluginUiException('Nome de ação Lua inválido: $action');
      }
      final rawArguments = map['args'];
      if (rawArguments != null) {
        // Lua uses {} for empty tables, which JSON encodes as an object.
        // Treat only an empty object as omitted positional arguments.
        // Non-empty objects remain invalid to preserve the action contract.
        final normalizedArguments = rawArguments is Map && rawArguments.isEmpty
            ? const <Object?>[]
            : rawArguments;
        if (normalizedArguments is! List || normalizedArguments.length > 32) {
          throw PluginUiException('$type.args é inválido.');
        }
        final bytes = utf8.encode(jsonEncode(normalizedArguments));
        if (bytes.length > PluginUiDocument.maxActionPayloadBytes) {
          throw PluginUiException('$type.args excede o limite de 8 KiB.');
        }
        actionArguments = List<Object?>.unmodifiable(normalizedArguments);
      }
    }

    final navigation = _enumString(
      map['navigation'],
      field: '$type.navigation',
      fallback: 'replace',
      allowed: const <String>{'replace', 'push', 'pop'},
    );

    final properties = <String, Object?>{
      'navigation': navigation,
    };
    final children = <PluginUiNode>[];

    if (action != null) {
      properties['submitForm'] = map['submit_form'] == true || type == 'search';
    }

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
      properties['label'] = _boundedString(
        map['label'],
        field: 'button.label',
        max: 256,
      );
      if (action == null && navigation != 'pop') {
        throw const PluginUiException(
          'button.action é obrigatório, exceto com navigation="pop".',
        );
      }
      properties['enabled'] = map['enabled'] is bool ? map['enabled'] : true;
      properties['variant'] = _enumString(
        map['variant'],
        field: 'button.variant',
        fallback: 'tonal',
        allowed: const <String>{'primary', 'tonal', 'outline', 'text'},
      );
    } else if (type == 'image') {
      final source = _boundedString(
        map['src'],
        field: 'image.src',
        max: 2048,
      );
      properties['src'] = source;
      final assetPath = _assetPathFromSource(source);
      if (assetPath != null) {
        properties['assetPath'] = assetPath;
      }
      properties['alt'] = _optionalBoundedString(
        map['alt'],
        field: 'image.alt',
        max: 512,
      );
      properties['fit'] = _enumString(
        map['fit'],
        field: 'image.fit',
        fallback: 'cover',
        allowed: const <String>{'cover', 'contain', 'fill'},
      );
      properties['height'] = _boundedNumber(
        map['height'],
        fallback: 220,
        min: 48,
        max: 720,
      );
    } else if (type == 'column' ||
        type == 'row' ||
        type == 'list' ||
        type == 'grid') {
      children.addAll(
        _parseChildren(map['children'], depth: depth, budget: budget),
      );
      if (type == 'grid') {
        properties['columns'] = _boundedNumber(
          map['columns'],
          fallback: 2,
          min: 1,
          max: 6,
        ).toInt();
        properties['ratio'] = _boundedNumber(
          map['ratio'],
          fallback: 1.0,
          min: 0.3,
          max: 4.0,
        ).toDouble();
      }
    } else if (type == 'card') {
      final child = map['child'];
      if (child != null) {
        if (child is! Map) {
          throw const PluginUiException(
            'card.child deve ser um componente.',
          );
        }
        children.add(
          PluginUiNode._parse(
            _stringMap(child),
            depth: depth + 1,
            budget: budget,
          ),
        );
      } else {
        children.addAll(
          _parseChildren(map['children'], depth: depth, budget: budget),
        );
      }
    } else if (type == 'spacer') {
      properties['size'] = _boundedNumber(
        map['size'],
        fallback: 16,
        min: 0,
        max: 256,
      ).toDouble();
    } else if (type == 'input' || type == 'textarea' || type == 'search') {
      final name = _fieldName(map, type, budget);
      properties['name'] = name;
      properties['label'] = _optionalBoundedString(
        map['label'],
        field: '$type.label',
        max: 256,
      );
      properties['hint'] = _optionalBoundedString(
        map['hint'],
        field: '$type.hint',
        max: 512,
      );
      final maxLength = _boundedNumber(
        map['max_length'],
        fallback: type == 'textarea' ? 16384 : (type == 'search' ? 512 : 4096),
        min: 1,
        max: type == 'textarea' ? 16384 : 4096,
      ).toInt();
      properties['maxLength'] = maxLength;
      properties['value'] = _optionalBoundedString(
            map['value'],
            field: '$type.value',
            max: maxLength,
          ) ??
          '';
      properties['enabled'] = map['enabled'] is bool ? map['enabled'] : true;
      if (type == 'input') {
        properties['obscure'] = map['obscure'] == true;
      }
    } else if (type == 'checkbox' || type == 'switch') {
      properties['name'] = _fieldName(map, type, budget);
      properties['label'] = _boundedString(
        map['label'],
        field: '$type.label',
        max: 256,
      );
      properties['value'] = map['value'] is bool ? map['value'] : false;
      properties['enabled'] = map['enabled'] is bool ? map['enabled'] : true;
    } else if (type == 'select') {
      properties['name'] = _fieldName(map, type, budget);
      properties['label'] = _optionalBoundedString(
        map['label'],
        field: 'select.label',
        max: 256,
      );
      properties['enabled'] = map['enabled'] is bool ? map['enabled'] : true;

      final rawOptions = map['options'];
      if (rawOptions is! List || rawOptions.isEmpty || rawOptions.length > 128) {
        throw const PluginUiException(
          'select.options deve conter entre 1 e 128 opções.',
        );
      }
      final options = <String>[];
      for (final raw in rawOptions) {
        final option = _boundedString(
          raw,
          field: 'select.options',
          max: 256,
        );
        if (options.contains(option)) {
          throw PluginUiException('Opção duplicada em select: $option');
        }
        options.add(option);
      }
      final selected = map['value'] == null
          ? options.first
          : _boundedString(map['value'], field: 'select.value', max: 256);
      if (!options.contains(selected)) {
        throw const PluginUiException(
          'select.value precisa existir em select.options.',
        );
      }
      properties['options'] = List<String>.unmodifiable(options);
      properties['value'] = selected;
    } else if (type == 'tabs') {
      final rawTabs = map['tabs'];
      if (rawTabs is! List ||
          rawTabs.isEmpty ||
          rawTabs.length > PluginUiDocument.maxTabs) {
        throw const PluginUiException(
          'tabs.tabs deve conter entre 1 e 8 abas.',
        );
      }

      final labels = <String>[];
      for (final rawTab in rawTabs) {
        if (rawTab is! Map) {
          throw const PluginUiException('tabs.tabs contém item inválido.');
        }
        final tab = _stringMap(rawTab);
        final label = _boundedString(
          tab['label'],
          field: 'tabs.tabs.label',
          max: 64,
        );
        if (labels.contains(label)) {
          throw PluginUiException('Rótulo de aba duplicado: $label');
        }
        final child = tab['child'];
        if (child is! Map) {
          throw const PluginUiException('tabs.tabs.child deve ser um componente.');
        }
        labels.add(label);
        children.add(
          PluginUiNode._parse(
            _stringMap(child),
            depth: depth + 1,
            budget: budget,
          ),
        );
      }
      properties['labels'] = List<String>.unmodifiable(labels);
      properties['index'] = _boundedNumber(
        map['index'],
        fallback: 0,
        min: 0,
        max: labels.length - 1,
      ).toInt();
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
      result.add(
        PluginUiNode._parse(
          _stringMap(item),
          depth: depth + 1,
          budget: budget,
        ),
      );
    }
    return result;
  }
}

typedef PluginUiAction = Future<Object?> Function(
  String method,
  List<Object?> arguments,
);

typedef PluginUiFormChanged = void Function(
  String name,
  Object? value, {
  bool rebuild,
});

class PluginUiPage extends StatefulWidget {
  const PluginUiPage({
    super.key,
    required this.initialDocument,
    required this.onAction,
    required this.allowNetworkImages,
    this.pluginRoot,
  });

  final PluginUiDocument initialDocument;
  final PluginUiAction onAction;
  final bool allowNetworkImages;
  final String? pluginRoot;

  @override
  State<PluginUiPage> createState() => _PluginUiPageState();
}

class _PluginUiPageState extends State<PluginUiPage> {
  late PluginUiDocument _document;
  late Map<String, Object?> _formValues;
  final List<_PluginUiSnapshot> _history = <_PluginUiSnapshot>[];
  bool _busy = false;
  int _documentVersion = 0;

  @override
  void initState() {
    super.initState();
    _document = widget.initialDocument;
    _formValues = Map<String, Object?>.of(_document.initialFormValues);
  }

  void _setFormValue(
    String name,
    Object? value, {
    bool rebuild = false,
  }) {
    if (rebuild) {
      setState(() => _formValues[name] = value);
    } else {
      _formValues[name] = value;
    }
  }

  void _replaceDocument(PluginUiDocument next) {
    setState(() {
      _document = next;
      _formValues = Map<String, Object?>.of(next.initialFormValues);
      _documentVersion += 1;
    });
  }

  void _pushDocument(PluginUiDocument next) {
    if (_history.length >= PluginUiDocument.maxNavigationDepth) {
      throw const PluginUiException(
        'A navegação excedeu o limite de 32 telas.',
      );
    }
    setState(() {
      _history.add(
        _PluginUiSnapshot(
          document: _document,
          formValues: Map<String, Object?>.of(_formValues),
        ),
      );
      _document = next;
      _formValues = Map<String, Object?>.of(next.initialFormValues);
      _documentVersion += 1;
    });
  }

  void _popDocument() {
    if (_history.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final previous = _history.removeLast();
    setState(() {
      _document = previous.document;
      _formValues = Map<String, Object?>.of(previous.formValues);
      _documentVersion += 1;
    });
  }

  Future<void> _runAction(PluginUiNode node) async {
    if (_busy) return;
    final navigation = node.string('navigation') ?? 'replace';
    final action = node.action;

    if (navigation == 'pop' && action == null) {
      _popDocument();
      return;
    }
    if (action == null) return;

    setState(() => _busy = true);
    try {
      final arguments = <Object?>[...node.actionArguments];
      if (node.boolean('submitForm') == true) {
        final encoded = utf8.encode(jsonEncode(_formValues));
        if (encoded.length > PluginUiDocument.maxFormPayloadBytes) {
          throw const PluginUiException(
            'Os dados do formulário excedem o limite de 64 KiB.',
          );
        }
        arguments.add(Map<String, Object?>.unmodifiable(_formValues));
      }

      final result = await widget.onAction(action, arguments);
      if (!mounted) return;

      if (navigation == 'pop') {
        _popDocument();
        return;
      }

      final next = PluginUiDocument.tryParse(result);
      if (next == null) return;
      if (navigation == 'push') {
        _pushDocument(next);
      } else {
        _replaceDocument(next);
      }
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
      appBar: AppBar(
        leading: _history.isEmpty
            ? null
            : IconButton(
                tooltip: 'Voltar',
                onPressed: _busy ? null : _popDocument,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(_document.title),
      ),
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
                  pluginRoot: widget.pluginRoot,
                  formValues: _formValues,
                  onFormChanged: _setFormValue,
                  documentVersion: _documentVersion,
                ),
              ],
            ),
            if (_busy)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

class _PluginUiSnapshot {
  const _PluginUiSnapshot({
    required this.document,
    required this.formValues,
  });

  final PluginUiDocument document;
  final Map<String, Object?> formValues;
}

class _PluginUiNodeView extends StatelessWidget {
  const _PluginUiNodeView({
    required this.node,
    required this.onAction,
    required this.allowNetworkImages,
    required this.pluginRoot,
    required this.formValues,
    required this.onFormChanged,
    required this.documentVersion,
  });

  final PluginUiNode node;
  final Future<void> Function(PluginUiNode node) onAction;
  final bool allowNetworkImages;
  final String? pluginRoot;
  final Map<String, Object?> formValues;
  final PluginUiFormChanged onFormChanged;
  final int documentVersion;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (final child in node.children) _childView(child),
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
        final onPressed = node.boolean('enabled') == false
            ? null
            : () => onAction(node);
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _spaced(children, 12),
        );
      case 'row':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final child in children)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: child,
                ),
              ),
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
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _spaced(children, 10),
              );
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: node.action == null ? null : () => onAction(node),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
          ),
        );
      case 'divider':
        return const Divider();
      case 'spacer':
        return SizedBox(height: (node.number('size') ?? 16).toDouble());
      case 'input':
      case 'textarea':
      case 'search':
        return _textField();
      case 'checkbox':
        return _checkbox();
      case 'switch':
        return _switch();
      case 'select':
        return _select();
      case 'tabs':
        return _PluginUiTabs(
          key: ValueKey<String>(
            'tabs:$documentVersion:${node.strings('labels').join('|')}',
          ),
          labels: node.strings('labels'),
          children: node.children,
          initialIndex: (node.number('index') ?? 0).toInt(),
          childBuilder: _childView,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _childView(PluginUiNode child) {
    return _PluginUiNodeView(
      node: child,
      onAction: onAction,
      allowNetworkImages: allowNetworkImages,
      pluginRoot: pluginRoot,
      formValues: formValues,
      onFormChanged: onFormChanged,
      documentVersion: documentVersion,
    );
  }

  Widget _textField() {
    final name = node.string('name')!;
    final current = formValues[name]?.toString() ?? '';
    final isTextarea = node.type == 'textarea';
    final isSearch = node.type == 'search';
    final enabled = node.boolean('enabled') != false;

    return TextFormField(
      key: ValueKey<String>('field:$documentVersion:$name'),
      initialValue: current,
      enabled: enabled,
      obscureText: node.type == 'input' && node.boolean('obscure') == true,
      minLines: isTextarea ? 4 : 1,
      maxLines: isTextarea ? 8 : 1,
      maxLength: node.number('maxLength')?.toInt(),
      textInputAction: isSearch ? TextInputAction.search : TextInputAction.next,
      decoration: InputDecoration(
        labelText: node.string('label'),
        hintText: node.string('hint'),
        border: const OutlineInputBorder(),
        prefixIcon: isSearch ? const Icon(Icons.search_rounded) : null,
      ),
      onChanged: (value) => onFormChanged(name, value),
      onFieldSubmitted: isSearch && node.action != null
          ? (_) => onAction(node)
          : null,
    );
  }

  Widget _checkbox() {
    final name = node.string('name')!;
    final value = formValues[name] == true;
    return CheckboxListTile(
      key: ValueKey<String>('field:$documentVersion:$name'),
      contentPadding: EdgeInsets.zero,
      title: Text(node.string('label')!),
      value: value,
      onChanged: node.boolean('enabled') == false
          ? null
          : (next) => onFormChanged(name, next == true, rebuild: true),
    );
  }

  Widget _switch() {
    final name = node.string('name')!;
    final value = formValues[name] == true;
    return SwitchListTile(
      key: ValueKey<String>('field:$documentVersion:$name'),
      contentPadding: EdgeInsets.zero,
      title: Text(node.string('label')!),
      value: value,
      onChanged: node.boolean('enabled') == false
          ? null
          : (next) => onFormChanged(name, next, rebuild: true),
    );
  }

  Widget _select() {
    final name = node.string('name')!;
    final options = node.strings('options');
    final rawValue = formValues[name];
    final selected = rawValue is String && options.contains(rawValue)
        ? rawValue
        : options.first;

    return DropdownButtonFormField<String>(
      key: ValueKey<String>('field:$documentVersion:$name'),
      initialValue: selected,
      decoration: InputDecoration(
        labelText: node.string('label'),
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final option in options)
          DropdownMenuItem<String>(
            value: option,
            child: Text(option),
          ),
      ],
      onChanged: node.boolean('enabled') == false
          ? null
          : (next) {
              if (next != null) {
                onFormChanged(name, next, rebuild: true);
              }
            },
    );
  }

  Widget _image(BuildContext context) {
    final source = node.string('src')!;
    final assetPath = node.string('assetPath');
    final height = (node.number('height') ?? 220).toDouble();
    final fit = switch (node.string('fit')) {
      'contain' => BoxFit.contain,
      'fill' => BoxFit.fill,
      _ => BoxFit.cover,
    };

    Widget image;
    if (assetPath != null) {
      final root = pluginRoot;
      if (root == null || root.isEmpty) {
        image = _imagePlaceholder(
          context,
          height,
          'Asset local indisponível fora de um pacote instalado.',
        );
      } else {
        final file = File(_resolveAssetFile(root, assetPath));
        image = Image.file(
          file,
          height: height,
          width: double.infinity,
          fit: fit,
          semanticLabel: node.string('alt'),
          errorBuilder: (context, error, stackTrace) => _imagePlaceholder(
            context,
            height,
            'Não foi possível carregar o asset local.',
          ),
        );
      }
    } else {
      final uri = Uri.tryParse(source);
      final isNetwork =
          uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
      if (!isNetwork) {
        image = _imagePlaceholder(
          context,
          height,
          'Fonte de imagem não suportada.',
        );
      } else if (!allowNetworkImages) {
        image = _imagePlaceholder(
          context,
          height,
          'Imagem de rede bloqueada: permissão network necessária',
        );
      } else {
        image = Image.network(
          source,
          height: height,
          width: double.infinity,
          fit: fit,
          semanticLabel: node.string('alt'),
          errorBuilder: (context, error, stackTrace) => _imagePlaceholder(
            context,
            height,
            'Não foi possível carregar a imagem.',
          ),
        );
      }
    }

    return node.action == null
        ? image
        : InkWell(onTap: () => onAction(node), child: image);
  }

  Widget _imagePlaceholder(
    BuildContext context,
    double height,
    String message,
  ) {
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, textAlign: TextAlign.center),
    );
  }
}

class _PluginUiTabs extends StatefulWidget {
  const _PluginUiTabs({
    super.key,
    required this.labels,
    required this.children,
    required this.initialIndex,
    required this.childBuilder,
  });

  final List<String> labels;
  final List<PluginUiNode> children;
  final int initialIndex;
  final Widget Function(PluginUiNode child) childBuilder;

  @override
  State<_PluginUiTabs> createState() => _PluginUiTabsState();
}

class _PluginUiTabsState extends State<_PluginUiTabs> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < widget.labels.length; index += 1)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(widget.labels[index]),
                    selected: index == _index,
                    onSelected: (_) => setState(() => _index = index),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        widget.childBuilder(widget.children[_index]),
      ],
    );
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
  final Set<String> fieldNames = <String>{};

  void addNode() {
    nodes += 1;
    if (nodes > PluginUiDocument.maxNodes) {
      throw const PluginUiException(
        'A árvore de UI contém componentes demais.',
      );
    }
  }

  void addField(String name) {
    if (fieldNames.length >= PluginUiDocument.maxFields) {
      throw const PluginUiException(
        'A página contém campos de formulário demais.',
      );
    }
    if (!fieldNames.add(name)) {
      throw PluginUiException('Nome de campo duplicado: $name');
    }
  }
}

String _fieldName(
  Map<String, Object?> map,
  String type,
  _UiBudget budget,
) {
  final name = _boundedString(map['name'], field: '$type.name', max: 128);
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(name)) {
    throw PluginUiException('Nome de campo inválido: $name');
  }
  budget.addField(name);
  return name;
}

String? _assetPathFromSource(String source) {
  if (!source.startsWith('asset:')) return null;

  var path = source.substring('asset:'.length);
  if (path.startsWith('//')) {
    path = path.substring(2);
  }
  if (path.isEmpty ||
      path.length > 512 ||
      path.startsWith('/') ||
      path.contains('\\') ||
      path.contains(':') ||
      path.contains('\u0000')) {
    throw const PluginUiException('image.src contém asset local inválido.');
  }

  final segments = path.split('/');
  if (segments.length < 2 ||
      segments.first != 'assets' ||
      segments.any((segment) =>
          segment.isEmpty || segment == '.' || segment == '..')) {
    throw const PluginUiException(
      'Assets locais precisam usar asset:assets/... sem traversal.',
    );
  }
  return segments.join('/');
}

String _resolveAssetFile(String root, String assetPath) {
  final suffix = assetPath.split('/').join(Platform.pathSeparator);
  return root.endsWith(Platform.pathSeparator)
      ? '$root$suffix'
      : '$root${Platform.pathSeparator}$suffix';
}

Map<String, Object?> _stringMap(Map raw) {
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw const PluginUiException(
        'Objeto de UI contém chave não textual.',
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _boundedString(
  Object? value, {
  required String field,
  required int max,
}) {
  if (value is! String || value.isEmpty || value.length > max) {
    throw PluginUiException('$field é inválido.');
  }
  return value;
}

String? _optionalBoundedString(
  Object? value, {
  required String field,
  required int max,
}) {
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
    throw PluginUiException('$field é inválido.');
  }
  return value;
}

num _boundedNumber(
  Object? value, {
  required num fallback,
  required num min,
  required num max,
}) {
  if (value == null) return fallback;
  if (value is! num || !value.isFinite || value < min || value > max) {
    throw const PluginUiException('Valor numérico de UI inválido.');
  }
  return value;
}

List<Widget> _spaced(List<Widget> children, double gap) {
  if (children.length < 2) return children;
  final result = <Widget>[];
  for (var index = 0; index < children.length; index += 1) {
    if (index > 0) result.add(SizedBox(height: gap));
    result.add(children[index]);
  }
  return result;
}
