import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'palette.dart';

export 'palette.dart';

/// The app's Material 3 theme: [palette]'s colors, with [displayFont] for headings and titles
/// and [bodyFont] for everything else.
ThemeData buildTheme(Palette palette, {required String displayFont, required String bodyFont}) {
  final colors = palette.toColorScheme();
  final text = _textTheme(colors, displayFont: displayFont, bodyFont: bodyFont);

  // A remote has no pointer, so whatever has focus must be easy to spot from the couch:
  // a ring as well as Material's usual focus overlay.
  BorderSide? ring(Set<WidgetState> states, Color color) =>
      states.contains(WidgetState.focused) ? BorderSide(color: color, width: 2) : null;

  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    textTheme: text,
    scaffoldBackgroundColor: colors.surface,
    canvasColor: colors.surface,
    focusColor: colors.onSurface.withValues(alpha: 0.12),
    hoverColor: colors.onSurface.withValues(alpha: 0.08),
    dividerTheme: DividerThemeData(color: colors.outlineVariant, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(side: WidgetStateProperty.resolveWith((s) => ring(s, colors.onSurface))),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStateProperty.resolveWith(
          (s) => ring(s, colors.primary) ?? BorderSide(color: colors.outlineVariant),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(side: WidgetStateProperty.resolveWith((s) => ring(s, colors.primary))),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(side: WidgetStateProperty.resolveWith((s) => ring(s, colors.primary))),
    ),
    chipTheme: ChipThemeData(
      side: WidgetStateBorderSide.resolveWith(
        (s) =>
            ring(s, colors.primary) ??
            (s.contains(WidgetState.selected) ? BorderSide.none : BorderSide(color: colors.outlineVariant)),
      ),
    ),
    // Material's outlined text fields, which DropdownMenu and the app's ChoiceField match.
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(),
      hintStyle: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
    ),
    cardTheme: CardThemeData(
      color: colors.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: colors.surfaceContainerHigh, barrierColor: palette.barrier),
    bottomSheetTheme: BottomSheetThemeData(modalBarrierColor: palette.barrier),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceContainer,
      indicatorColor: colors.secondaryContainer,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Material's type scale, with [displayFont] for the display, headline and title styles and
/// [bodyFont] for the body and label styles.
TextTheme _textTheme(ColorScheme colors, {required String displayFont, required String bodyFont}) {
  final typography = Typography.material2021();
  final base = (colors.brightness == Brightness.dark ? typography.white : typography.black).apply(
    bodyColor: colors.onSurface,
    displayColor: colors.onSurface,
  );
  final display = _googleFamily(displayFont);
  final body = _googleFamily(bodyFont);
  TextStyle? font(TextStyle? style, String family) => style?.copyWith(fontFamily: family);
  return base.copyWith(
    displayLarge: font(base.displayLarge, display),
    displayMedium: font(base.displayMedium, display),
    displaySmall: font(base.displaySmall, display),
    headlineLarge: font(base.headlineLarge, display),
    headlineMedium: font(base.headlineMedium, display),
    headlineSmall: font(base.headlineSmall, display),
    titleLarge: font(base.titleLarge, display),
    titleMedium: font(base.titleMedium, display),
    titleSmall: font(base.titleSmall, display),
    bodyLarge: font(base.bodyLarge, body),
    bodyMedium: font(base.bodyMedium, body),
    bodySmall: font(base.bodySmall, body),
    labelLarge: font(base.labelLarge, body),
    labelMedium: font(base.labelMedium, body),
    labelSmall: font(base.labelSmall, body),
  );
}

/// Registers the font with google_fonts (downloading it if needed) and returns
/// the family name Flutter should use for it.
String _googleFamily(String name) => GoogleFonts.getFont(name).fontFamily!;

/// Genre buttons: rounded rectangles on the card color with light text, rather than Material's
/// accent-colored pills, which look busy in a grid or a row of genres. The theme's focus ring
/// still applies.
ButtonStyle genreButtonStyle(ColorScheme colors, {bool compact = false}) => OutlinedButton.styleFrom(
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  backgroundColor: colors.surfaceContainer,
  foregroundColor: colors.onSurface,
  visualDensity: compact ? VisualDensity.compact : null,
);

/// Shortcuts to the current theme's colors and text styles.
extension ThemeContext on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
