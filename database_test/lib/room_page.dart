import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';

import 'database.dart';
import 'device_page.dart';
import 'device_presets.dart';
import 'device_session.dart';
import 'js_test_page.dart';
import 'request.dart';
import 'room_icons.dart';
import 'sheets.dart';
import 'ui.dart';
import 'widgets/sensors/value_display.dart';
import 'widgets/widget_config.dart';

// Devices of one room: tap opens the page with the device's widgets, long
// press edits the device, the bin icon deletes it
class RoomPage extends StatefulWidget {
  final Room room;

  const RoomPage({super.key, required this.room});

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  // Widgets whose field and unit the card of a sensor shows, the first one wins
  static const _badgeKinds = {WidgetKind.value, WidgetKind.gauge, WidgetKind.chart};

  List<Device> _devices = [];
  Map<int, WidgetConfig> _badgeConfigs = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final devices = await (database.select(database.devices)
          ..where((t) => t.roomId.equals(widget.room.id)))
        .get();
    final widgets = await (database.select(database.deviceWidgets)
          ..where((t) => t.deviceId.isIn(devices.map((d) => d.id)))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();

    final badgeConfigs = <int, WidgetConfig>{};
    for (final entry in widgets) {
      if (_badgeKinds.contains(entry.kind)) {
        badgeConfigs.putIfAbsent(entry.deviceId, () => WidgetConfig.decode(entry.config));
      }
    }
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _badgeConfigs = badgeConfigs;
    });
  }

  Future<void> _addDevice() async {
    final device = await showAddDeviceSheet(context, widget.room);
    if (!mounted) return;
    // Straight to its page, so widgets can be added
    device == null ? await _load() : await _openDevice(device);
  }

  // The device is reloaded afterwards because the page may have changed it
  // (widgets, payload, polling interval)
  Future<void> _openDevice(Device device) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DevicePage(device: device, room: widget.room)),
    );
    if (mounted) await _load();
  }

  Future<void> _editDevice(Device device) async {
    await showDeviceSheet(context, widget.room, device: device);
    if (mounted) await _load();
  }

  Future<void> _deleteDevice(Device device) async {
    await database.deleteDevice(device.id);
    closeDeviceSession(device.id);
    await _load();
  }

  Future<void> _deleteRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${widget.room.name}"?'),
        content: const Text('The room and all its devices will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final device in _devices) {
      await database.deleteDevice(device.id);
      closeDeviceSession(device.id);
    }
    await (database.delete(database.rooms)
          ..where((t) => t.id.equals(widget.room.id)))
        .go();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Icon(roomIconAt(widget.room.iconIndex), size: 20),
            const SizedBox(width: 8),
            Text(widget.room.name),
          ],
        ),
        actions: [
          // Only for testing if flutter_js runs
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const JsTestPage()),
            ),
            icon: const Icon(Icons.javascript),
            tooltip: 'flutter_js test',
          ),
          IconButton(
            onPressed: _deleteRoom,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete room',
          ),
        ],
      ),
      body: _devices.isEmpty
          ? Center(
              child: Text(
                'No devices yet.\nClick + to add one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.design.muted),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (context, i) {
                final device = _devices[i];
                return _DeviceCard(
                  device: device,
                  // Getting the session starts polling a sensor, which then
                  // keeps running for the whole app session
                  badge: device.role == DeviceRole.sensor
                      ? SensorBadge(
                          session: deviceSession(device),
                          config: _badgeConfigs[device.id] ?? const WidgetConfig({}),
                        )
                      : null,
                  onTap: () => _openDevice(device),
                  onEdit: () => _editDevice(device),
                  onDelete: () => _deleteDevice(device),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDevice,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Device device;

  // Shown before the delete button, the request method if not given
  final Widget? badge;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DeviceCard({
    required this.device,
    this.badge,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    return Padding(
      padding: EdgeInsets.only(bottom: design.spacing * 0.75),
      child: DesignCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(device.role.icon),
          title: Text(
            device.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            buildUri(device.scheme, device.host, device.path).toString(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              badge ??
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: design.field,
                      borderRadius: BorderRadius.circular(design.badgeRadius),
                    ),
                    child: Text(
                      device.method,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              // Deleting is only possible here, never by long pressing.
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete device',
              ),
            ],
          ),
          onTap: onTap,
          onLongPress: onEdit,
        ),
      ),
    );
  }
}
