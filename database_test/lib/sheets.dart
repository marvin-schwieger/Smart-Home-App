import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import 'auth/auth_page.dart';
import 'auth/device_auth.dart';
import 'database.dart';
import 'device_presets.dart';
import 'device_session.dart';
import 'request.dart';
import 'room_icons.dart';
import 'ui.dart';
import 'widgets/sensors/poll_rate.dart';

// Sheet 1: create a room - only a name and an icon are needed.
Future<void> showAddRoomSheet(BuildContext context, {required int position}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // lets the sheet grow when the keyboard opens
    showDragHandle: true,
    builder: (_) => _AddRoomSheet(position: position),
  );
}

// Sheet 2: pick a sensor, an actuator or a preset, then sheet 3 asks for its
// address. Returns the new device, null if the user backed out
Future<Device?> showAddDeviceSheet(BuildContext context, Room room) async {
  final template = await showModalBottomSheet<DeviceTemplate>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DevicePickerSheet(room: room),
  );
  if (template == null || !context.mounted) return null;
  return showDeviceSheet(context, room, template: template);
}

// Sheet 3: create a CoAP/HTTP device inside [room] from [template], or edit
// an existing one when [device] is given. Returns the saved device
Future<Device?> showDeviceSheet(
  BuildContext context,
  Room room, {
  Device? device,
  DeviceTemplate? template,
}) {
  return showModalBottomSheet<Device>(
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

    return SheetBody(
      title: 'Add a room',
      subtitle: 'Name it after the real room - devices get grouped under it.',
      children: [
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          decoration: fieldDecoration('NAME', hint: 'e.g. Living room'),
          onChanged: (_) => setState(() {}), // keeps the save button in sync
        ),
        const SizedBox(height: 16),
        const FieldLabel('Icon'),
        _IconPicker(
          selected: _iconIndex,
          onSelected: (index) => setState(() => _iconIndex = index),
        ),
        const SizedBox(height: 20),
        SaveButton(
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

    return SheetBody(
      title: 'Add a device',
      subtitle: 'To ${room.name}. Pick what it is - you set the address next '
          'and add widgets on its page.',
      children: [
        for (final group in groups) ...[
          GroupLabel(group),
          const SizedBox(height: 8),
          PickerGrid(
            children: [
              for (final template in deviceTemplates)
                if (template.group == group)
                  PickerTile<DeviceTemplate>(
                    value: template,
                    icon: template.icon,
                    label: template.label,
                    subtitle: template.subtitle,
                  ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
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

  // Fixed once the device exists, its widgets depend on it
  late final DeviceRole _role;
  late String _scheme;
  late String _method;
  late int _pollSeconds;
  late DeviceAuth _auth;

  @override
  void initState() {
    super.initState();
    // While editing the fields start with the stored values, while creating
    // with the defaults of the picked template.
    final device = widget.device;
    final template = widget.template;
    _role = device?.role ?? template?.role ?? DeviceRole.actuator;
    _nameCtrl = TextEditingController(text: device?.name ?? '');
    _hostCtrl = TextEditingController(text: device?.host ?? '');
    _pathCtrl = TextEditingController(text: device?.path ?? '/');
    _payloadCtrl = TextEditingController(text: device?.payload ?? template?.payload ?? '');
    _scheme = device?.scheme ?? 'coap';
    _method = device?.method ?? _role.defaultMethod;
    _pollSeconds = device?.pollSeconds ?? DeviceSession.defaultPollSeconds;
    _auth = device == null ? DeviceAuth.none : DeviceAuth.decode(device.auth);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _pathCtrl.dispose();
    _payloadCtrl.dispose();
    super.dispose();
  }

  bool get _hasAddress =>
      _nameCtrl.text.trim().isNotEmpty && _hostCtrl.text.trim().isNotEmpty;

  // What is missing in the authentication, null if it is complete
  String? get _authError => _auth.validate(_scheme);

  bool get _isValid => _hasAddress && _authError == null;

  // coaps:// can't be used without DTLS, so switching there picks it
  void _setScheme(String scheme) => setState(() {
        _scheme = scheme;
        _auth = _auth.forScheme(scheme);
      });

  // The settings are edited on a page of their own, see auth/auth_page.dart
  Future<void> _editAuth() async {
    final auth = await showAuthPage(
      context,
      scheme: _scheme,
      auth: _auth,
      deviceName: _nameCtrl.text,
    );
    if (auth != null && mounted) setState(() => _auth = auth);
  }

  Future<void> _save() async {
    final values = DevicesCompanion(
      roomId: Value(widget.room.id),
      role: Value(_role),
      name: Value(_nameCtrl.text.trim()),
      host: Value(_hostCtrl.text.trim()),
      scheme: Value(_scheme),
      path: Value(normalizePath(_pathCtrl.text)),
      method: Value(_method),
      payload: Value(_payloadCtrl.text),
      pollSeconds: Value(_role == DeviceRole.sensor ? _pollSeconds : null),
      auth: Value(_auth.cleanedFor(_scheme).encode()),
    );

    final existing = widget.device;
    final int id;
    if (existing == null) {
      id = await database.into(database.devices).insert(values);
      for (final (kind, config) in [...?widget.template?.widgets]) {
        await database.addWidget(id, kind, jsonEncode(config));
      }
    } else {
      id = existing.id;
      await (database.update(database.devices)..where((t) => t.id.equals(id))).write(values);
    }

    final saved = await (database.select(database.devices)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    updateDeviceSession(saved); // a sensor polls the new address right away
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.device != null;
    final isSensor = _role == DeviceRole.sensor;

    return SheetBody(
      title: isEditing ? 'Edit ${_role.label}' : 'New ${_role.label}',
      subtitle: isSensor
          ? 'in ${widget.room.name} · requested in an interval'
          : 'in ${widget.room.name} · requested when a widget changes something',
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: fieldDecoration(
            'NAME',
            hint: isSensor ? 'e.g. Temperature sensor' : 'e.g. Desk lamp',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Transport'),
        ChoiceRow(
          options: schemes,
          selected: _scheme,
          labelBuilder: (option) => '$option://',
          onSelected: _setScheme,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hostCtrl,
                decoration: fieldDecoration('HOST', hint: '192.168.1.5'),
                onChanged: (_) => setState(() {}), // updates the URI preview
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _pathCtrl,
                decoration: fieldDecoration(
                  'PATH',
                  hint: isSensor ? '/temperature' : '/actuator',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const FieldLabel('Authentication'),
        _AuthTile(auth: _auth, error: _authError, onTap: _editAuth),
        const SizedBox(height: 16),
        const FieldLabel('Method'),
        ChoiceRow(
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
            decoration: fieldDecoration(
              'PAYLOAD',
              hint: '{"on": true}',
              helper: isSensor
                  ? 'Sent with every request'
                  : 'Switches, sliders and colours change their field in it '
                      'before it is sent',
            ),
          ),
        ],
        if (isSensor) ...[
          const SizedBox(height: 16),
          const FieldLabel('Polling interval'),
          PollIntervalPicker(
            seconds: _pollSeconds,
            onChanged: (seconds) => setState(() => _pollSeconds = seconds),
          ),
        ],
        const SizedBox(height: 16),
        _UriPreview(
          scheme: _scheme,
          host: _hostCtrl.text,
          path: _pathCtrl.text,
        ),
        const SizedBox(height: 20),
        SaveButton(
          enabled: _isValid,
          label: !_hasAddress
              ? 'Name it and set a host'
              : _authError != null
                  ? 'Set up the authentication'
                  : isEditing
                      ? 'Save changes'
                      : 'Save ${_role.label}',
          onPressed: _save,
        ),
      ],
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
            borderRadius: BorderRadius.circular(context.design.fieldRadius),
            child: Container(
              decoration: BoxDecoration(
                color: i == selected ? Theme.of(context).colorScheme.primary : context.design.field,
                borderRadius: BorderRadius.circular(context.design.fieldRadius),
              ),
              child: Icon(
                roomIcons[i],
                size: context.design.iconSize,
                color: i == selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
      ],
    );
  }
}

// Method and the most important setting of the authentication, opens its
// page. Turns red while something is missing, e.g. after switching to coaps://
class _AuthTile extends StatelessWidget {
  final DeviceAuth auth;

  // What is missing, null if the authentication is complete
  final String? error;
  final VoidCallback onTap;

  const _AuthTile({required this.auth, required this.error, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    final radius = BorderRadius.circular(design.fieldRadius);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: design.field, borderRadius: radius),
        child: Row(
          children: [
            Icon(authIcon(auth.method), size: design.iconSize, color: design.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    authType(auth.method).label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    error ?? auth.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: error == null ? design.muted : design.error,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: design.icon),
          ],
        ),
      ),
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
    final design = context.design;
    final text = host.trim().isEmpty
        ? 'Enter a host to see the full URI'
        : buildUri(scheme, host, path).toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: design.field,
        borderRadius: BorderRadius.circular(design.fieldRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 16, color: design.icon),
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
