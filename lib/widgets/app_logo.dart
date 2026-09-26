import 'package:flutter_svg/flutter_svg.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/theme_controller.dart';
import '../utils/theme_presets.dart';

/// The app logo: full color on the Prism theme, a theme-colored gradient on all others.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.asset = 'assets/images/logo.svg',
    this.colorAsset = 'assets/images/logo_color.svg',
    this.height = 32,
  });

  /// Single-color version, filled with the gradient.
  final String asset;

  /// Full-color version shown on Prism. Pass null if there isn't one for this logo.
  final String? colorAsset;

  final double height;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemePreset>(
    valueListenable: themeController,
    builder: (context, preset, _) {
      if (preset.id == 'prism' && colorAsset != null) {
        // Prism: show the logo's own colors, no gradient.
        return SvgPicture.asset(colorAsset!, height: height);
      }

      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            context.theme.colors.primary,
            context.theme.colors.secondary,
          ],
        ).createShader(bounds),
        child: SvgPicture.asset(asset, height: height),
      );
    },
  );
}