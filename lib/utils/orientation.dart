import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class AppOrientation {
  static bool _isPhone = false;

  /// Works out whether this is a phone, then applies the menu orientation.
  static Future<void> init() async {
    _isPhone = await _detectPhone();
    await menus();
  }

  /// Menus: phones in portrait, with the status bar and system buttons visible.
  static Future<void> menus() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // An empty list means "any orientation" for tablets, TVs and desktop.
    await SystemChrome.setPreferredOrientations(
      _isPhone ? [DeviceOrientation.portraitUp] : [],
    );
  }

  /// Video: phones in landscape (either way round), full screen with the system bars hidden.
  static Future<void> player() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_isPhone) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  static Future<bool> _detectPhone() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return false;

    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final shortestSide =
        (view.physicalSize / view.devicePixelRatio).shortestSide;
    if (shortestSide == 0 || shortestSide >= 600) return false;

    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.systemFeatures.contains('android.software.leanback'))
        return false; // Android TV
    }
    return true;
  }
}
