import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'app_design.dart';
import 'design_presets.dart';

// What the user picked on the settings page: a preset and how it is changed.
// Stored as JSON, see settings/app_settings.dart
@immutable
class DesignSettings {
  // Id of a DesignPreset
  final String preset;

  // Replaces the accent of the preset, null keeps it
  final Color? accent;

  // Times every corner radius: 0 is square, 1 as designed, 2 twice as round
  final double roundness;

  // Times every height, gap and padding
  final double size;

  // Times every text
  final double textScale;

  // Borders around cards and fields, null keeps those of the preset
  final bool? borders;

  const DesignSettings({
    this.preset = 'warm',
    this.accent,
    this.roundness = 1,
    this.size = 1,
    this.textScale = 1,
    this.borders,
  });

  // Limits of the sliders on the settings page
  static const (double, double) roundnessRange = (0, 2);
  static const (double, double) sizeRange = (0.85, 1.25);
  static const (double, double) textScaleRange = (0.85, 1.3);

  DesignPreset get basis => designPreset(preset);

  Color get accentColor => accent ?? basis.accent;

  bool get hasBorders => borders ?? basis.light.borderWidth > 0;

  // The design for [brightness] with all changes applied. Without an accent
  // of its own the preset keeps its highlight, otherwise it comes from the
  // accent, see buildTheme
  AppDesign design(Brightness brightness, {Color? highlight}) {
    final base = brightness == Brightness.dark ? basis.dark : basis.light;
    return base.scaled(roundness: roundness, size: size).copyWith(
          borderWidth: hasBorders ? max(1.0, base.borderWidth) : 0,
          highlight: accent == null ? null : highlight,
        );
  }

  // Another preset starts without changes, only the text size stays
  DesignSettings withPreset(String preset) => DesignSettings(preset: preset, textScale: textScale);

  DesignSettings withAccent(Color? accent) => DesignSettings(
        preset: preset,
        accent: accent,
        roundness: roundness,
        size: size,
        textScale: textScale,
        borders: borders,
      );

  DesignSettings withBorders(bool borders) => DesignSettings(
        preset: preset,
        accent: accent,
        roundness: roundness,
        size: size,
        textScale: textScale,
        borders: borders,
      );

  DesignSettings copyWith({double? roundness, double? size, double? textScale}) => DesignSettings(
        preset: preset,
        accent: accent,
        roundness: roundness ?? this.roundness,
        size: size ?? this.size,
        textScale: textScale ?? this.textScale,
        borders: borders,
      );

  String encode() => jsonEncode({
        'preset': preset,
        'accent': accent?.toARGB32(),
        'roundness': roundness,
        'size': size,
        'textScale': textScale,
        'borders': borders,
      });

  // The defaults if [json] is missing or can't be read; values outside the
  // sliders are pulled back into them
  factory DesignSettings.decode(String? json) {
    if (json == null) return const DesignSettings();
    try {
      final map = jsonDecode(json);
      if (map is! Map<String, dynamic>) return const DesignSettings();
      double number(String key, (double, double) range) => switch (map[key]) {
            num value => value.toDouble().clamp(range.$1, range.$2),
            _ => 1.0,
          };
      return DesignSettings(
        preset: designPreset('${map['preset']}').id,
        accent: switch (map['accent']) { int argb => Color(argb), _ => null },
        roundness: number('roundness', roundnessRange),
        size: number('size', sizeRange),
        textScale: number('textScale', textScaleRange),
        borders: switch (map['borders']) { bool borders => borders, _ => null },
      );
    } on FormatException {
      return const DesignSettings();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DesignSettings &&
      other.preset == preset &&
      other.accent == accent &&
      other.roundness == roundness &&
      other.size == size &&
      other.textScale == textScale &&
      other.borders == borders;

  @override
  int get hashCode => Object.hash(preset, accent, roundness, size, textScale, borders);
}

// The Material theme for [settings], with the design attached as extension.
// Material widgets that the app doesn't draw itself, like the switches,
// dialogs and the menu, take their colors and shapes from here
ThemeData buildTheme(DesignSettings settings, Brightness brightness) {
  final seeded = ColorScheme.fromSeed(seedColor: settings.accentColor, brightness: brightness);
  final design = settings.design(brightness, highlight: seeded.primaryContainer);
  final scheme = seeded.copyWith(error: design.error);

  RoundedRectangleBorder shape(double radius, {BorderSide side = BorderSide.none}) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);
  OutlineInputBorder fieldBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(design.fieldRadius),
        borderSide: design.borderWidth > 0
            ? BorderSide(color: color, width: design.borderWidth)
            : BorderSide.none,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: design.background,
    canvasColor: design.sheet,
    extensions: [design],
    appBarTheme: AppBarTheme(
      backgroundColor: design.background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: design.card,
      elevation: 0,
      shape: shape(design.cardRadius, side: design.border),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: design.sheet,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: design.faint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(design.sheetRadius)),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: design.sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(design.sheetRadius)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: design.sheet,
      surfaceTintColor: Colors.transparent,
      shape: shape(design.sheetRadius),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: design.sheet,
      surfaceTintColor: Colors.transparent,
      shape: shape(design.fieldRadius, side: design.border),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: design.field,
      helperMaxLines: 2,
      border: fieldBorder(design.outline),
      enabledBorder: fieldBorder(design.outline),
      disabledBorder: fieldBorder(design.outline),
      focusedBorder: fieldBorder(scheme.primary),
      errorBorder: fieldBorder(design.error),
      focusedErrorBorder: fieldBorder(design.error),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape(design.buttonRadius)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: shape(design.buttonRadius)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(shape: shape(design.buttonRadius)),
    dividerTheme: DividerThemeData(color: design.outline),
    listTileTheme: ListTileThemeData(iconColor: design.icon),
  );
}
