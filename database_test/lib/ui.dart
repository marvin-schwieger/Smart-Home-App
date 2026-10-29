import 'package:flutter/material.dart';

import 'design/app_design.dart';

export 'design/app_design.dart' show DesignOf;

// Building blocks shared by the pages, the sheets and the device widgets.
// Their colors, corners and sizes come from context.design (see
// design/app_design.dart), never from fixed values

// Frame of a bottom sheet: title, subtitle and the form below it
class SheetBody extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const SheetBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    final side = design.padding + 4;
    return SingleChildScrollView(
      // The bottom inset keeps the form above the on-screen keyboard.
      padding: EdgeInsets.fromLTRB(
        side,
        0,
        side,
        side + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 13, color: design.muted)),
          SizedBox(height: design.spacing + 4),
          ...children,
        ],
      ),
    );
  }
}

// Small caps heading above a group, e.g. SENSORS in the pickers
class GroupLabel extends StatelessWidget {
  final String text;

  const GroupLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: context.design.muted),
    );
  }
}

// Label above a form control, e.g. "Transport"
class FieldLabel extends StatelessWidget {
  final String text;

  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: TextStyle(fontSize: 13, color: context.design.muted)),
    );
  }
}

// Surface of a card on a page: rooms, devices, widgets, sections. Tappable
// if [onTap] or [onLongPress] is given
class DesignCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const DesignCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(design.cardRadius),
      side: design.border,
    );
    final content = Padding(padding: padding ?? EdgeInsets.all(design.padding), child: child);
    return Material(
      color: design.card,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null && onLongPress == null
          ? content
          : InkWell(onTap: onTap, onLongPress: onLongPress, customBorder: shape, child: content),
    );
  }
}

// Heading and a card below it, e.g. the groups of the settings page
class SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SectionCard({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    return Padding(
      padding: EdgeInsets.only(bottom: design.spacing + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GroupLabel(title),
          const SizedBox(height: 8),
          DesignCard(
            padding: EdgeInsets.all(design.padding * 0.75),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Icon in a small rounded box, e.g. in the picker tiles. [accent] tints it
// with the accent color, [selected] fills it
class IconBox extends StatelessWidget {
  final IconData icon;
  final bool accent;
  final bool selected;

  const IconBox(this.icon, {super.key, this.accent = false, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary
            : accent
                ? design.highlight
                : design.field,
        borderRadius: BorderRadius.circular(design.badgeRadius),
      ),
      child: Icon(
        icon,
        size: design.iconSize,
        color: selected
            ? scheme.onPrimary
            : accent
                ? scheme.primary
                : scheme.onSurface,
      ),
    );
  }
}

// One option of a list where one is picked, e.g. a method on the
// authentication page: something in front, name, a line below and a radio
// mark at the end
class OptionTile extends StatelessWidget {
  final Widget leading;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const OptionTile({
    super.key,
    required this.leading,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(design.fieldRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: design.muted)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? primary : design.faint,
            ),
          ],
        ),
      ),
    );
  }
}

// Row of buttons where exactly one option is selected.
class ChoiceRow extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final String Function(String option)? labelBuilder;

  const ChoiceRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.labelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: ChoiceButton(
              label: labelBuilder?.call(options[i]) ?? options[i],
              selected: options[i] == selected,
              onTap: () => onSelected(options[i]),
            ),
          ),
        ],
      ],
    );
  }
}

// One button of a ChoiceRow, filled while selected
class ChoiceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(design.fieldRadius);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        height: design.choiceHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? scheme.primary : design.field,
          borderRadius: radius,
          border: selected || design.borderWidth == 0
              ? null
              : Border.all(color: design.outline, width: design.borderWidth),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? scheme.onPrimary : design.icon,
          ),
        ),
      ),
    );
  }
}

// Entry of a picker sheet: icon, name and a short line below. Tapping it
// closes the sheet with [value] as result
class PickerTile<T> extends StatelessWidget {
  final T value;
  final IconData icon;
  final String label;
  final String subtitle;

  const PickerTile({
    super.key,
    required this.value,
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    final radius = BorderRadius.circular(design.fieldRadius);
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: design.borderWidth > 0 ? design.outline : design.field,
            width: 1.5,
          ),
          borderRadius: radius,
        ),
        child: Row(
          children: [
            IconBox(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: design.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Tiles of a picker sheet, two per row
class PickerGrid extends StatelessWidget {
  final List<Widget> children;

  const PickerGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: context.design.tileHeight,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      children: children,
    );
  }
}

// Large button at the end of a form, e.g. Save
class SaveButton extends StatelessWidget {
  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  const SaveButton({
    super.key,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    return SizedBox(
      width: double.infinity,
      height: design.buttonHeight,
      child: FilledButton(
        // Stays disabled until the required fields are filled in
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(design.buttonRadius)),
        ),
        child: Text(label),
      ),
    );
  }
}

// Large outlined button, e.g. "Add widget"
class WideOutlinedButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const WideOutlinedButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    return SizedBox(
      width: double.infinity,
      height: design.buttonHeight,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(design.buttonRadius)),
        ),
      ),
    );
  }
}

// Label and value in one line, e.g. "Email  marvin@example.com"
class InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const InfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 13, color: context.design.muted)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

// Box with monospace text, e.g. a payload or a response
class CodeBox extends StatelessWidget {
  final String text;

  const CodeBox(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final design = context.design;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: design.field,
        borderRadius: BorderRadius.circular(design.badgeRadius),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }
}

// Fill, corners and borders come from the theme, see buildTheme
InputDecoration fieldDecoration(String label, {String? hint, String? helper}) => InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
    );
