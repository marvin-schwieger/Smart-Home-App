import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../database.dart';

// Accounts of the app. They only exist on this device - there is no server,
// signing in decides whose account the menu shows. The password is never
// stored, only a PBKDF2-HMAC-SHA-256 hash of it with a random salt
// (RFC 8018), so even someone with the database can't read it

late Session session;

class AccountException implements Exception {
  final String message;

  const AccountException(this.message);

  @override
  String toString() => message;
}

const int minPasswordLength = 8;

// Iterations of PBKDF2 for new accounts. OWASP recommended 310 000 for
// HMAC-SHA-256 until 2023, now 600 000 - which takes about two seconds on a
// phone in debug mode. Each account keeps the number it was created with, so
// it can be raised without locking anyone out
const int defaultPasswordIterations = 310000;

@visibleForTesting
int passwordIterations = defaultPasswordIterations;

// Hashing runs in a background isolate, so the iterations don't block the
// UI. Widget tests turn it off, their fake clock doesn't wait for isolates
@visibleForTesting
bool hashInBackground = true;

const int _saltLength = 16;
const int _hashLength = 32;

// PBKDF2 with HMAC-SHA-256
Uint8List pbkdf2(String password, Uint8List salt, int iterations) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, _hashLength));
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}

Future<Uint8List> _hash(String password, Uint8List salt, int iterations) => hashInBackground
    ? Isolate.run(() => pbkdf2(password, salt, iterations))
    : Future.value(pbkdf2(password, salt, iterations));

// What is missing or wrong for a new account, null if it can be created
String? validateRegistration({
  required String name,
  required String email,
  required String password,
  required String repeated,
}) {
  if (name.trim().isEmpty) return 'Fill in your name';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) return 'Enter a valid email';
  if (password.length < minPasswordLength) {
    return 'The password needs at least $minPasswordLength characters';
  }
  if (password != repeated) return 'The passwords differ';
  return null;
}

// The account that is signed in. The menu and the home page listen to it
class Session extends ChangeNotifier {
  static const _setting = 'account';

  Account? _account;

  Account? get account => _account;

  bool get isSignedIn => _account != null;

  // Signed in again with the account that was signed in when the app closed
  static Future<Session> restore() async {
    final session = Session();
    final id = int.tryParse(await database.setting(_setting) ?? '');
    if (id != null) session._account = await _byId(id);
    return session;
  }

  // Creates the account and signs it in. Throws an AccountException if the
  // input isn't valid or the email is taken
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final error = validateRegistration(name: name, email: email, password: password, repeated: password);
    if (error != null) throw AccountException(error);
    if (await _byEmail(email) != null) {
      throw const AccountException('There is already an account with this email');
    }

    final salt = _randomBytes(_saltLength);
    final hash = await _hash(password, salt, passwordIterations);
    final id = await database.into(database.accounts).insert(
          AccountsCompanion.insert(
            name: name.trim(),
            email: _normalized(email),
            passwordHash: base64.encode(hash),
            salt: base64.encode(salt),
            iterations: passwordIterations,
          ),
        );
    await _signInAs(await _byId(id));
  }

  // Throws an AccountException if the email or the password is wrong
  Future<void> signIn(String email, String password) async {
    await _signInAs(await _verified(email, password));
  }

  Future<void> signOut() async {
    _account = null;
    notifyListeners();
    await database.setSetting(_setting, null);
  }

  // Deletes the signed in account, once its password is confirmed
  Future<void> deleteAccount(String password) async {
    final account = await _verified(_account?.email ?? '', password);
    await (database.delete(database.accounts)..where((t) => t.id.equals(account.id))).go();
    await signOut();
  }

  // The account with [email] if [password] is right. Both mistakes get the
  // same message, and an unknown email takes as long as a wrong password, so
  // neither tells whether an account exists
  Future<Account> _verified(String email, String password) async {
    final account = await _byEmail(email);
    final hash = await _hash(
      password,
      account == null ? Uint8List(_saltLength) : base64.decode(account.salt),
      account?.iterations ?? passwordIterations,
    );
    if (account == null || !_sameBytes(hash, base64.decode(account.passwordHash))) {
      throw const AccountException('Wrong email or password');
    }
    return account;
  }

  Future<void> _signInAs(Account? account) async {
    if (account == null) return;
    _account = account;
    notifyListeners();
    await database.setSetting(_setting, '${account.id}');
  }

  static Future<Account?> _byId(int id) =>
      (database.select(database.accounts)..where((t) => t.id.equals(id))).getSingleOrNull();

  static Future<Account?> _byEmail(String email) =>
      (database.select(database.accounts)..where((t) => t.email.equals(_normalized(email))))
          .getSingleOrNull();
}

extension AccountNames on Account {
  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  // Up to two letters for the avatar, e.g. "MS"
  String get initials => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => String.fromCharCode(part.runes.first).toUpperCase())
      .join();
}

String _normalized(String email) => email.trim().toLowerCase();

final Random _random = Random.secure();

Uint8List _randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

// Compares in constant time, so the time taken doesn't reveal how many
// bytes of a hash were right
bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
