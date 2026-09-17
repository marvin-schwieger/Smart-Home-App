import 'package:flutter/material.dart';

import 'database.dart';
import 'device_presets.dart';
import 'request.dart';
import 'room_icons.dart';
import 'sheets.dart';

// Devices of one room: tap sends the request (or opens the controls of a
// preset like the lamp), long press edits the device, the bin icon deletes it
class RoomPage extends StatefulWidget {
  final Room room;

  const RoomPage({super.key, required this.room});

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  List<Device> _devices = [];

  // Last response per device id - kept in memory only maybe store??!!
  final Map<int, String> _responses = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final devices = await (database.select(database.devices)
          ..where((t) => t.roomId.equals(widget.room.id)))
        .get();
    setState(() => _devices = devices);
  }

  Future<void> _addDevice() async {
    await showAddDeviceSheet(context, widget.room);
    if (mounted) await _load();
  }

  // Page of a preset device, the device is reloaded afterwards because the
  // page may have changed it (lamp state, polling interval)
  Future<void> _openPage(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await _load();
  }

  Future<void> _editDevice(Device device) async {
    await showDeviceSheet(context, widget.room, device: device);
    if (mounted) await _load();
  }

  Future<void> _send(Device device) async {
    setState(() => _responses[device.id] = 'Loading...');
    final response = await sendRequest(device);
    if (mounted) setState(() => _responses[device.id] = response);
  }

  Future<void> _deleteDevice(Device device) async {
    await (database.delete(database.devices)..where((t) => t.id.equals(device.id))).go();
    _responses.remove(device.id);
    stopTemperatureFeed(device.id);
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
      stopTemperatureFeed(device.id);
    }
    await (database.delete(database.devices)
          ..where((t) => t.roomId.equals(widget.room.id)))
        .go();
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
          IconButton(
            onPressed: _deleteRoom,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete room',
          ),
        ],
      ),
      body: _devices.isEmpty
          ? const Center(
              child: Text(
                'No devices yet.\nClick + to add one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (context, i) {
                final device = _devices[i];
                return switch (device.kind) {
                  DeviceKind.lamp => _DeviceCard(
                      device: device,
                      leading: LampIcon(
                        state: LampState.fromPayload(device.payload),
                        size: 20,
                      ),
                      onTap: () => _openPage(LampPage(device: device, room: widget.room)),
                      onEdit: () => _editDevice(device),
                      onDelete: () => _deleteDevice(device),
                    ),
                  // Getting the feed starts polling, which then keeps running
                  // for the whole app session
                  DeviceKind.temperature => _DeviceCard(
                      device: device,
                      leading: const Icon(Icons.thermostat, color: Color(0xFFD9722B)),
                      badge: TemperatureBadge(feed: temperatureFeed(device)),
                      onTap: () =>
                          _openPage(TemperatureSensorPage(device: device, room: widget.room)),
                      onEdit: () => _editDevice(device),
                      onDelete: () => _deleteDevice(device),
                    ),
                  DeviceKind.custom => _DeviceCard(
                      device: device,
                      response: _responses[device.id],
                      onTap: () => _send(device),
                      onEdit: () => _editDevice(device),
                      onDelete: () => _deleteDevice(device),
                    ),
                };
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
  final Widget leading;

  // Shown before the delete button, the request method if not given
  final Widget? badge;
  final String? response;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DeviceCard({
    required this.device,
    this.leading = const Icon(Icons.sensors),
    this.badge,
    this.response,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: leading,
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
                        color: const Color(0xFFEDE9E3),
                        borderRadius: BorderRadius.circular(8),
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
          // Response of the last request, shown under the device.
          if (response != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  response!,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
