import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import 'database.dart';
import 'device_presets.dart';
import 'request.dart';
import 'room_icons.dart';

// Colors reused by the sheet controls.
const Color _fieldColor = Color(0xFFEDE9E3);
const Color _subtitleColor = Color(0xFF8D6E4A);

// Sheet 1: create a room - only a name and an icon are needed.
Future<void> showAddRoomSheet(BuildContext context, {required int position}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // lets the sheet grow when the keyboard opens
    showDragHandle: true,
    builder: (_) => _AddRoomSheet(position: position),
  );
}

// Sheet 2: pick what to add (a preset like the lamp or a plain resource),
// then sheet 3 asks for its address
Future<void> showAddDeviceSheet(BuildContext context, Room room) async {
  final template = await showModalBottomSheet<DeviceTemplate>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DevicePickerSheet(room: room),
  );
  if (template == null || !context.mounted) return;
  await showDeviceSheet(context, room, template: template);
}

// Sheet 3: create a CoAP/HTTP resource inside [room] from [template], or edit
// an existing one when [device] is given
Future<void> showDeviceSheet(
  BuildContext context,
  Room room, {
  Device? device,
  DeviceTemplate? template,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DeviceSheet(room: room, device: device, template: template),
  );
}

class _AddRoomSheet extends StatefulWidget {
  final int position;

  const _AddRoomSheet({required this.position});

  @override
  State<_AddRoomSheet> createState() => _AddRoomSheetState();
}

class _AddRoomSheetState extends State<_AddRoomSheet> {
  final _nameCtrl = TextEditingController();
  int _iconIndex = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await database.into(database.rooms).insert(
          RoomsCompanion.insert(
            name: _nameCtrl.text.trim(),
            iconIndex: Value(_iconIndex),
            position: Value(widget.position),
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasName = _nameCtrl.text.trim().isNotEmpty;

    return _SheetBody(
      title: 'Add a room',
      subtitle: 'Name it after the real room - devices get grouped under it.',
      children: [
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          decoration: _fieldDecoration('NAME', hint: 'e.g. Living room'),
          onChanged: (_) => setState(() {}), // keeps the save button in sync
        ),
        const SizedBox(height: 16),
        const Text('Icon', style: TextStyle(fontSize: 13, color: _subtitleColor)),
        const SizedBox(height: 8),
        _IconPicker(
          selected: _iconIndex,
          onSelected: (index) => setState(() => _iconIndex = index),
        ),
        const SizedBox(height: 20),
        _SaveButton(
          enabled: hasName,
          label: hasName ? 'Add room' : 'Give the room a name',
          onPressed: _save,
        ),
      ],
    );
  }
}

class _DevicePickerSheet extends StatelessWidget {
  final Room room;

  const _DevicePickerSheet({required this.room});

  @override
  Widget build(BuildContext context) {
    // A set keeps the order in which the groups first appear
    final groups = {for (final template in deviceTemplates) template.group};

    return _SheetBody(
      title: 'Add a device',
      subtitle: 'To ${room.name}. Pick what it is - you set the address next.',
      children: [
        for (final group in groups) ...[
          Text(
            group.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              color: _subtitleColor,
            ),
          ),
          const SizedBox(height: 8),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 64,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            children: [
              for (final template in deviceTemplates)
                if (template.group == group) _TemplateTile(template: template),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

// Closes the picker with its template as result
class _TemplateTile extends StatelessWidget {
  final DeviceTemplate template;

  const _TemplateTile({required this.template});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context, template),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: _fieldColor, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _fieldColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(template.icon, size: 20, color: Colors.black87),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    template.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: _subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceSheet extends StatefulWidget {
  final Room room;

  // null while creating, set while editing an existing device.
  final Device? device;

  // Picked in the "Add a device" sheet, only set while creating
  final DeviceTemplate? template;

  const _DeviceSheet({required this.room, required this.device, required this.template});

  @override
  State<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<_DeviceSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _pathCtrl;
  late final TextEditingController _payloadCtrl;
  late final DeviceKind _kind;
  late String _scheme;
  late String _method;

  // Only set for sensors that poll
  int? _pollSeconds;

  @override
  void initState() {
    super.initState();
    // While editing the fields start with the stored values, while creating
    // with the defaults of the picked template.
    final device = widget.device;
    final template = widget.template;
    _kind = device?.kind ?? template?.kind ?? DeviceKind.custom;
    _nameCtrl = TextEditingController(text: device?.name ?? '');
    _hostCtrl = TextEditingController(text: device?.host ?? '');
    _pathCtrl = TextEditingController(text: device?.path ?? '/');
    _payloadCtrl = TextEditingController(text: device?.payload ?? _kind.initialPayload);
    _scheme = device?.scheme ?? template?.scheme ?? 'coap';
    _method = device?.method ?? _kind.fixedMethod ?? 'GET';
    _pollSeconds = device?.pollSeconds ?? _kind.defaultPollSeconds;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _pathCtrl.dispose();
    _payloadCtrl.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _nameCtrl.text.trim().isNotEmpty && _hostCtrl.text.trim().isNotEmpty;

  Future<void> _save() async {
    final device = widget.device;
    final values = DevicesCompanion(
      roomId: Value(widget.room.id),
      kind: Value(_kind),
      name: Value(_nameCtrl.text.trim()),
      host: Value(_hostCtrl.text.trim()),
      scheme: Value(_scheme),
      path: Value(normalizePath(_pathCtrl.text)),
      method: Value(_method),
      payload: Value(_payloadCtrl.text),
      pollSeconds: Value(_pollSeconds),
    );

    if (device == null) {
      await database.into(database.devices).insert(values);
    } else {
      await (database.update(database.devices)
            ..where((t) => t.id.equals(device.id)))
          .write(values);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.device != null;
    final fixedMethod = _kind.fixedMethod;
    final what = _kind.label ?? '$_scheme resource';

    return _SheetBody(
      title: isEditing ? 'Edit $what' : 'New $what',
      subtitle: 'in ${widget.room.name}',
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: _fieldDecoration('NAME', hint: 'Desk sensor'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        const Text('Transport', style: TextStyle(fontSize: 13, color: _subtitleColor)),
        const SizedBox(height: 8),
        _ChoiceRow(
          options: const ['coap', 'http'],
          selected: _scheme,
          labelBuilder: (option) => '$option://',
          onSelected: (option) => setState(() => _scheme = option),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hostCtrl,
                decoration: _fieldDecoration('HOST', hint: '192.168.1.5'),
                onChanged: (_) => setState(() {}), // updates the URI preview
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _pathCtrl,
                decoration: _fieldDecoration('PATH', hint: '/actuator'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Presets send a fixed method: sensors request it in an interval, the
        // others with a payload built by their controls
        if (_pollSeconds != null) ...[
          const Text('Polling interval', style: TextStyle(fontSize: 13, color: _subtitleColor)),
          const SizedBox(height: 8),
          PollIntervalPicker(
            seconds: _pollSeconds!,
            onChanged: (seconds) => setState(() => _pollSeconds = seconds),
          ),
        ] else if (fixedMethod != null)
          _PayloadPreview(method: fixedMethod, payload: _payloadCtrl.text)
        else ...[
          const Text('Method', style: TextStyle(fontSize: 13, color: _subtitleColor)),
          const SizedBox(height: 8),
          _ChoiceRow(
            options: requestMethods,
            selected: _method,
            onSelected: (option) => setState(() => _method = option),
          ),
          // Only POST/PUT/DELETE carry a body, so the field appears just for those.
          if (methodHasPayload(_method)) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _payloadCtrl,
              maxLines: 3,
              decoration: _fieldDecoration('PAYLOAD', hint: '{"on": true}'),
            ),
          ],
        ],
        const SizedBox(height: 16),
        _UriPreview(
          scheme: _scheme,
          host: _hostCtrl.text,
          path: _pathCtrl.text,
        ),
        const SizedBox(height: 20),
        _SaveButton(
          enabled: _isValid,
          label: !_isValid
              ? 'Name it and set a host'
              : isEditing
                  ? 'Save changes'
                  : 'Save resource',
          onPressed: _save,
        ),
      ],
    );
  }
}

// Shared frame for both sheets: title, subtitle and the form below it.
class _SheetBody extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _SheetBody({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // The bottom inset keeps the form above the on-screen keyboard.
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: _subtitleColor)),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

// Row of buttons where exactly one option is selected.
class _ChoiceRow extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final String Function(String option)? labelBuilder;

  const _ChoiceRow({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.labelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _button(context, options[i])),
        ],
      ],
    );
  }

  Widget _button(BuildContext context, String option) {
    final isSelected = option == selected;

    return InkWell(
      onTap: () => onSelected(option),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : _fieldColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          labelBuilder?.call(option) ?? option,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

class _IconPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;

  const _IconPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 6,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (var i = 0; i < roomIcons.length; i++)
          InkWell(
            onTap: () => onSelected(i),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: i == selected ? Theme.of(context).colorScheme.primary : _fieldColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                roomIcons[i],
                size: 20,
                color: i == selected ? Colors.white : Colors.black87,
              ),
            ),
          ),
      ],
    );
  }
}

// Shows the URI that will be sent, assembled from the fields above
class _UriPreview extends StatelessWidget {
  final String scheme;
  final String host;
  final String path;

  const _UriPreview({required this.scheme, required this.host, required this.path});

  @override
  Widget build(BuildContext context) {
    final text = host.trim().isEmpty
        ? 'Enter a host to see the full URI'
        : buildUri(scheme, host, path).toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, size: 16, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// Read-only request body of a preset, it changes later through the device page
class _PayloadPreview extends StatelessWidget {
  final String method;
  final String payload;

  const _PayloadPreview({required this.method, required this.payload});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$method - payload is filled in by the controls',
            style: const TextStyle(fontSize: 13, color: _subtitleColor),
          ),
          const SizedBox(height: 6),
          Text(
            payload,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  const _SaveButton({
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        // Stays disabled until the required fields are filled in
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label),
      ),
    );
  }
}

InputDecoration _fieldDecoration(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: _fieldColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
