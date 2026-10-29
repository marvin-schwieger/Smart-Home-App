import 'package:database_test/auth/coap_security.dart';
import 'package:database_test/auth/oscore.dart';
import 'package:database_test/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// A sequence number used twice with the same key repeats the nonce, so
// neither parallel requests, nor a restart, nor two devices sharing keys may
// get one again

OscoreContext _context(List<int> senderId) => OscoreContext.derive(
      masterSecret: 'secret'.codeUnits,
      senderId: senderId,
      recipientId: const [9],
    );

Future<int> _stored(OscoreContext context) async =>
    (await (database.select(database.oscoreSequences)
              ..where((t) => t.context.equals(oscoreContextId(context))))
            .getSingle())
        .reserved;

void main() {
  final context = _context(const [1]);

  setUp(() {
    forgetOscoreSequences();
    database = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => database.close());

  test('parallel requests get different numbers, reserved in the database', () async {
    final numbers = await Future.wait([for (var i = 0; i < 100; i++) takeOscoreSequence(context)]);

    expect(numbers.toSet().length, 100);
    expect(numbers.first, 0);
    expect(await _stored(context), greaterThan(numbers.reduce((a, b) => a > b ? a : b)));
  });

  test('after a restart the numbers continue behind the reservation', () async {
    final before = [for (var i = 0; i < 5; i++) await takeOscoreSequence(context)];
    final reserved = await _stored(context);

    forgetOscoreSequences();
    final after = await takeOscoreSequence(context);

    expect(after, reserved);
    expect(after, greaterThan(before.last));
  });

  test('equal settings share the numbers, other sender IDs count on their own', () async {
    final sameKeys = _context(const [1]);
    final otherSender = _context(const [2]);

    expect(await takeOscoreSequence(context), 0);
    expect(await takeOscoreSequence(sameKeys), 1);
    expect(await takeOscoreSequence(otherSender), 0);
  });
}
