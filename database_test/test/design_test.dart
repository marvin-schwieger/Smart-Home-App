import 'package:database_test/database.dart';
import 'package:database_test/design/app_design.dart';
import 'package:database_test/design/design_presets.dart';
import 'package:database_test/design/design_settings.dart';
import 'package:database_test/settings/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every preset builds a light and a dark theme with its design attached', () {
    expect(designPresets.map((p) => p.id).toSet(), hasLength(designPresets.length));
    for (final preset in designPresets) {
      for (final brightness in Brightness.values) {
        final theme = buildTheme(DesignSettings(preset: preset.id), brightness);
        final design = theme.extension<AppDesign>()!;
        final expected = brightness == Brightness.dark ? preset.dark : preset.light;

        expect(theme.brightness, brightness, reason: preset.id);
        expect(theme.scaffoldBackgroundColor, expected.background, reason: preset.id);
        expect(design.cardRadius, expected.cardRadius, reason: preset.id);
        expect(design.highlight, expected.highlight, reason: preset.id);
      }
    }
  });

  test('roundness and size scale the preset, the outline switch overrides it', () {
    const settings = DesignSettings(preset: 'warm', roundness: 0, size: 1.2, borders: true);

    final design = settings.design(Brightness.light);

    expect(design.cardRadius, 0);
    expect(design.buttonHeight, closeTo(52 * 1.2, 0.001));
    expect(design.borderWidth, 1);
    expect(const DesignSettings(preset: 'outline', borders: false).design(Brightness.light).borderWidth, 0);
  });

  test('an own accent replaces the highlight of the preset', () {
    final theme = buildTheme(const DesignSettings(accent: Color(0xFFDC2626)), Brightness.light);

    expect(theme.extension<AppDesign>()!.highlight, theme.colorScheme.primaryContainer);
  });

  test('settings survive JSON, broken or odd values fall back', () {
    const settings = DesignSettings(
      preset: 'soft',
      accent: Color(0xFF16A34A),
      roundness: 1.5,
      size: 0.9,
      textScale: 1.2,
      borders: true,
    );

    expect(DesignSettings.decode(settings.encode()), settings);
    expect(DesignSettings.decode('not json'), const DesignSettings());
    expect(DesignSettings.decode(null), const DesignSettings());
    final odd = DesignSettings.decode('{"preset":"gone","roundness":9,"size":"big"}');
    expect((odd.preset, odd.roundness, odd.size), ('warm', 2.0, 1.0));
  });

  test('another preset starts without changes but keeps the text size', () {
    const settings = DesignSettings(accent: Color(0xFF16A34A), roundness: 0.5, textScale: 1.2);

    expect(settings.withPreset('clean'), const DesignSettings(preset: 'clean', textScale: 1.2));
  });

  test('dark mode and design are stored and loaded again', () async {
    database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final settings = AppSettings();
    await settings.setThemeMode(ThemeMode.dark);
    await settings.setDesign(const DesignSettings(preset: 'outline', roundness: 0.5));
    // Not stored while a slider is dragged
    await settings.setDesign(const DesignSettings(preset: 'outline', roundness: 1.8), save: false);

    final loaded = await AppSettings.load();
    expect(loaded.themeMode, ThemeMode.dark);
    expect(loaded.design, const DesignSettings(preset: 'outline', roundness: 0.5));
  });

  testWidgets('widgets without the design in their theme get the warm one', (tester) async {
    late AppDesign design;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(builder: (context) {
          design = context.design;
          return const SizedBox();
        }),
      ),
    );

    expect(design, AppDesign.warmDark);
  });
}
