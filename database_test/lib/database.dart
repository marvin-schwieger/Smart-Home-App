import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';


late AppDatabase database;

class Rooms extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get iconIndex => integer().withDefault(const Constant(0))();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

// What a device does: a sensor is read in an interval, an actuator receives
// commands. Decides which widgets can be added to it (see widgets/catalog.dart)
enum DeviceRole { sensor, actuator }

// Everything that can be added to a device page. Stored by name, so existing
// values must not be renamed
enum WidgetKind {
  // Sensors
  value,
  chart,
  gauge,
  pollRate,
  // Actuators
  toggle,
  slider,
  color,
  button,
  // Both
  response,
}

class Devices extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get roomId => integer()();
  TextColumn get role => textEnum<DeviceRole>()();
  TextColumn get name => text()();
  TextColumn get scheme => text().withDefault(const Constant('coap'))();
  TextColumn get host => text()();
  TextColumn get path => text().withDefault(const Constant('/'))();
  TextColumn get method => text().withDefault(const Constant('GET'))();

  // Sent with every request. The widgets of an actuator change their field
  // in it, so it also holds the last state, e.g. {"on": true}
  TextColumn get payload => text().withDefault(const Constant(''))();

  // Seconds between two requests of a sensor, null for actuators
  IntColumn get pollSeconds => integer().nullable()();

  // Method and settings as JSON, e.g. {"method": "basic", "username": "admin"},
  // see auth/device_auth.dart. Holds the secrets in plain text
  TextColumn get auth => text().withDefault(const Constant('{}'))();
}

// OSCORE sequence numbers below [reserved] may have been used already, per
// security context and not per device, as several devices can share one.
// Only ever counts up, see auth/coap_security.dart
class OscoreSequences extends Table {
  // Hash of what decides the nonces: Sender Key, Common IV and Sender ID
  TextColumn get context => text()();
  IntColumn get reserved => integer()();

  @override
  Set<Column> get primaryKey => {context};
}

// One widget on a device page, e.g. the chart of a sensor or a slider of an
// actuator
class DeviceWidgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get deviceId => integer()();
  TextColumn get kind => textEnum<WidgetKind>()();
  IntColumn get position => integer().withDefault(const Constant(0))();

  // Settings as JSON, e.g. {"label": "Temperature", "field": "temp", "unit": "°C"}
  TextColumn get config => text().withDefault(const Constant('{}'))();
}

// Accounts of the app, created and signed in from the menu. They only exist
// on this device. The password is kept as salted PBKDF2 hash, never in plain
// text, see account/accounts.dart
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  // Lower case, used to sign in
  TextColumn get email => text().unique()();

  // Base64 of the PBKDF2 hash and of its random salt
  TextColumn get passwordHash => text()();
  TextColumn get salt => text()();

  // Stored per account, so it can be raised later without locking anyone out
  IntColumn get iterations => integer()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// Settings of the app by name, e.g. the dark mode or the design, see
// settings/app_settings.dart
class Settings extends Table {
  TextColumn get name => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {name};
}

@DriftDatabase(tables: [Rooms, Devices, DeviceWidgets, OscoreSequences, Accounts, Settings])
class AppDatabase extends _$AppDatabase {
  // Tests pass an in-memory database, the app uses the file
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // v2 added the device kind, existing devices became custom resources.
          // The column is gone since v4, so it is added as plain SQL
          if (from < 2) {
            await customStatement(
              "ALTER TABLE devices ADD COLUMN kind TEXT NOT NULL DEFAULT 'custom'",
            );
          }
          // v3 added the polling interval of sensors
          if (from < 3) await m.addColumn(devices, devices.pollSeconds);
          // v5 added the authentication. Before the v4 step, which copies the
          // devices table with all its current columns
          if (from < 5) {
            await m.addColumn(devices, devices.auth);
            await m.createTable(oscoreSequences);
          }
          // v4 replaced the fixed kinds with a role and freely added widgets
          if (from < 4) await _migrateToWidgets(m);
          // v6 added the accounts and the settings of the menu
          if (from < 6) {
            await m.createTable(accounts);
            await m.createTable(settings);
          }
        },
      );

  // Lamps and temperature sensors get the widgets their fixed pages showed, a
  // custom resource a send button and the response like in the room list.
  // Plain SQL on purpose, so it doesn't change along with the presets
  Future<void> _migrateToWidgets(Migrator m) async {
    await m.createTable(deviceWidgets);

    const widgetsByKind = {
      'temperature': [
        ('value', '{"label":"Temperature","field":"","unit":"°C","decimals":1}'),
        ('chart', '{"label":"History","field":"","unit":"°C"}'),
        ('pollRate', '{}'),
        ('response', '{}'),
      ],
      'lamp': [
        ('toggle', '{"label":"Power","field":"on"}'),
        ('slider', '{"label":"Brightness","field":"brightness","min":0,"max":100,"step":1,"unit":"%"}'),
        ('color', '{"label":"Colour","field":"color"}'),
        ('response', '{}'),
      ],
      'custom': [
        ('button', '{"label":"Send","payload":""}'),
        ('response', '{}'),
      ],
    };
    for (final MapEntry(key: deviceKind, value: widgets) in widgetsByKind.entries) {
      for (final (position, (kind, config)) in widgets.indexed) {
        await customStatement(
          'INSERT INTO device_widgets (device_id, kind, position, config) '
          'SELECT id, ?, ?, ? FROM devices WHERE kind = ?',
          [kind, position, config, deviceKind],
        );
      }
    }

    // Recreates the table without the kind column: temperature sensors become
    // sensors, lamps and custom resources actuators
    await m.alterTable(
      TableMigration(
        devices,
        newColumns: [devices.role],
        columnTransformer: {
          devices.role: const CustomExpression<String>(
            "CASE kind WHEN 'temperature' THEN 'sensor' ELSE 'actuator' END",
          ),
        },
      ),
    );
  }

  // Widgets of one device in the order of its page
  Future<List<DeviceWidget>> widgetsOf(int deviceId) => (select(deviceWidgets)
        ..where((t) => t.deviceId.equals(deviceId))
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .get();

  // Adds a widget at the end of the device page
  Future<void> addWidget(int deviceId, WidgetKind kind, String config) async {
    final last = deviceWidgets.position.max();
    final row = await (selectOnly(deviceWidgets)
          ..addColumns([last])
          ..where(deviceWidgets.deviceId.equals(deviceId)))
        .getSingle();
    await into(deviceWidgets).insert(
      DeviceWidgetsCompanion.insert(
        deviceId: deviceId,
        kind: kind,
        position: Value((row.read(last) ?? -1) + 1),
        config: Value(config),
      ),
    );
  }

  // Value of a setting, null if it was never set
  Future<String?> setting(String name) async =>
      (await (select(settings)..where((t) => t.name.equals(name))).getSingleOrNull())?.value;

  // Stores [value] under [name], null removes the setting
  Future<void> setSetting(String name, String? value) async {
    if (value == null) {
      await (delete(settings)..where((t) => t.name.equals(name))).go();
    } else {
      await into(settings).insertOnConflictUpdate(SettingsCompanion.insert(name: name, value: value));
    }
  }

  // Removes a device together with its widgets
  Future<void> deleteDevice(int deviceId) => transaction(() async {
        await (delete(deviceWidgets)..where((t) => t.deviceId.equals(deviceId))).go();
        await (delete(devices)..where((t) => t.id.equals(deviceId))).go();
      });
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, 'devices.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
