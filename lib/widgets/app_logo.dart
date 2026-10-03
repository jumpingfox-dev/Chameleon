import 'package:flutter_svg/flutter_svg.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/theme_controller.dart';
import '../utils/theme_presets.dart';

/// Which version of the logo to show.
enum AppLogoVariant {
  /// Full color on the Prism theme, the theme-colored gradient on all others.
  auto,

  /// Always the theme-colored gradient.
  gradient,

  /// Always the full-color logo (falls back to the gradient if there's no color asset).
  color,
}

/// The app logo, in full color or as a theme-colored gradient (see [AppLogoVariant]).
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.asset = 'assets/images/logo.svg',
    this.colorAsset = 'assets/images/logo_color.svg',
    this.height = 32,
    this.variant = AppLogoVariant.auto,
  });

  /// Single-color version, filled with the gradient.
  final String asset;

  /// Full-color version. Pass null if there isn't one for this logo.
  final String? colorAsset;

  final double height;

  final AppLogoVariant variant;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemePreset>(
    valueListenable: themeController,
    builder: (context, preset, _) {
      final showColor =
          colorAsset != null &&
          switch (variant) {
            AppLogoVariant.color => true,
            AppLogoVariant.gradient => false,
            AppLogoVariant.auto => preset.id == 'default',
          };

      if (showColor) {
        // The logo's own colors, no gradient.
        return SvgPicture.asset(colorAsset!, height: height);
      }

      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            context.theme.colors.primary,
            context.theme.colors.border,
          ],
        ).createShader(bounds),
        child: SvgPicture.asset(asset, height: height),
      );
    },
  );
}
