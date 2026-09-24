import 'dart:convert';

import 'package:database_test/database.dart';
import 'package:database_test/device_page.dart';
import 'package:database_test/device_session.dart';
import 'package:database_test/room_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Devices use http:// here: in widget tests every HTTP request is answered
// with 400 and an empty body, so nothing goes over the network

late Room _room;

Future<Device> _addDevice(
  DeviceRole role, {
  String payload = '',
  int? pollSeconds,
  List<(WidgetKind, String)> widgets = const [],
}) async {
  final id = await database.into(database.devices).insert(
        DevicesCompanion.insert(
          roomId: _room.id,
          role: role,
          name: role == DeviceRole.sensor ? 'Thermo' : 'Lamp',
          host: '127.0.0.1',
          scheme: const Value('http'),
          method: Value(role == DeviceRole.sensor ? 'GET' : 'PUT'),
          payload: Value(payload),
          pollSeconds: Value(pollSeconds),
        ),
      );
  for (final (kind, config) in widgets) {
    await database.addWidget(id, kind, config);
  }
  return _stored(id);
}

Future<Device> _stored(int id) =>
    (database.select(database.devices)..where((t) => t.id.equals(id))).getSingle();

// The mocked HTTP client answers in real time, while widget tests run on fake
// time, so this lets real time pass until [text] shows up
Future<void> _waitForText(WidgetTester tester, String text) async {
  for (var i = 0; i < 100 && find.textContaining(text).evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

// Sessions outlive the pages, their polling timers must not outlive the test
Future<void> _closeSessions(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (var id = 1; id <= 10; id++) {
    closeDeviceSession(id);
  }
}

void main() {
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final id = await database.into(database.rooms).insert(RoomsCompanion.insert(name: 'Office'));
    _room = await (database.select(database.rooms)..where((t) => t.id.equals(id))).getSingle();
  });

  tearDown(() => database.close());

  // Tall enough that every widget card is on screen
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('actuator widgets change fields of the payload and send it', (tester) async {
    useTallScreen(tester);
    final lamp = await _addDevice(
      DeviceRole.actuator,
      payload: '{"on":true,"brightness":100,"color":"#FFFFFF"}',
      widgets: [
        (WidgetKind.toggle, '{"label":"Power","field":"on"}'),
        (
          WidgetKind.slider,
          '{"label":"Brightness","field":"brightness","min":0,"max":100,"step":1,"unit":"%"}',
        ),
        (WidgetKind.color, '{"label":"Colour","field":"color"}'),
        (WidgetKind.response, '{}'),
      ],
    );

    await tester.pumpWidget(MaterialApp(home: DevicePage(device: lamp, room: _room)));
    await tester.pumpAndSettle();

    expect(find.text('Power'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Brightness'), findsOneWidget);
    expect(find.text('100 %'), findsNWidgets(2)); // value and max label
    expect(find.text('#FFFFFF'), findsOneWidget);
    expect(find.text('Nothing sent yet - use a control above'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsOneWidget);
    await _waitForText(tester, 'Code 400');
    expect(find.textContaining('Code 400 · '), findsOneWidget);
    expect(jsonDecode((await _stored(lamp.id)).payload), {
      'on': false,
      'brightness': 100,
      'color': '#FFFFFF',
    });

    // Dragging to the far left sets 0, sent as a whole number
    await tester.drag(find.byType(Slider), const Offset(-800, 0));
    await tester.pumpAndSettle();
    expect(find.text('0 %'), findsNWidgets(2)); // value and min label
    expect(jsonDecode((await _stored(lamp.id)).payload)['brightness'], 0);

    await _closeSessions(tester);
  });

  testWidgets('sensor widgets show the polled values', (tester) async {
    useTallScreen(tester);
    final sensor = await _addDevice(
      DeviceRole.sensor,
      pollSeconds: 5,
      widgets: [
        (WidgetKind.value, '{"label":"Temperature","field":"temp","unit":"°C","decimals":1}'),
        (WidgetKind.chart, '{"label":"History","field":"temp","unit":"°C"}'),
        (
          WidgetKind.gauge,
          '{"label":"Level","field":"temp","unit":"°C","decimals":0,"min":0,"max":40}',
        ),
        (WidgetKind.pollRate, '{}'),
        (WidgetKind.response, '{}'),
      ],
    );

    await tester.pumpWidget(MaterialApp(home: DevicePage(device: sensor, room: _room)));
    await tester.pumpAndSettle();

    // First poll gets the empty 400 response
    await _waitForText(tester, 'in the response');
    expect(find.text('no "temp" in the response'), findsOneWidget);
    expect(find.text('The graph starts after two readings'), findsOneWidget);

    final session = deviceSession(sensor);
    final now = DateTime.now();
    session.samples.addAll([
      Sample(now.subtract(const Duration(seconds: 10)), {'temp': 20.0}),
      Sample(now, {'temp': 22.0}),
    ]);
    session.update(session.device); // lets the widgets rebuild
    await tester.pump();

    expect(find.text('22.0 °C'), findsOneWidget);
    expect(find.text('22 °C'), findsOneWidget); // gauge
    expect(find.byType(LineChart), findsOneWidget);

    await tester.tap(find.text('30 s'));
    await tester.pumpAndSettle();
    expect(session.pollSeconds, 30);
    expect((await _stored(sensor.id)).pollSeconds, 30);

    await _closeSessions(tester);
  });

  testWidgets('a new device opens its page, where widgets are added', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(MaterialApp(home: RoomPage(room: _room)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sensor'));
    await tester.pumpAndSettle();

    expect(find.text('New sensor'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'NAME'), 'Desk');
    await tester.enterText(find.widgetWithText(TextField, 'HOST'), '127.0.0.1');
    await tester.tap(find.text('http://'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save sensor'));
    await tester.pumpAndSettle();

    expect(find.text('No widgets yet'), findsOneWidget);
    await tester.tap(find.text('Add widget'));
    await tester.pumpAndSettle();
    // Only widgets for sensors are offered
    expect(find.text('Slider'), findsNothing);
    await tester.tap(find.text('Graph'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add graph'));
    await tester.pumpAndSettle();

    expect(find.text('History'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Desk'), findsOneWidget);
    expect(find.text('--'), findsOneWidget); // badge, the empty response has no number

    await _closeSessions(tester);
  });
}
