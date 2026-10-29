import 'package:database_test/account/accounts.dart';
import 'package:database_test/database.dart';
import 'package:database_test/design/app_design.dart';
import 'package:database_test/main.dart';
import 'package:database_test/settings/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The menu of the home page with the account, the dark mode, the settings
// and about, in the whole app

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label), text);
  await tester.pump();
}

// Theme of the home page, also while another page lies on top of it
ThemeData _theme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(HomePage, skipOffstage: false)));

void main() {
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    appSettings = AppSettings();
    session = Session();
    // The fake clock of widget tests doesn't wait for an isolate
    hashInBackground = false;
    passwordIterations = 1000;
  });
  tearDown(() {
    hashInBackground = true;
    passwordIterations = defaultPasswordIterations;
    return database.close();
  });

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
  }

  testWidgets('a new account is created from the menu and greeted', (tester) async {
    await start(tester);
    expect(find.text('Hello'), findsOneWidget);

    await _openMenu(tester);
    expect(find.text('Not signed in'), findsOneWidget);
    await _tap(tester, find.text('Sign in'));
    await _tap(tester, find.text('No account yet? Create one'));

    await _enter(tester, 'NAME', 'Marvin Test');
    await _enter(tester, 'EMAIL', 'marvin@example.com');
    await _enter(tester, 'PASSWORD', 'secret123');
    expect(find.text('The passwords differ'), findsOneWidget);
    await _enter(tester, 'REPEAT PASSWORD', 'secret123');
    await _tap(tester, find.widgetWithText(FilledButton, 'Create account'));

    expect(find.text('Hello, Marvin'), findsOneWidget);
    await _openMenu(tester);
    expect(find.text('Marvin Test'), findsOneWidget);
    expect(find.text('marvin@example.com'), findsOneWidget);

    await _tap(tester, find.text('Sign out'));
    // Lets the snack bar run out
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('signing in with a wrong password shows why', (tester) async {
    await Session().register(name: 'Marvin', email: 'marvin@example.com', password: 'secret123');
    await start(tester);

    await _openMenu(tester);
    await _tap(tester, find.text('Sign in'));
    await _enter(tester, 'EMAIL', 'marvin@example.com');
    await _enter(tester, 'PASSWORD', 'wrong pass');
    await _tap(tester, find.widgetWithText(FilledButton, 'Sign in'));
    expect(find.text('Wrong email or password'), findsOneWidget);

    await _enter(tester, 'PASSWORD', 'secret123');
    await _tap(tester, find.widgetWithText(FilledButton, 'Sign in'));
    expect(find.text('Hello, Marvin'), findsOneWidget);
  });

  testWidgets('the dark mode switch changes the theme and is kept', (tester) async {
    await start(tester);
    expect(_theme(tester).brightness, Brightness.light);

    await _openMenu(tester);
    await _tap(tester, find.text('Dark mode'));

    expect(appSettings.themeMode, ThemeMode.dark);
    expect(_theme(tester).brightness, Brightness.dark);
    expect(_theme(tester).extension<AppDesign>()!.background, AppDesign.warmDark.background);
    expect(await database.setting('themeMode'), 'dark');
  });

  testWidgets('the settings page switches the design of the whole app', (tester) async {
    await start(tester);

    await _openMenu(tester);
    await _tap(tester, find.text('Settings'));
    await _tap(tester, find.text('Dark'));
    expect(appSettings.themeMode, ThemeMode.dark);

    await _tap(tester, find.text('Soft'));
    expect(appSettings.design.preset, 'soft');
    expect(_theme(tester).extension<AppDesign>()!.cardRadius, 26);
    expect(await database.setting('design'), contains('"preset":"soft"'));

    await _tap(tester, find.text('Outlines'));
    expect(_theme(tester).extension<AppDesign>()!.borderWidth, 1);
    await _tap(tester, find.text('Reset to Soft'));
    expect(_theme(tester).extension<AppDesign>()!.borderWidth, 0);
  });

  testWidgets('about shows the version', (tester) async {
    await start(tester);

    await _openMenu(tester);
    await _tap(tester, find.text('About'));

    expect(find.text('Version 0.1.0'), findsOneWidget);
    expect(find.text('Open source licenses'), findsOneWidget);
  });
}
