import 'package:flutter/material.dart';

import '../database.dart';
import '../design/design_settings.dart';

late AppSettings appSettings;

// What the user sets in the menu: dark mode and design. Kept in the
// settings table, so it survives a restart. The app builds its theme from
// it and rebuilds whenever it changes, see main.dart
class AppSettings extends ChangeNotifier {
  static const _themeModeSetting = 'themeMode';
  static const _designSetting = 'design';

  ThemeMode _themeMode;
  DesignSettings _design;

  AppSettings([this._themeMode = ThemeMode.system, this._design = const DesignSettings()]);

  static Future<AppSettings> load() async => AppSettings(
        ThemeMode.values.asNameMap()[await database.setting(_themeModeSetting)] ?? ThemeMode.system,
        DesignSettings.decode(await database.setting(_designSetting)),
      );

  // System follows the setting of the phone
  ThemeMode get themeMode => _themeMode;

  DesignSettings get design => _design;

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await database.setSetting(_themeModeSetting, mode.name);
  }

  // [save] is false while a slider is dragged: the app shows each step right
  // away, but stores only the value it is let go at
  Future<void> setDesign(DesignSettings design, {bool save = true}) async {
    _design = design;
    notifyListeners();
    if (save) await database.setSetting(_designSetting, design.encode());
  }
}
