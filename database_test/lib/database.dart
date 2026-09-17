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

class Devices extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get roomId => integer()();
  TextColumn get name => text()();
  TextColumn get scheme => text().withDefault(const Constant('coap'))();
  TextColumn get host => text()();
  TextColumn get path => text().withDefault(const Constant('/'))();
  TextColumn get method => text().withDefault(const Constant('GET'))();
  TextColumn get payload => text().withDefault(const Constant(''))();
}

@DriftDatabase(tables: [Rooms, Devices])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          for (final table in allTables) {
            await m.deleteTable(table.actualTableName);
          }
          await m.createAll();
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
