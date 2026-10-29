import 'dart:convert';
import 'dart:typed_data';

import 'package:database_test/account/accounts.dart';
import 'package:database_test/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    // Few iterations, so the tests stay fast. The number is stored per account
    passwordIterations = 1000;
  });
  tearDown(() {
    passwordIterations = defaultPasswordIterations;
    return database.close();
  });

  test('PBKDF2 matches Python hashlib', () {
    // RFC 7914 11: P = "passwd", S = "salt", c = 1
    expect(
      _hex(pbkdf2('passwd', Uint8List.fromList(utf8.encode('salt')), 1)),
      '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc',
    );
    expect(
      _hex(pbkdf2('Pässwort 🔑', Uint8List(16), 1000)),
      '4157946b74f2fa0d98c8561985c1e1cd2f11b47b6dd9f6d1c27d4b06c4938223',
    );
  });

  test('a new account is signed in and only its hash is stored', () async {
    final session = Session();
    await session.register(name: 'Marvin Test', email: ' Marvin@Example.com ', password: 'secret123');

    final account = session.account!;
    expect((account.name, account.email), ('Marvin Test', 'marvin@example.com'));
    expect((account.firstName, account.initials), ('Marvin', 'MT'));
    expect(account.iterations, 1000);

    final stored = await database.select(database.accounts).getSingle();
    expect(stored.passwordHash, isNot(contains('secret123')));
    expect(base64.decode(stored.passwordHash), hasLength(32));
    expect(base64.decode(stored.salt), hasLength(16));
  });

  test('the same password gets a different hash for every account', () async {
    final session = Session();
    await session.register(name: 'A', email: 'a@example.com', password: 'same password');
    await session.register(name: 'B', email: 'b@example.com', password: 'same password');

    final hashes = [for (final a in await database.select(database.accounts).get()) a.passwordHash];
    expect(hashes.toSet(), hasLength(2));
  });

  test('signing in checks the password and ignores the case of the email', () async {
    final session = Session();
    await session.register(name: 'Marvin', email: 'marvin@example.com', password: 'secret123');
    await session.signOut();
    expect(session.isSignedIn, isFalse);

    // Wrong password and unknown email get the same answer
    for (final (email, password) in [('marvin@example.com', 'wrong pass'), ('nobody@example.com', 'secret123')]) {
      await expectLater(
        session.signIn(email, password),
        throwsA(isA<AccountException>().having((e) => e.message, 'message', 'Wrong email or password')),
      );
    }

    await session.signIn('MARVIN@example.com', 'secret123');
    expect(session.account?.name, 'Marvin');
  });

  test('an email can only have one account', () async {
    final session = Session();
    await session.register(name: 'Marvin', email: 'marvin@example.com', password: 'secret123');

    expect(
      session.register(name: 'Other', email: 'Marvin@example.com', password: 'secret456'),
      throwsA(isA<AccountException>()),
    );
  });

  test('the signed in account is restored after a restart, a signed out one not', () async {
    await Session().register(name: 'Marvin', email: 'marvin@example.com', password: 'secret123');

    final restored = await Session.restore();
    expect(restored.account?.email, 'marvin@example.com');

    await restored.signOut();
    expect((await Session.restore()).isSignedIn, isFalse);
  });

  test('deleting needs the password', () async {
    final session = Session();
    await session.register(name: 'Marvin', email: 'marvin@example.com', password: 'secret123');

    await expectLater(session.deleteAccount('wrong pass'), throwsA(isA<AccountException>()));
    expect(await database.select(database.accounts).get(), hasLength(1));

    await session.deleteAccount('secret123');
    expect(session.isSignedIn, isFalse);
    expect(await database.select(database.accounts).get(), isEmpty);
  });

  test('registration input is checked', () {
    String? check(String name, String email, String password, [String? repeated]) => validateRegistration(
          name: name,
          email: email,
          password: password,
          repeated: repeated ?? password,
        );

    expect(check('', 'a@b.de', 'secret123'), 'Fill in your name');
    expect(check('A', 'not an email', 'secret123'), 'Enter a valid email');
    expect(check('A', 'a@b.de', 'short'), contains('at least 8'));
    expect(check('A', 'a@b.de', 'secret123', 'secret124'), 'The passwords differ');
    expect(check('A', 'a@b.de', 'secret123'), isNull);
  });
}
