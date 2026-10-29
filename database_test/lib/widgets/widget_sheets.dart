import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../database.dart';
import '../device_data.dart';
import '../device_presets.dart';
import '../device_session.dart';
import '../ui.dart';
import 'catalog.dart';
import 'widget_config.dart';

// Lets the user pick a widget that fits the device of [session] and set it
// up. Returns true if one was added
Future<bool> showAddWidgetSheet(BuildContext context, DeviceSession session) async {
  final type = await showModalBottomSheet<WidgetType>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _WidgetPickerSheet(device: session.device),
  );
  if (type == null || !context.mounted) return false;

  // Nothing to set up, e.g. the polling rate
  if (type.fields.isEmpty) {
    await database.addWidget(session.device.id, type.kind, jsonEncode(type.defaults));
    return true;
  }
  return showWidgetConfigSheet(context, session, type: type);
}

// Settings of a new widget of [type], or of the existing [entry]. Returns
// true if they were saved
Future<bool> showWidgetConfigSheet(
  BuildContext context,
  DeviceSession session, {
  WidgetType? type,
  DeviceWidget? entry,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _WidgetConfigSheet(
      session: session,
      type: type ?? widgetType(entry!.kind),
      entry: entry,
    ),
  );
  return saved ?? false;
}

class _WidgetPickerSheet extends StatelessWidget {
  final Device device;

  const _WidgetPickerSheet({required this.device});

  @override
  Widget build(BuildContext context) {
    final fitting = widgetTypes.where((t) => t.roles.contains(device.role));
    final groups = {
      '${device.role.label} widgets': fitting.where((t) => t.roles.length == 1),
      'General': fitting.where((t) => t.roles.length > 1),
    };

    return SheetBody(
      title: 'Add a widget',
      subtitle: 'To ${device.name}. You can add as many as you like.',
      children: [
        for (final MapEntry(key: group, value: types) in groups.entries)
          if (types.isNotEmpty) ...[
            GroupLabel(group),
            const SizedBox(height: 8),
            PickerGrid(
              children: [
                for (final type in types)
                  PickerTile<WidgetType>(
                    value: type,
                    icon: type.icon,
                    label: type.label,
                    subtitle: type.description,
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

class _WidgetConfigSheet extends StatefulWidget {
  final DeviceSession session;
  final WidgetType type;

  // null while adding, set while editing
  final DeviceWidget? entry;

  const _WidgetConfigSheet({required this.session, required this.type, this.entry});

  @override
  State<_WidgetConfigSheet> createState() => _WidgetConfigSheetState();
}

class _WidgetConfigSheetState extends State<_WidgetConfigSheet> {
  late final Map<String, Object?> _initial;
  late final Map<String, TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _initial = entry == null
        ? {...widget.type.defaults}
        : WidgetConfig.decode(entry.config).values;
    _ctrls = {
      for (final field in widget.type.fields)
        field.key: TextEditingController(text: WidgetConfig(_initial).text(field.key)),
    };
  }

  @override
  void dispose() {
    for (final ctrl in _ctrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // The settings as typed, numbers already parsed; null values mark numbers
  // that can't be read
  Map<String, Object?> get _values => {
        ..._initial, // keeps settings the sheet doesn't show
        for (final field in widget.type.fields)
          field.key: switch (field.input) {
            ConfigInput.number => _parseNumber(_ctrls[field.key]!.text),
            _ => _ctrls[field.key]!.text.trim(),
          },
      };

  // Whole numbers are kept as int, so they're stored as 1 instead of 1.0
  static num? _parseNumber(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite) return null;
    return value == value.roundToDouble() ? value.toInt() : value;
  }

  String? get _error {
    final values = _values;
    for (final field in widget.type.fields) {
      if (field.input == ConfigInput.number && values[field.key] == null) {
        return '${field.label[0]}${field.label.substring(1).toLowerCase()} must be a number';
      }
    }
    return widget.type.validate?.call(WidgetConfig(values));
  }

  // Data the field suggestions come from: the last response of a sensor, the
  // payload of an actuator
  Object? get _sampleData => widget.session.isSensor
      ? widget.session.latest?.data
      : decodeBody(widget.session.device.payload);

  Future<void> _save() async {
    final config = WidgetConfig(_values).encode();
    final entry = widget.entry;
    if (entry == null) {
      await database.addWidget(widget.session.device.id, widget.type.kind, config);
    } else {
      await (database.update(database.deviceWidgets)
            ..where((t) => t.id.equals(entry.id)))
          .write(DeviceWidgetsCompanion(config: Value(config)));
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final name = type.label.toLowerCase();
    final error = _error;

    return SheetBody(
      title: widget.entry == null ? 'Add $name' : 'Edit $name',
      subtitle: 'on ${widget.session.device.name}',
      children: [
        for (final field in type.fields) ...[
          TextField(
            controller: _ctrls[field.key],
            keyboardType: field.input == ConfigInput.number
                ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                : TextInputType.text,
            decoration: fieldDecoration(field.label, hint: field.hint),
            onChanged: (_) => setState(() {}), // keeps the save button in sync
          ),
          if (field.input == ConfigInput.field) _suggestions(field),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        SaveButton(
          enabled: error == null,
          label: error ?? (widget.entry == null ? 'Add $name' : 'Save changes'),
          onPressed: _save,
        ),
      ],
    );
  }

  // Fields found in the sample data, tapping one fills it in
  Widget _suggestions(ConfigField field) {
    final paths = fieldPaths(_sampleData);
    if (paths.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(
          widget.session.isSensor
              ? 'Fields of the response are suggested here after the first reading'
              : 'Fields of the payload are suggested here',
          style: TextStyle(fontSize: 12, color: context.design.muted),
        ),
      );
    }

    final ctrl = _ctrls[field.key]!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final path in paths)
            ChoiceChip(
              label: Text(path, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              selected: ctrl.text.trim() == path,
              onSelected: (_) => setState(() => ctrl.text = path),
            ),
        ],
      ),
    );
  }
}
