import 'package:forui/forui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui_phosphor/forui_phosphor.dart';

import 'styles/button_styles.dart';
import 'styles/sidebar_style.dart';

part 'colors.dart';
part 'typography.dart';
part 'style.dart';
part 'icons.dart';

FThemeData buildTheme(
  FColors colors, {
  required String displayFont,
  required String bodyFont,
}) {
  // Change this to false to use the desktop variant of this theme.
  const touch = false;

  final typography = _typography(
    colors: colors,
    touch: touch,
    displayFont: displayFont,
    bodyFont: bodyFont,
  );

  final icons = _icons();

  final style = _style(colors: colors, typography: typography, touch: touch);

  return FThemeData(
    colors: colors,
    typography: typography,
    icons: icons,
    style: style,
    touch: touch,
    buttonStyles: buttonStyles(colors: colors, typography: typography, style: style, touch: touch),
    sidebarStyle: sidebarStyle(colors: colors, typography: typography, icons: icons, style: style, touch: touch),
  );
}
