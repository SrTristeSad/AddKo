import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../core/addons/domain/installed_addon.dart';

class LegacyAddonSettingsPage extends StatefulWidget {
  const LegacyAddonSettingsPage({
    required this.addon,
    required this.addonDataRootPath,
    super.key,
  });

  final InstalledAddon addon;
  final String addonDataRootPath;

  @override
  State<LegacyAddonSettingsPage> createState() => _LegacyAddonSettingsPageState();
}

class _LegacyAddonSettingsPageState extends State<LegacyAddonSettingsPage> {
  List<_SettingDefinition> _definitions = const [];
  Map<String, String> _values = const {};
  String? _error;
  bool _loading = true;
  bool _saving = false;

  File get _settingsFile => File(
        p.join(
          widget.addonDataRootPath,
          widget.addon.manifest.id,
          'settings.json',
        ),
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final definitions = await _loadDefinitions();
      final stored = await _loadValues();
      final values = <String, String>{
        for (final definition in definitions)
          definition.id: stored[definition.id] ?? definition.defaultValue,
        ...stored,
      };
      if (!mounted) return;
      setState(() {
        _definitions = definitions;
        _values = values;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<List<_SettingDefinition>> _loadDefinitions() async {
    final candidates = [
      File(p.join(widget.addon.installPath, 'resources', 'settings.xml')),
      File(
        p.join(
          widget.addon.installPath,
          'resources',
          'settings',
          'settings.xml',
        ),
      ),
    ];

    File? source;
    for (final candidate in candidates) {
      if (await candidate.exists()) {
        source = candidate;
        break;
      }
    }
    if (source == null) return const [];

    final document = XmlDocument.parse(await source.readAsString());
    final definitions = <_SettingDefinition>[];
    for (final setting in document.descendants.whereType<XmlElement>()) {
      if (setting.name.local != 'setting') continue;
      final id = setting.getAttribute('id')?.trim();
      if (id == null || id.isEmpty) continue;

      final control = setting.descendants
          .whereType<XmlElement>()
          .where((node) => node.name.local == 'control')
          .firstOrNull;
      final type = (setting.getAttribute('type') ??
              control?.getAttribute('type') ??
              'text')
          .trim()
          .toLowerCase();
      final rawLabel = setting.getAttribute('label')?.trim();
      final label = rawLabel == null || rawLabel.isEmpty || int.tryParse(rawLabel) != null
          ? id
          : rawLabel;
      final defaultValue = setting.getAttribute('default') ??
          setting.getElement('default')?.innerText ??
          '';

      final options = <_SettingOption>[];
      for (final option in setting.descendants.whereType<XmlElement>()) {
        if (option.name.local != 'option') continue;
        final value = option.getAttribute('value') ?? option.innerText;
        final optionLabel = option.getAttribute('label') ?? option.innerText;
        if (value.trim().isNotEmpty) {
          options.add(_SettingOption(label: optionLabel.trim(), value: value.trim()));
        }
      }
      final oldValues = setting.getAttribute('values');
      if (options.isEmpty && oldValues != null && oldValues.trim().isNotEmpty) {
        for (final value in oldValues.split('|')) {
          options.add(_SettingOption(label: value, value: value));
        }
      }

      definitions.add(
        _SettingDefinition(
          id: id,
          label: label,
          type: type,
          defaultValue: defaultValue,
          options: options,
        ),
      );
    }
    return definitions;
  }

  Future<Map<String, String>> _loadValues() async {
    if (!await _settingsFile.exists()) return {};
    try {
      final decoded = jsonDecode(await _settingsFile.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value?.toString() ?? '',
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _settingsFile.parent.create(recursive: true);
      final temporary = File('${_settingsFile.path}.tmp');
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_values),
        flush: true,
      );
      if (await _settingsFile.exists()) {
        await _settingsFile.delete();
      }
      await temporary.rename(_settingsFile.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações salvas.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configurações • ${widget.addon.manifest.name}'),
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: _saving || _loading ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_definitions.isEmpty) {
      return const Center(
        child: Text('Este addon não declarou configurações em settings.xml.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
      itemCount: _definitions.length,
      separatorBuilder: (_, __) => const Divider(height: 28),
      itemBuilder: (context, index) {
        final definition = _definitions[index];
        return _buildSetting(definition);
      },
    );
  }

  Widget _buildSetting(_SettingDefinition definition) {
    final value = _values[definition.id] ?? definition.defaultValue;
    if (definition.isBoolean) {
      final enabled = {'true', '1', 'yes', 'on'}.contains(value.toLowerCase());
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(definition.label),
        subtitle: Text(definition.id),
        value: enabled,
        onChanged: (next) => setState(() {
          _values = {..._values, definition.id: next ? 'true' : 'false'};
        }),
      );
    }

    if (definition.options.isNotEmpty) {
      final selected = definition.options.any((option) => option.value == value)
          ? value
          : null;
      return DropdownButtonFormField<String>(
        value: selected,
        decoration: InputDecoration(
          labelText: definition.label,
          helperText: definition.id,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final option in definition.options)
            DropdownMenuItem(value: option.value, child: Text(option.label)),
        ],
        onChanged: (next) {
          if (next == null) return;
          setState(() => _values = {..._values, definition.id: next});
        },
      );
    }

    return TextFormField(
      key: ValueKey('${definition.id}:$value'),
      initialValue: value,
      keyboardType: definition.isNumeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      inputFormatters: definition.isInteger
          ? [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))]
          : null,
      decoration: InputDecoration(
        labelText: definition.label,
        helperText: definition.id,
        border: const OutlineInputBorder(),
      ),
      onChanged: (next) => _values = {..._values, definition.id: next},
    );
  }
}

class _SettingDefinition {
  const _SettingDefinition({
    required this.id,
    required this.label,
    required this.type,
    required this.defaultValue,
    required this.options,
  });

  final String id;
  final String label;
  final String type;
  final String defaultValue;
  final List<_SettingOption> options;

  bool get isBoolean => type == 'bool' || type == 'boolean' || type == 'toggle';
  bool get isInteger => type == 'integer' || type == 'int';
  bool get isNumeric => isInteger || type == 'number' || type == 'slider';
}

class _SettingOption {
  const _SettingOption({required this.label, required this.value});

  final String label;
  final String value;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
