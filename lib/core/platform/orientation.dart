import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether this is an Android TV or Google TV. Set once at startup by [detectTv].
///
/// Screen size alone can't tell: most 1080p TVs report 960 × 540, which is phone-sized.
bool isTv = false;

/// Call once at startup, before the first frame.
///
/// `flutter run --dart-define=TV=true` forces it on, for trying the TV behaviour on an emulator
/// whose system image isn't a TV one, or on desktop.
Future<void> detectTv() async {
  if (const bool.fromEnvironment('TV')) {
    isTv = true;
    return;
  }
  if (kIsWeb || !Platform.isAndroid) return;
  final info = await DeviceInfoPlugin().androidInfo;
  isTv = info.systemFeatures.contains('android.software.leanback');
}

/// Phones get the phone layout in any orientation. Decided by the screen's shorter side, so
/// turning a phone sideways (or the moment of landscape while leaving the player) never
/// switches to the TV and tablet layout. TVs never get it, however small they say they are.
bool isPhoneLayout(BuildContext context) => !isTv && MediaQuery.sizeOf(context).shortestSide < 600;

/// Which ways the screen may turn.
///
/// * Phones: the app stays upright, except the player, which turns with the phone
///   (following the phone's own rotation lock).
/// * Tablets, TVs and desktops: anything goes, everywhere.
abstract final class AppOrientation {
  /// Whether this device is a phone, by its screen's shorter side.
  static bool get _isPhone {
    if (isTv) return false;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.shortestSide < 600;
  }

  /// Call once at startup.
  static Future<void> init() => menus();

  /// Everything outside the player: upright on phones, with the status and navigation bars.
  /// TVs have no use for system bars, so they stay hidden there, as in other TV apps.
  static Future<void> menus() async {
    await SystemChrome.setEnabledSystemUIMode(
      isTv ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
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