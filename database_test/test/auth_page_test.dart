import 'package:database_test/auth/device_auth.dart';
import 'package:database_test/database.dart';
import 'package:database_test/device_presets.dart';
import 'package:database_test/sheets.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The device sheet only shows the authentication in one line, it is set up
// on a page of its own. Phone-sized screen, so everything has to fit

late Room _room;

Future<void> _openSheet(WidgetTester tester, {Device? device}) async {
  tester.view.physicalSize = const Size(360, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => device == null
                ? showDeviceSheet(context, _room, template: deviceTemplates.first)
                : showDeviceSheet(context, _room, device: device),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

// Text of the save button of the sheet, or of the apply button of the page
String _buttonLabel(WidgetTester tester) =>
    (tester.widget<FilledButton>(find.byType(FilledButton)).child! as Text).data!;

void main() {
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final id = await database.into(database.rooms).insert(RoomsCompanion.insert(name: 'Office'));
    _room = await (database.select(database.rooms)..where((t) => t.id.equals(id))).getSingle();
  });
  tearDown(() => database.close());

  testWidgets('the page offers the methods of the transport, the sheet saves them', (tester) async {
    await _openSheet(tester);
    await _enter(tester, 'NAME', 'Thermo');
    await _enter(tester, 'HOST', '172.30.13.2');
    expect(find.text('No credentials are sent'), findsOneWidget);

    // coaps:// can't do without DTLS, which still needs its settings
    await _tap(tester, find.text('coaps://'));
    expect(find.text('Fill in identity'), findsOneWidget);
    expect(_buttonLabel(tester), 'Set up the authentication');

    await _tap(tester, find.text('DTLS'));
    expect(find.text('Thermo · coaps://'), findsOneWidget);
    expect(find.text('None'), findsNothing);
    await _enter(tester, 'IDENTITY', 'app');
    await _enter(tester, 'PRE-SHARED KEY', '0x12zz');
    expect(_buttonLabel(tester), 'Pre-shared key: odd or invalid hex');
    await _enter(tester, 'PRE-SHARED KEY', 'secretPSK');
    await _tap(tester, find.text('Apply'));

    expect(find.text('Identity app'), findsOneWidget);
    expect(_buttonLabel(tester), 'Save sensor');

    // https:// has no DTLS, the page then offers the HTTP methods
    await _tap(tester, find.text('https://'));
    await _tap(tester, find.text('None'));
    expect(find.text('OAuth 2.0'), findsOneWidget);
    expect(find.text('CERTIFICATE OF THE DEVICE'), findsOneWidget);
    await _tap(tester, find.text('Basic'));
    await _enter(tester, 'USERNAME', 'admin');
    await _enter(tester, 'PASSWORD', 'secret');
    await _tap(tester, find.text('Apply'));

    expect(find.text('User admin'), findsOneWidget);
    await _tap(tester, find.text('Save sensor'));

    final device = await database.select(database.devices).getSingle();
    final auth = DeviceAuth.decode(device.auth);
    expect(device.scheme, 'https');
    expect(auth.method, AuthMethod.basic);
    // The DTLS key typed before isn't stored
    expect(auth.values, {'username': 'admin', 'password': 'secret'});
  });

  testWidgets('going back from the page keeps the old authentication', (tester) async {
    await _openSheet(tester);
    await _tap(tester, find.text('http://'));
    await _tap(tester, find.text('None'));

    await _tap(tester, find.text('Basic'));
    await _enter(tester, 'USERNAME', 'admin');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('No credentials are sent'), findsOneWidget);
  });

  testWidgets('an existing device opens with its authentication', (tester) async {
    final id = await database.into(database.devices).insert(
          DevicesCompanion.insert(
            roomId: _room.id,
            role: DeviceRole.sensor,
            name: 'Thermo',
            host: '172.30.13.2',
            auth: const Value('{"method":"oscore","masterSecret":"0x0102","recipientId":"0x01"}'),
          ),
        );
    final device = await (database.select(database.devices)..where((t) => t.id.equals(id))).getSingle();
    await _openSheet(tester, device: device);

    expect(find.text('AES-CCM-16-64-128 · recipient ID 0x01, sender ID empty'), findsOneWidget);
    await _tap(tester, find.text('OSCORE'));
    expect(find.text('OSCORE SETTINGS'), findsOneWidget);
    expect(find.text('0x01'), findsOneWidget);
    expect(_buttonLabel(tester), 'Apply');

    // Another algorithm, whose 12 byte nonce leaves room for 6 byte IDs
    await _tap(tester, find.text('AES-CCM-16-64-128'));
    await tester.tap(find.text('A128GCM').last);
    await tester.pumpAndSettle();
    await _enter(tester, 'RECIPIENT ID', '0x01020304050607');
    expect(_buttonLabel(tester), 'Sender and recipient ID can have at most 6 bytes with A128GCM');
    await _enter(tester, 'RECIPIENT ID', '0x01');
    await _tap(tester, find.text('Apply'));

    expect(find.text('A128GCM · recipient ID 0x01, sender ID empty'), findsOneWidget);
  });
}
