import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import 'account/accounts.dart';
import 'database.dart';
import 'design/design_settings.dart';
import 'menu/about_page.dart';
import 'menu/app_drawer.dart';
import 'room_icons.dart';
import 'room_page.dart';
import 'settings/app_settings.dart';
import 'sheets.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  database = AppDatabase();
  appSettings = await AppSettings.load();
  session = await Session.restore();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the dark mode or the design changes in the menu
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
        final design = appSettings.design;
        return MaterialApp(
          title: appName,
          theme: buildTheme(design, Brightness.light),
          darkTheme: buildTheme(design, Brightness.dark),
          themeMode: appSettings.themeMode,
          // The text size of the design on top of the one of the system
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(media.textScaler.scale(1) * design.textScale),
              ),
              child: child!,
            );
          },
          home: const HomePage(),
        );
      },
    );
  }
}

// Landing page: all rooms as a grid -> can be reordered by dragging
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Room> _rooms = [];

  // Number of devices per room id, shown on the room card
  Map<int, int> _deviceCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rooms = await (database.select(database.rooms)
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    final devices = await database.select(database.devices).get();

    final counts = <int, int>{};
    for (final device in devices) {
      counts[device.roomId] = (counts[device.roomId] ?? 0) + 1;
    }

    setState(() {
      _rooms = rooms;
      _deviceCounts = counts;
    });
  }

  Future<void> _addRoom() async {
    await showAddRoomSheet(context, position: _rooms.length);
    if (mounted) await _load();
  }

  Future<void> _openRoom(Room room) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomPage(room: room)),
    );
    if (mounted) await _load(); // device count may have changed
  }

  // Saves the new order after a drag so it survives a restart
  Future<void> _reorder(int oldIndex, int newIndex) async {
    final reordered = List.of(_rooms);
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    setState(() => _rooms = reordered);

    await database.batch((batch) {
      for (var i = 0; i < reordered.length; i++) {
        batch.update(
          database.rooms,
          RoomsCompanion(position: Value(i)),
          where: (t) => t.id.equals(reordered[i].id),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    return Scaffold(
      // The hamburger button in the app bar opens it
      appBar: AppBar(backgroundColor: Colors.transparent),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(design.padding + 4, 0, design.padding + 4, design.padding + 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListenableBuilder(
                listenable: session,
                builder: (context, _) => Text(
                  switch (session.account) {
                    final account? => 'Hello, ${account.firstName}',
                    null => 'Hello',
                  },
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(height: design.spacing),
              Expanded(
                child: _rooms.isEmpty
                    ? _EmptyHome(onAddRoom: _addRoom)
                    : _roomGrid(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roomGrid() {
    final gap = context.design.spacing * 0.75;
    return ReorderableGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      childAspectRatio: 1.15,
      onReorder: _reorder,
      // The "Add room" tile sits in the grid but must not be draggable,
      // which is what the footer slot is for
      footer: [
        _DashedTile(
          key: const ValueKey('add-room'),
          icon: Icons.add,
          label: 'Add room',
          onTap: _addRoom,
        ),
      ],
      children: [
        for (final room in _rooms)
          _RoomCard(
            key: ValueKey(room.id),
            room: room,
            deviceCount: _deviceCounts[room.id] ?? 0,
            onTap: () => _openRoom(room),
          ),
      ],
    );
  }
}

// Shown while no room exists yet
class _EmptyHome extends StatelessWidget {
  final VoidCallback onAddRoom;

  const _EmptyHome({required this.onAddRoom});

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 130,
          width: double.infinity,
          child: CustomPaint(
            painter: _DashedBorderPainter(color: design.faint, radius: design.cardRadius),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.home_outlined, size: 32, color: design.muted),
                  const SizedBox(height: 8),
                  Text('no rooms yet', style: TextStyle(color: design.muted)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Start with a room',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Rooms are just containers - name one after a real room, then add '
          'the sensors, lamps and endpoints that live there.',
          style: TextStyle(color: design.muted, height: 1.4),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: design.buttonHeight,
          child: FilledButton.icon(
            onPressed: onAddRoom,
            icon: const Icon(Icons.add),
            label: const Text('Add your first room'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(design.buttonRadius)),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomCard extends StatelessWidget {
  final Room room;
  final int deviceCount;
  final VoidCallback onTap;

  const _RoomCard({
    super.key,
    required this.room,
    required this.deviceCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    return DesignCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconBox(roomIconAt(room.iconIndex), accent: true),
              Text(
                '$deviceCount device${deviceCount == 1 ? '' : 's'}',
                style: TextStyle(color: design.muted, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          Text(
            room.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// Grid tile with a dashed outline, used for "Add room".
class _DashedTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DashedTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    return InkWell(
      borderRadius: BorderRadius.circular(design.cardRadius),
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: design.faint, radius: design.cardRadius),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: design.muted),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(color: design.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws the dashed rounded rectangle used by the empty state and the add tile.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );

    // Walk along the outline and draw only short pieces of it.
    final dashes = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + 6;
        dashes.addPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          Offset.zero,
        );
        distance = next + 4;
      }
    }

    canvas.drawPath(
      dashes,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
