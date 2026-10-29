import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import 'database.dart';
import 'device_presets.dart';
import 'device_session.dart';
import 'sheets.dart';
import 'ui.dart';
import 'widgets/catalog.dart';
import 'widgets/widget_config.dart';
import 'widgets/widget_sheets.dart';

// Page of one device: the widgets the user added to it, in their own order.
// Which widgets can be added depends on the role (see widgets/catalog.dart);
// all of them share the session of the device
class DevicePage extends StatefulWidget {
  final Device device;
  final Room room;

  const DevicePage({super.key, required this.device, required this.room});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late final DeviceSession _session = deviceSession(widget.device);
  List<DeviceWidget> _widgets = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final widgets = await database.widgetsOf(widget.device.id);
    if (!mounted) return;
    setState(() {
      _widgets = widgets;
      _loaded = true;
    });
  }

  Future<void> _addWidget() async {
    if (await showAddWidgetSheet(context, _session)) await _load();
  }

  Future<void> _editWidget(DeviceWidget entry) async {
    if (await showWidgetConfigSheet(context, _session, entry: entry)) await _load();
  }

  Future<void> _removeWidget(DeviceWidget entry) async {
    await (database.delete(database.deviceWidgets)..where((t) => t.id.equals(entry.id))).go();
    await _load();
  }

  // The sheet hands the changes to the session, which rebuilds the page
  Future<void> _editDevice() => showDeviceSheet(context, widget.room, device: _session.device);

  // Saves the new order after a drag so it survives a restart
  Future<void> _reorder(int oldIndex, int newIndex) async {
    final reordered = List.of(_widgets);
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    setState(() => _widgets = reordered);

    await database.batch((batch) {
      for (var i = 0; i < reordered.length; i++) {
        batch.update(
          database.deviceWidgets,
          DeviceWidgetsCompanion(position: Value(i)),
          where: (t) => t.id.equals(reordered[i].id),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final device = _session.device;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name),
                Text(
                  '${_capitalized(device.role.label)} · ${widget.room.name}',
                  style: TextStyle(fontSize: 12, color: context.design.muted),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: _editDevice,
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit device',
              ),
            ],
          ),
          body: !_loaded
              ? const SizedBox.shrink()
              : _widgets.isEmpty
                  ? _EmptyDevice(role: device.role, onAdd: _addWidget)
                  : ReorderableListView.builder(
                      padding: EdgeInsets.all(context.design.padding),
                      // Dragged by the handle in the card header only, the
                      // charts and sliders need their own gestures
                      buildDefaultDragHandles: false,
                      itemCount: _widgets.length,
                      onReorderItem: _reorder,
                      itemBuilder: (context, i) {
                        final entry = _widgets[i];
                        return _WidgetCard(
                          key: ValueKey(entry.id),
                          index: i,
                          entry: entry,
                          session: _session,
                          onEdit: () => _editWidget(entry),
                          onRemove: () => _removeWidget(entry),
                        );
                      },
                      footer: _AddWidgetButton(onPressed: _addWidget),
                    ),
        );
      },
    );
  }
}

String _capitalized(String text) => '${text[0].toUpperCase()}${text.substring(1)}';

// Card around one widget: a header with drag handle, name and menu, the
// widget itself below
class _WidgetCard extends StatelessWidget {
  final int index;
  final DeviceWidget entry;
  final DeviceSession session;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _WidgetCard({
    super.key,
    required this.index,
    required this.entry,
    required this.session,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final type = widgetType(entry.kind);
    final config = WidgetConfig.decode(entry.config);
    final design = context.design;

    return Padding(
      padding: EdgeInsets.only(bottom: design.spacing * 0.75),
      child: DesignCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                    child: Icon(Icons.drag_indicator, size: 20, color: design.faint),
                  ),
                ),
                Expanded(
                  child: Text(
                    type.title(config),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: design.muted),
                  ),
                ),
                PopupMenuButton<VoidCallback>(
                  icon: Icon(Icons.more_horiz, color: design.icon),
                  tooltip: 'Widget options',
                  onSelected: (action) => action(),
                  itemBuilder: (_) => [
                    if (type.fields.isNotEmpty)
                      PopupMenuItem(value: onEdit, child: const Text('Edit')),
                    PopupMenuItem(value: onRemove, child: const Text('Remove')),
                  ],
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(design.padding, 0, design.padding, design.padding),
              child: type.build(session, config),
            ),
          ],
        ),
      ),
    );
  }
}

// Shown while the device has no widgets yet
class _EmptyDevice extends StatelessWidget {
  final DeviceRole role;
  final VoidCallback onAdd;

  const _EmptyDevice({required this.role, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    final examples = widgetTypes
        .where((t) => t.roles.contains(role))
        .map((t) => t.label.toLowerCase())
        .join(', ');

    return ListView(
      padding: EdgeInsets.all(design.padding),
      children: [
        const SizedBox(height: 40),
        Icon(role.icon, size: 40, color: design.muted),
        const SizedBox(height: 12),
        const Text(
          'No widgets yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Put together what this ${role.label} shows: $examples.',
          textAlign: TextAlign.center,
          style: TextStyle(color: design.muted, height: 1.4),
        ),
        const SizedBox(height: 24),
        _AddWidgetButton(onPressed: onAdd),
      ],
    );
  }
}

class _AddWidgetButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddWidgetButton({required this.onPressed});

  @override
  Widget build(BuildContext context) =>
      WideOutlinedButton(icon: Icons.add, label: 'Add widget', onPressed: onPressed);
}
