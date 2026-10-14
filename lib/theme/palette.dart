import 'package:material_ui/material_ui.dart';

/// The colors a theme is made from: what the presets define and the custom theme editor
/// edits. [buildTheme] turns them into a Material [ColorScheme].
@immutable
class Palette {
  const Palette({
    this.brightness = Brightness.dark,
    required this.barrier,
    required this.background,
    required this.foreground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.error,
    required this.errorForeground,
    required this.card,
    required this.border,
  });

  final Brightness brightness;

  /// Dims what's behind dialogs, sheets and the open sidebar.
  final Color barrier;

  /// The page.
  final Color background;

  /// Text and icons on the page.
  final Color foreground;

  /// The accent: main buttons, selection, progress.
  final Color primary;
  final Color primaryForeground;

  /// Quieter fills: selected tabs and chips, tonal buttons, the focus highlight.
  final Color secondary;
  final Color secondaryForeground;

  /// Raised fills, such as text fields and placeholders.
  final Color muted;

  /// Secondary text: captions, hints, years.
  final Color mutedForeground;

  final Color destructive;
  final Color destructiveForeground;
  final Color error;
  final Color errorForeground;

  /// Cards and dialogs.
  final Color card;

  /// Outlines and dividers.
  final Color border;

  Palette copyWith({
    Brightness? brightness,
    Color? barrier,
    Color? background,
    Color? foreground,
    Color? primary,
    Color? primaryForeground,
    Color? secondary,
    Color? secondaryForeground,
    Color? muted,
    Color? mutedForeground,
    Color? destructive,
    Color? destructiveForeground,
    Color? error,
    Color? errorForeground,
    Color? card,
    Color? border,
  }) => Palette(
    brightness: brightness ?? this.brightness,
    barrier: barrier ?? this.barrier,
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    primary: primary ?? this.primary,
    primaryForeground: primaryForeground ?? this.primaryForeground,
    secondary: secondary ?? this.secondary,
    secondaryForeground: secondaryForeground ?? this.secondaryForeground,
    muted: muted ?? this.muted,
    mutedForeground: mutedForeground ?? this.mutedForeground,
    destructive: destructive ?? this.destructive,
    destructiveForeground: destructiveForeground ?? this.destructiveForeground,
    error: error ?? this.error,
    errorForeground: errorForeground ?? this.errorForeground,
    card: card ?? this.card,
    border: border ?? this.border,
  );

  /// The Material color roles for this palette. Surfaces step up from [background] through
  /// [card] to [muted], so Material's raised containers keep the theme's tint.
  ColorScheme toColorScheme() => ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: primaryForeground,
    primaryContainer: secondary,
    onPrimaryContainer: secondaryForeground,
    secondary: Color.lerp(primary, foreground, 0.35)!,
    onSecondary: background,
    secondaryContainer: secondary,
    onSecondaryContainer: secondaryForeground,
    tertiary: Color.lerp(border, foreground, 0.4)!,
    onTertiary: background,
    error: error,
    onError: errorForeground,
    errorContainer: Color.lerp(background, destructive, 0.25)!,
    onErrorContainer: Color.lerp(destructive, foreground, 0.6)!,
    surface: background,
    onSurface: foreground,
    onSurfaceVariant: mutedForeground,
    surfaceDim: background,
    surfaceBright: Color.lerp(muted, foreground, 0.08)!,
    surfaceContainerLowest: Color.lerp(background, Colors.black, 0.3)!,
    surfaceContainerLow: Color.lerp(background, card, 0.5)!,
    surfaceContainer: card,
    surfaceContainerHigh: Color.lerp(card, muted, 0.6)!,
    surfaceContainerHighest: muted,
    outline: Color.lerp(border, foreground, 0.3)!,
    outlineVariant: border,
    shadow: Colors.black,
    scrim: barrier,
    inverseSurface: foreground,
    onInverseSurface: background,
    inversePrimary: Color.lerp(primary, background, 0.4)!,
    surfaceTint: Colors.transparent, // the surfaces above already carry the theme's tint
  );
}
