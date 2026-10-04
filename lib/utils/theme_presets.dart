import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/theme.dart';

// Helper shortcut for clean HSL definitions
Color _hsl(double h, double s, double l, [double a = 1.0]) =>
    HSLColor.fromAHSL(a, h, s, l).toColor();

class ThemeSeed {
  const ThemeSeed(this.baseHue, this.accentHue, this.vibrance, this.depth);

  final int baseHue; // 0–359
  final int accentHue; // 0–359
  final int vibrance; // 0–9
  final int depth; // 0–9

  String get code =>
      '${baseHue.toString().padLeft(3, '0')}${accentHue.toString().padLeft(3, '0')}$vibrance$depth';

  /// Accepts "28533082" or "285-330-8-2".
  static ThemeSeed? parse(String input) {
    final digits = input.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^\d{8}$').hasMatch(digits)) return null;
    final base = int.parse(digits.substring(0, 3));
    final accent = int.parse(digits.substring(3, 6));
    if (base > 359 || accent > 359) return null;
    return ThemeSeed(base, accent, int.parse(digits[6]), int.parse(digits[7]));
  }

  ThemeSeed copyWith({
    int? baseHue,
    int? accentHue,
    int? vibrance,
    int? depth,
  }) => ThemeSeed(
    baseHue ?? this.baseHue,
    accentHue ?? this.accentHue,
    vibrance ?? this.vibrance,
    depth ?? this.depth,
  );
}

FColors generateColors(ThemeSeed s) {
  final b = s.baseHue.toDouble();
  final a = s.accentHue.toDouble();
  final accentSat = 0.40 + s.vibrance * 0.06; // 0.40 – 0.94
  final bgL = 0.03 + s.depth * 0.012; // 0.03 – 0.138

  return FColors(
    brightness: .dark,
    systemOverlayStyle: .light,
    barrier: _hsl(b, 0.50, 0.03, 0.6),
    background: _hsl(b, 0.35, bgL),
    foreground: _hsl(b, 0.15, 0.96),
    primary: _hsl(a, accentSat, 0.58),
    primaryForeground: _hsl(a, 1.0, 0.98),
    secondary: _hsl(b, 0.25, bgL + 0.09),
    secondaryForeground: _hsl(b, 0.15, 0.96),
    muted: _hsl(b, 0.25, bgL + 0.09),
    mutedForeground: _hsl(b, 0.15, 0.65),
    destructive: _hsl(0, 0.70, 0.50),
    destructiveForeground: _hsl(0, 0.0, 0.98),
    error: _hsl(0, 0.70, 0.50),
    errorForeground: _hsl(0, 0.0, 0.98),
    card: _hsl(b, 0.30, bgL + 0.04),
    border: _hsl(b, 0.20, bgL + 0.13),
    extensions: const [AppColors()],
  );
}

class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.label,
    required this.colors,
  });

  final String id;
  final String label;
  final FColors colors;
}

final themePresets = <ThemePreset>[
  ThemePreset(
    id: 'default',
    label: 'Default',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(227, 0.45, 0.03, 0.70),
      background: _hsl(227, 0.41, 0.067), // Logo background (#0a0d18)
      foreground: _hsl(186, 0.67, 0.941), // Wordmark (#e6f8fa)
      primary: _hsl(262, 0.83, 0.578), // Gradient start, violet (#7c3aed)
      primaryForeground: _hsl(186, 0.67, 0.941), // Wordmark, reads well on violet
      secondary: _hsl(262, 0.45, 0.18), // Deep violet: selected tabs and hover
      secondaryForeground: _hsl(186, 0.67, 0.941), // Wordmark
      muted: _hsl(226, 0.35, 0.12), // Lifted navy
      mutedForeground: _hsl(195, 0.15, 0.66), // Cool grey with a hint of cyan
      destructive: _hsl(355, 0.80, 0.60),
      destructiveForeground: _hsl(186, 0.67, 0.941),
      error: _hsl(355, 0.80, 0.60),
      errorForeground: _hsl(186, 0.67, 0.941),
      card: _hsl(226, 0.38, 0.10), // Slightly lifted navy
      border: _hsl(200, 0.35, 0.20), // Gradient end, cyan (#06b6d4), darkened
      extensions: const [AppColors()],
    ),
  ),

  // =============================================================================
  // 1. RUBY - "Pigeon's blood" red: deep wine surfaces, rose-white highlights.
  // =============================================================================
  ThemePreset(
    id: 'ruby',
    label: 'Ruby',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(345, 0.50, 0.03, 0.6),
      background: _hsl(345, 0.40, 0.05), // Deep wine
      foreground: _hsl(350, 0.30, 0.96), // Rose white
      primary: _hsl(350, 0.85, 0.52), // Pigeon's blood
      primaryForeground: _hsl(0, 0.0, 1.0),
      secondary: _hsl(335, 0.35, 0.15), // Garnet
      secondaryForeground: _hsl(340, 0.40, 0.92),
      muted: _hsl(345, 0.25, 0.13),
      mutedForeground: _hsl(345, 0.20, 0.67),
      destructive: _hsl(
        12,
        0.85,
        0.55,
      ), // Orange-red, distinct from the ruby primary
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(12, 0.85, 0.55),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(345, 0.35, 0.09),
      border: _hsl(345, 0.30, 0.20),
      extensions: const [AppColors()],
    ),
  ),

  // =============================================================================
  // 2. AMBER - Fossilized resin: honey-brown surfaces, cream text, glowing gold.
  // =============================================================================
  ThemePreset(
    id: 'amber',
    label: 'Amber',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(30, 0.50, 0.03, 0.6),
      background: _hsl(30, 0.40, 0.05), // Dark resin
      foreground: _hsl(40, 0.40, 0.93), // Cream
      primary: _hsl(35, 0.95, 0.55), // Glowing honey
      primaryForeground: _hsl(
        30,
        0.80,
        0.08,
      ), // Dark text on the bright primary
      secondary: _hsl(25, 0.40, 0.15), // Cognac
      secondaryForeground: _hsl(38, 0.50, 0.90),
      muted: _hsl(30, 0.30, 0.13),
      mutedForeground: _hsl(35, 0.25, 0.66),
      destructive: _hsl(0, 0.75, 0.55),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.75, 0.55),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(32, 0.35, 0.09), // Honey-brown
      border: _hsl(30, 0.35, 0.20),
      extensions: const [AppColors()],
    ),
  ),

  // =============================================================================
  // 3. CITRINE - Golden quartz: olive-gold depths, champagne light, sunny yellow.
  // =============================================================================
  ThemePreset(
    id: 'citrine',
    label: 'Citrine',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(48, 0.50, 0.03, 0.6),
      background: _hsl(48, 0.30, 0.05), // Olive-gold shadow
      foreground: _hsl(52, 0.50, 0.95), // Champagne
      primary: _hsl(48, 0.95, 0.55), // Sunlit citrine
      primaryForeground: _hsl(
        45,
        0.90,
        0.08,
      ), // Dark text on the bright primary
      secondary: _hsl(40, 0.35, 0.15), // Honey quartz
      secondaryForeground: _hsl(50, 0.50, 0.90),
      muted: _hsl(48, 0.25, 0.13),
      mutedForeground: _hsl(48, 0.22, 0.66),
      destructive: _hsl(0, 0.75, 0.55),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.75, 0.55),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(50, 0.25, 0.09),
      border: _hsl(46, 0.35, 0.20),
      extensions: const [AppColors()],
    ),
  ),

  // =============================================================================
  // 4. EMERALD - Deep blue-green depths, mint-white light, vivid green facets.
  // =============================================================================
  ThemePreset(
    id: 'emerald',
    label: 'Emerald',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(160, 0.50, 0.03, 0.6),
      background: _hsl(160, 0.40, 0.05), // Forest depth
      foreground: _hsl(140, 0.25, 0.95), // Mint white
      primary: _hsl(150, 0.75, 0.45), // Emerald facet
      primaryForeground: _hsl(160, 0.60, 0.06), // near-black forest green
      secondary: _hsl(170, 0.40, 0.14), // Teal inclusion
      secondaryForeground: _hsl(160, 0.45, 0.90),
      muted: _hsl(155, 0.28, 0.13),
      mutedForeground: _hsl(150, 0.18, 0.65),
      destructive: _hsl(0, 0.75, 0.55),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.75, 0.55),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(155, 0.35, 0.09),
      border: _hsl(150, 0.30, 0.20),
      extensions: const [AppColors()],
    ),
  ),

  // =============================================================================
  // 5. SAPPHIRE - Royal navy depths, silvery light, cornflower-blue brilliance.
  // =============================================================================
  ThemePreset(
    id: 'sapphire',
    label: 'Sapphire',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(225, 0.50, 0.03, 0.6),
      background: _hsl(225, 0.50, 0.06), // Royal navy
      foreground: _hsl(215, 0.30, 0.96), // Silvery white
      primary: _hsl(220, 0.90, 0.60), // Cornflower brilliance
      primaryForeground: _hsl(0, 0.0, 1.0),
      secondary: _hsl(232, 0.40, 0.16), // Deep royal blue
      secondaryForeground: _hsl(220, 0.50, 0.92),
      muted: _hsl(225, 0.30, 0.14),
      mutedForeground: _hsl(215, 0.20, 0.67),
      destructive: _hsl(0, 0.75, 0.55),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.75, 0.55),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(225, 0.40, 0.10),
      border: _hsl(220, 0.35, 0.22),
      extensions: const [AppColors()],
    ),
  ),

  // =============================================================================
  // 6. TANZANITE - Trichroic blue-violet: blue depths that flash violet.
  // =============================================================================
  ThemePreset(
    id: 'tanzanite',
    label: 'Tanzanite',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(250, 0.50, 0.03, 0.6),
      background: _hsl(245, 0.40, 0.06), // Blue depth
      foreground: _hsl(255, 0.35, 0.96), // Lavender white
      primary: _hsl(252, 0.75, 0.65), // Blue-violet flash
      primaryForeground: _hsl(0, 0.0, 1.0),
      secondary: _hsl(268, 0.35, 0.16), // Violet facet
      secondaryForeground: _hsl(265, 0.45, 0.92),
      muted: _hsl(238, 0.30, 0.14), // Blue facet
      mutedForeground: _hsl(250, 0.20, 0.68),
      destructive: _hsl(0, 0.75, 0.55),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.75, 0.55),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(248, 0.35, 0.10),
      border: _hsl(258, 0.30, 0.22),
      extensions: const [AppColors()],
    ),
  ),

  // =============================================================================
  // 7. AMETHYST - Royal purple quartz: plum depths, lavender light, orchid glow.
  // =============================================================================
  ThemePreset(
    id: 'amethyst',
    label: 'Amethyst',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(280, 0.50, 0.03, 0.6),
      background: _hsl(280, 0.35, 0.06), // Plum depth
      foreground: _hsl(285, 0.35, 0.96), // Lavender white
      primary: _hsl(280, 0.70, 0.62), // Royal amethyst
      primaryForeground: _hsl(0, 0.0, 1.0),
      secondary: _hsl(295, 0.30, 0.16), // Orchid shadow
      secondaryForeground: _hsl(290, 0.40, 0.92),
      muted: _hsl(278, 0.25, 0.14),
      mutedForeground: _hsl(280, 0.20, 0.68),
      destructive: _hsl(0, 0.75, 0.55),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.75, 0.55),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(280, 0.30, 0.10),
      border: _hsl(285, 0.28, 0.22),
      extensions: const [AppColors()],
    ),
  ),

  // =============================================================================
  // ADD CUSTOM THEMES
  // =============================================================================
];
