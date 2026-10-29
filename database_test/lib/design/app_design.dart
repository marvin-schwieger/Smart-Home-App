import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

// The look of the app in one place: colors, shapes and sizes of every kind
// of component. Widgets read them with context.design instead of fixed
// values, so another design only needs other values (see design_presets.dart)
// and the dark mode is just a second set of them.
//
// Attached to the theme as an extension, so a change of the design or of the
// dark mode animates like the rest of the theme
@immutable
class AppDesign extends ThemeExtension<AppDesign> {
  // Colors

  // Behind the pages
  final Color background;

  // Rooms, devices, widgets and sections on a page
  final Color card;

  // Bottom sheets, the menu and dialogs
  final Color sheet;

  // Text fields, choices that aren't picked, info boxes in sheets
  final Color field;

  // Soft accent behind icons, e.g. the icon of a room. Taken from the accent
  // color when the theme is built
  final Color highlight;

  // Subtitles, helper texts and the small headings above groups
  final Color muted;

  // Icons on cards and fields
  final Color icon;

  // Drag handles, dashed outlines, radio buttons that aren't picked
  final Color faint;

  // Borders of cards and fields when [borderWidth] is above 0
  final Color outline;

  final Color error;

  // Shapes: corner radii and borders

  final double cardRadius;
  final double sheetRadius;

  // Text fields, tiles in pickers, buttons of a choice row
  final double fieldRadius;

  // Large buttons, e.g. Save
  final double buttonRadius;

  // Small boxes: badges, icon boxes, code
  final double badgeRadius;

  // 0: cards and fields have no border
  final double borderWidth;

  // Sizes

  // Large buttons, e.g. Save
  final double buttonHeight;

  // Buttons of a choice row, e.g. GET/PUT
  final double choiceHeight;

  // Tiles in pickers, e.g. "Add a device"
  final double tileHeight;

  // Gap between fields and between cards
  final double spacing;

  // Inside cards and around pages
  final double padding;

  // Icons in tiles and icon boxes
  final double iconSize;

  const AppDesign({
    required this.background,
    required this.card,
    required this.sheet,
    required this.field,
    required this.highlight,
    required this.muted,
    required this.icon,
    required this.faint,
    required this.outline,
    required this.error,
    required this.cardRadius,
    required this.sheetRadius,
    required this.fieldRadius,
    required this.buttonRadius,
    required this.badgeRadius,
    required this.borderWidth,
    required this.buttonHeight,
    required this.choiceHeight,
    required this.tileHeight,
    required this.spacing,
    required this.padding,
    required this.iconSize,
  });

  // The original look of the app, also used where no design is attached to
  // the theme, e.g. in widget tests
  static const AppDesign warmLight = AppDesign(
    background: Color(0xFFF4F1EB),
    card: Color(0xFFFFFFFF),
    sheet: Color(0xFFFBF9F6),
    field: Color(0xFFEDE9E3),
    highlight: Color(0xFFEDEBFF),
    muted: Color(0xFF8D6E4A),
    icon: Color(0x8A000000),
    faint: Color(0x42000000),
    outline: Color(0xFFDDD6CB),
    error: Color(0xFFC62828),
    cardRadius: 16,
    sheetRadius: 28,
    fieldRadius: 12,
    buttonRadius: 14,
    badgeRadius: 8,
    borderWidth: 0,
    buttonHeight: 52,
    choiceHeight: 44,
    tileHeight: 64,
    spacing: 16,
    padding: 16,
    iconSize: 20,
  );

  static const AppDesign warmDark = AppDesign(
    background: Color(0xFF1A1815),
    card: Color(0xFF26231F),
    sheet: Color(0xFF211E1B),
    field: Color(0xFF332F2A),
    highlight: Color(0xFF2E3163),
    muted: Color(0xFFC9A882),
    icon: Color(0xB3FFFFFF),
    faint: Color(0x4DFFFFFF),
    outline: Color(0xFF443E37),
    error: Color(0xFFEF9A9A),
    cardRadius: 16,
    sheetRadius: 28,
    fieldRadius: 12,
    buttonRadius: 14,
    badgeRadius: 8,
    borderWidth: 0,
    buttonHeight: 52,
    choiceHeight: 44,
    tileHeight: 64,
    spacing: 16,
    padding: 16,
    iconSize: 20,
  );

  // Border of cards and fields, none while [borderWidth] is 0
  BorderSide get border =>
      borderWidth > 0 ? BorderSide(color: outline, width: borderWidth) : BorderSide.none;

  // The design with every corner radius times [roundness] and every height,
  // gap and padding times [size]
  AppDesign scaled({double roundness = 1, double size = 1}) => copyWith(
        cardRadius: cardRadius * roundness,
        sheetRadius: sheetRadius * roundness,
        fieldRadius: fieldRadius * roundness,
        buttonRadius: buttonRadius * roundness,
        badgeRadius: badgeRadius * roundness,
        buttonHeight: buttonHeight * size,
        choiceHeight: choiceHeight * size,
        tileHeight: tileHeight * size,
        spacing: spacing * size,
        padding: padding * size,
        iconSize: iconSize * size,
      );

  @override
  AppDesign copyWith({
    Color? background,
    Color? card,
    Color? sheet,
    Color? field,
    Color? highlight,
    Color? muted,
    Color? icon,
    Color? faint,
    Color? outline,
    Color? error,
    double? cardRadius,
    double? sheetRadius,
    double? fieldRadius,
    double? buttonRadius,
    double? badgeRadius,
    double? borderWidth,
    double? buttonHeight,
    double? choiceHeight,
    double? tileHeight,
    double? spacing,
    double? padding,
    double? iconSize,
  }) =>
      AppDesign(
        background: background ?? this.background,
        card: card ?? this.card,
        sheet: sheet ?? this.sheet,
        field: field ?? this.field,
        highlight: highlight ?? this.highlight,
        muted: muted ?? this.muted,
        icon: icon ?? this.icon,
        faint: faint ?? this.faint,
        outline: outline ?? this.outline,
        error: error ?? this.error,
        cardRadius: cardRadius ?? this.cardRadius,
        sheetRadius: sheetRadius ?? this.sheetRadius,
        fieldRadius: fieldRadius ?? this.fieldRadius,
        buttonRadius: buttonRadius ?? this.buttonRadius,
        badgeRadius: badgeRadius ?? this.badgeRadius,
        borderWidth: borderWidth ?? this.borderWidth,
        buttonHeight: buttonHeight ?? this.buttonHeight,
        choiceHeight: choiceHeight ?? this.choiceHeight,
        tileHeight: tileHeight ?? this.tileHeight,
        spacing: spacing ?? this.spacing,
        padding: padding ?? this.padding,
        iconSize: iconSize ?? this.iconSize,
      );

  @override
  AppDesign lerp(AppDesign? other, double t) {
    if (other == null) return this;
    Color color(Color a, Color b) => Color.lerp(a, b, t)!;
    double size(double a, double b) => lerpDouble(a, b, t)!;
    return AppDesign(
      background: color(background, other.background),
      card: color(card, other.card),
      sheet: color(sheet, other.sheet),
      field: color(field, other.field),
      highlight: color(highlight, other.highlight),
      muted: color(muted, other.muted),
      icon: color(icon, other.icon),
      faint: color(faint, other.faint),
      outline: color(outline, other.outline),
      error: color(error, other.error),
      cardRadius: size(cardRadius, other.cardRadius),
      sheetRadius: size(sheetRadius, other.sheetRadius),
      fieldRadius: size(fieldRadius, other.fieldRadius),
      buttonRadius: size(buttonRadius, other.buttonRadius),
      badgeRadius: size(badgeRadius, other.badgeRadius),
      borderWidth: size(borderWidth, other.borderWidth),
      buttonHeight: size(buttonHeight, other.buttonHeight),
      choiceHeight: size(choiceHeight, other.choiceHeight),
      tileHeight: size(tileHeight, other.tileHeight),
      spacing: size(spacing, other.spacing),
      padding: size(padding, other.padding),
      iconSize: size(iconSize, other.iconSize),
    );
  }
}

extension DesignOf on BuildContext {
  // The design of the current theme, see AppDesign
  AppDesign get design {
    final theme = Theme.of(this);
    return theme.extension<AppDesign>() ??
        (theme.brightness == Brightness.dark ? AppDesign.warmDark : AppDesign.warmLight);
  }
}
