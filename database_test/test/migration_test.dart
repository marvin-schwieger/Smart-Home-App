import 'package:database_test/database.dart';
import 'package:database_test/widgets/widget_config.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _roomsTable = 'CREATE TABLE rooms (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    'name TEXT NOT NULL, icon_index INTEGER NOT NULL DEFAULT 0, '
    'position INTEGER NOT NULL DEFAULT 0)';

// Devices as they were in v3, with the fixed kind and the polling interval
const _v3 = [
  _roomsTable,
  "CREATE TABLE devices (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "
      "room_id INTEGER NOT NULL, kind TEXT NOT NULL DEFAULT 'custom', "
      "name TEXT NOT NULL, scheme TEXT NOT NULL DEFAULT 'coap', host TEXT NOT NULL, "
      "path TEXT NOT NULL DEFAULT '/', method TEXT NOT NULL DEFAULT 'GET', "
      "payload TEXT NOT NULL DEFAULT '', poll_seconds INTEGER NULL)",
  "INSERT INTO rooms (name) VALUES ('Office')",
  "INSERT INTO devices (room_id, kind, name, host, path, method, payload, poll_seconds) VALUES "
      "(1, 'temperature', 'Thermo', '10.0.0.2', '/temperature', 'GET', '', 30), "
      "(1, 'lamp', 'Lamp', '10.0.0.3', '/lamp', 'PUT', "
      "'{\"on\":false,\"brightness\":40,\"color\":\"#FF0000\"}', NULL), "
      "(1, 'custom', 'Other', '10.0.0.4', '/x', 'POST', 'hello', NULL)",
  'PRAGMA user_version = 3',
];

// Devices as they were in v4, before the authentication
const _v4 = [
  _roomsTable,
  "CREATE TABLE devices (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "
      "room_id INTEGER NOT NULL, role TEXT NOT NULL, name TEXT NOT NULL, "
      "scheme TEXT NOT NULL DEFAULT 'coap', host TEXT NOT NULL, "
      "path TEXT NOT NULL DEFAULT '/', method TEXT NOT NULL DEFAULT 'GET', "
      "payload TEXT NOT NULL DEFAULT '', poll_seconds INTEGER NULL)",
  'CREATE TABLE device_widgets (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      'device_id INTEGER NOT NULL, kind TEXT NOT NULL, '
      'position INTEGER NOT NULL DEFAULT 0, config TEXT NOT NULL DEFAULT \'{}\')',
  "INSERT INTO rooms (name) VALUES ('Office')",
  "INSERT INTO devices (room_id, role, name, host) VALUES (1, 'sensor', 'Thermo', '10.0.0.2')",
  'PRAGMA user_version = 4',
];

// Devices as they were in v1, before kinds and polling
const _v1 = [
  _roomsTable,
  "CREATE TABLE devices (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "
      "room_id INTEGER NOT NULL, name TEXT NOT NULL, scheme TEXT NOT NULL DEFAULT 'coap', "
      "host TEXT NOT NULL, path TEXT NOT NULL DEFAULT '/', "
      "method TEXT NOT NULL DEFAULT 'GET', payload TEXT NOT NULL DEFAULT '')",
  "INSERT INTO rooms (name) VALUES ('Office')",
  "INSERT INTO devices (room_id, name, host) VALUES (1, 'Old', '10.0.0.5')",
  'PRAGMA user_version = 1',
];

AppDatabase _openWith(List<String> statements) => AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          for (final statement in statements) {
            raw.execute(statement);
          }
        },
      ),
    );

void main() {
  test('v3 presets become sensors and actuators with their widgets', () async {
    final db = _openWith(_v3);
    addTearDown(db.close);

    final devices = await (db.select(db.devices)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    expect(devices.map((d) => d.role), [
      DeviceRole.sensor,
      DeviceRole.actuator,
      DeviceRole.actuator,
    ]);
    expect(devices[0].pollSeconds, 30);
    expect(devices[1].payload, contains('"brightness":40'));
    expect((devices[2].method, devices[2].payload), ('POST', 'hello'));

    Future<List<WidgetKind>> kinds(int id) async => [for (final w in await db.widgetsOf(id)) w.kind];
    expect(await kinds(1), [WidgetKind.value, WidgetKind.chart, WidgetKind.pollRate, WidgetKind.response]);
    expect(await kinds(2), [WidgetKind.toggle, WidgetKind.slider, WidgetKind.color, WidgetKind.response]);
    expect(await kinds(3), [WidgetKind.button, WidgetKind.response]);

    final slider = (await db.widgetsOf(2))[1];
    final config = WidgetConfig.decode(slider.config);
    expect((config.field, config.max, config.unit), ('brightness', 100, '%'));

    final columns = await db.customSelect('PRAGMA table_info(devices)').get();
    expect(columns.map((c) => c.read<String>('name')), isNot(contains('kind')));

    // New widgets go after the migrated ones
    await db.addWidget(1, WidgetKind.gauge, '{}');
    expect((await kinds(1)).last, WidgetKind.gauge);
  });

  test('v4 devices start without authentication', () async {
    final db = _openWith(_v4);
    addTearDown(db.close);

    final device = await db.select(db.devices).getSingle();
    expect((device.name, device.auth), ('Thermo', '{}'));
    expect(await db.select(db.oscoreSequences).get(), isEmpty);
    // v6: accounts and settings of the menu
    expect(await db.select(db.accounts).get(), isEmpty);
    await db.setSetting('themeMode', 'dark');
    expect(await db.setting('themeMode'), 'dark');
  });

  test('v1 devices become actuators with a send button', () async {
    final db = _openWith(_v1);
    addTearDown(db.close);

    final device = await db.select(db.devices).getSingle();
    expect((device.role, device.pollSeconds), (DeviceRole.actuator, null));
    expect([for (final w in await db.widgetsOf(device.id)) w.kind], [
      WidgetKind.button,
      WidgetKind.response,
    ]);
  });
}
