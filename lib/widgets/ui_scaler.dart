import 'package:material_ui/material_ui.dart';

/// Scales the entire UI in proportion to the window width.
class UiScaler extends StatelessWidget {
  const UiScaler({super.key, required this.child});

  final Widget child;

  /// The width your layout is designed at. At this width, scale = 1.0.
  static const designWidth = 1280.0;

  /// Phones keep their normal size, so the bottom nav layout still applies.
  static const phoneBreakpoint = 600.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width;

    final scale = width < phoneBreakpoint
        ? 1.0
        : (width / designWidth)
              .clamp(0.8, 2.5)
              .toDouble(); // don't get tiny or huge

    if (scale == 1.0) return child;

    // Lay the app out at a smaller or larger "virtual" size, then stretch it to fill the window.
    final virtualSize = mq.size / scale;

    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: virtualSize,
        child: MediaQuery(
          data: mq.copyWith(
            size: virtualSize,
            // Keep SafeArea correct at the new scale.
            padding: mq.padding / scale,
            viewPadding: mq.viewPadding / scale,
            viewInsets: mq.viewInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}
