import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Phones get the phone layout in any orientation. Decided by the screen's shorter side, so
/// turning a phone sideways (or the moment of landscape while leaving the player) never
/// switches to the TV and tablet layout.
bool isPhoneLayout(BuildContext context) => MediaQuery.sizeOf(context).shortestSide < 600;

/// Which ways the screen may turn.
///
/// * Phones: the app stays upright, except the player, which turns with the phone
///   (following the phone's own rotation lock).
/// * Tablets, TVs and desktops: anything goes, everywhere.
abstract final class AppOrientation {
  /// Whether this device is a phone, by its screen's shorter side.
  static bool get _isPhone {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.shortestSide < 600;
  }

  /// Call once at startup.
  static Future<void> init() => menus();

  /// Everything outside the player: upright on phones, with the status and navigation bars.
  static Future<void> menus() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(
      _isPhone ? const [DeviceOrientation.portraitUp] : const [],
    );
  }

  /// Sideways, either way round.
  static const landscape = [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];

  /// Upright.
  static const portrait = [DeviceOrientation.portraitUp];

  /// The player: full screen, held to [only] (e.g. [landscape]). Left empty, it's free to turn
  /// with the phone, following the phone's own rotation lock. Tablets and TVs always turn freely.
  static Future<void> player({List<DeviceOrientation> only = const []}) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(_isPhone ? only : const []);
  }
}