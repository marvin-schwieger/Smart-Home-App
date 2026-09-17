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

// What a device is: a preset with its own controls (see device_presets.dart)
// or a plain resource where the user sets method and payload by hand
enum DeviceKind { custom, lamp, temperature }

class Devices extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get roomId => integer()();
  TextColumn get kind =>
      textEnum<DeviceKind>().withDefault(const Constant('custom'))();
  TextColumn get name => text()();
  TextColumn get scheme => text().withDefault(const Constant('coap'))();
  TextColumn get host => text()();
  TextColumn get path => text().withDefault(const Constant('/'))();
  TextColumn get method => text().withDefault(const Constant('GET'))();
  TextColumn get payload => text().withDefault(const Constant(''))();

  // Seconds between two requests of a polling sensor, null for other devices
  IntColumn get pollSeconds => integer().nullable()();
}

@DriftDatabase(tables: [Rooms, Devices])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // v2 added the device kind, existing devices become custom resources
          if (from < 2) await m.addColumn(devices, devices.kind);
          // v3 added the polling interval of sensors
          if (from < 3) await m.addColumn(devices, devices.pollSeconds);
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, 'devices.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
