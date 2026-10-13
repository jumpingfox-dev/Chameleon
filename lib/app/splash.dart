import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// What a TV shows while the app starts: the full wordmark, centered, as on the TV banner
/// (`android/app/src/main/res/drawable-xhdpi/tv_banner.png`). Phones keep the system splash
/// up instead (see `main`).
///
/// Android 12+ only lets the system splash show a small icon, so on a TV it shows just the
/// background, and this takes over as soon as Flutter can draw. Before Android 12 the system
/// splash is the banner itself, and this draws the wordmark in the same place and size.
class TvSplash extends StatelessWidget {
  const TvSplash({super.key});

  /// The app icon's background, which the splash screens use too.
  static const background = Color(0xFF0A0D18);

  /// The wordmark's width on the banner, in logical pixels (960 px at xhdpi).
  static const _wordmarkWidth = 480.0;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: background,
    child: Center(
      child: SvgPicture.asset('assets/images/text_logo_color.svg', width: _wordmarkWidth),
    ),
  );
}
