import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

typedef ColorToken = ({
  String label,
  Color Function(FColors c) get,
  FColors Function(FColors c, Color v) set,
});

final colorTokens = <String, ColorToken>{
  'background': (
    label: 'Background',
    get: (c) => c.background,
    set: (c, v) => c.copyWith(background: v),
  ),
  'foreground': (
    label: 'Foreground',
    get: (c) => c.foreground,
    set: (c, v) => c.copyWith(foreground: v),
  ),
  'primary': (
    label: 'Primary',
    get: (c) => c.primary,
    set: (c, v) => c.copyWith(primary: v),
  ),
  'primaryForeground': (
    label: 'Primary text',
    get: (c) => c.primaryForeground,
    set: (c, v) => c.copyWith(primaryForeground: v),
  ),
  'secondary': (
    label: 'Secondary',
    get: (c) => c.secondary,
    set: (c, v) => c.copyWith(secondary: v),
  ),
  'secondaryForeground': (
    label: 'Secondary text',
    get: (c) => c.secondaryForeground,
    set: (c, v) => c.copyWith(secondaryForeground: v),
  ),
  'muted': (
    label: 'Muted',
    get: (c) => c.muted,
    set: (c, v) => c.copyWith(muted: v),
  ),
  'mutedForeground': (
    label: 'Muted text',
    get: (c) => c.mutedForeground,
    set: (c, v) => c.copyWith(mutedForeground: v),
  ),
  'destructive': (
    label: 'Destructive',
    get: (c) => c.destructive,
    set: (c, v) => c.copyWith(destructive: v),
  ),
  'destructiveForeground': (
    label: 'Destructive text',
    get: (c) => c.destructiveForeground,
    set: (c, v) => c.copyWith(destructiveForeground: v),
  ),
  'error': (
    label: 'Error',
    get: (c) => c.error,
    set: (c, v) => c.copyWith(error: v),
  ),
  'errorForeground': (
    label: 'Error text',
    get: (c) => c.errorForeground,
    set: (c, v) => c.copyWith(errorForeground: v),
  ),
  'card': (
    label: 'Card',
    get: (c) => c.card,
    set: (c, v) => c.copyWith(card: v),
  ),
  'border': (
    label: 'Border',
    get: (c) => c.border,
    set: (c, v) => c.copyWith(border: v),
  ),
  'barrier': (
    label: 'Barrier',
    get: (c) => c.barrier,
    set: (c, v) => c.copyWith(barrier: v),
  ),
};

FColors withBrightness(FColors c, bool light) => c.copyWith(
  brightness: light ? Brightness.light : Brightness.dark,
  systemOverlayStyle: light
      ? SystemUiOverlayStyle.dark
      : SystemUiOverlayStyle.light,
);

final _hexPattern = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');
final _hslPattern = RegExp(
  r'^hsla?\(\s*([\d.]+)\s*,\s*([\d.]+)%?\s*,\s*([\d.]+)%?\s*(?:,\s*([\d.]+)\s*)?\)$',
  caseSensitive: false,
);

/// Parses #RRGGBB, #AARRGGBB, hsl(h, s%, l%) or hsla(h, s%, l%, a).
Color? parseColor(String input) {
  final v = input.trim();

  final hex = _hexPattern.firstMatch(v);
  if (hex != null) {
    final digits = hex.group(1)!;
    return Color(
      int.parse(digits.length == 6 ? 'FF$digits' : digits, radix: 16),
    );
  }

  final hsl = _hslPattern.firstMatch(v);
  if (hsl != null) {
    final h = double.parse(hsl.group(1)!) % 360;
    final s = (double.parse(hsl.group(2)!) / 100).clamp(0.0, 1.0);
    final l = (double.parse(hsl.group(3)!) / 100).clamp(0.0, 1.0);
    final a = hsl.group(4) == null
        ? 1.0
        : double.parse(hsl.group(4)!).clamp(0.0, 1.0);
    return HSLColor.fromAHSL(a, h, s, l).toColor();
  }

  return null;
}

String _toHex(Color c) {
  final argb = c.toARGB32();
  final opaque = (argb >> 24) == 0xFF;
  final digits = opaque
      ? (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')
      : argb.toRadixString(16).padLeft(8, '0');
  return '#${digits.toUpperCase()}';
}

/// Writes colors out as INI text, used to pre-fill the editor.
String colorsToIni(FColors c) {
  final out = StringBuffer('[theme]\nbrightness = ${c.brightness.name}\n');
  for (final e in colorTokens.entries) {
    out.writeln('${e.key} = ${_toHex(e.value.get(c))}');
  }
  return out.toString();
}

/// Parses INI text on top of [base]. Returns the colors, or the errors if any line is invalid.
({FColors? colors, List<String> errors}) parseColorIni(
  String text,
  FColors base,
) {
  final keys = {for (final k in colorTokens.keys) k.toLowerCase(): k};
  final errors = <String>[];
  var colors = base;

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final commentAt = line.indexOf(' ;');
    if (commentAt != -1)
      line = line.substring(0, commentAt).trim(); // inline "; comment"

    if (line.isEmpty ||
        line.startsWith(';') ||
        line.startsWith('#') ||
        line.startsWith('['))
      continue;

    final sep = line.indexOf(RegExp('[=:]'));
    if (sep == -1) {
      errors.add('Line ${i + 1}: expected "name = color"');
      continue;
    }
    final name = line.substring(0, sep).trim().toLowerCase();
    final value = line.substring(sep + 1).trim();

    if (name == 'brightness') {
      if (value != 'light' && value != 'dark') {
        errors.add('Line ${i + 1}: brightness must be "light" or "dark"');
      } else {
        colors = withBrightness(colors, value == 'light');
      }
      continue;
    }

    final key = keys[name];
    if (key == null) {
      errors.add('Line ${i + 1}: unknown name "$name"');
      continue;
    }
    final color = parseColor(value);
    if (color == null) {
      errors.add('Line ${i + 1}: invalid color "$value"');
      continue;
    }
    colors = colorTokens[key]!.set(colors, color);
  }

  return errors.isEmpty
      ? (colors: colors, errors: const [])
      : (colors: null, errors: errors);
}
