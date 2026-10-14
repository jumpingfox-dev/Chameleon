import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:media_kit/media_kit.dart';

import 'app/router.dart';
import 'app/splash.dart';
import 'app/ui_scaler.dart';
import 'core/cast/cast_controller.dart';
import 'core/cast/sync_play_controller.dart';
import 'core/focus/focus_rows.dart';
import 'core/jellyfin/jellyfin_controller.dart';
import 'core/platform/orientation.dart';
import 'core/storage/app_cache.dart';
import 'core/storage/storage.dart';
import 'features/home/home_layout.dart';
import 'features/player/playback_settings.dart';
import 'theme/app_icons.dart';
import 'theme/font_controller.dart';
import 'theme/theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  // Keeps the system splash up while everything below loads, instead of a blank first frame.
  FlutterNativeSplash.preserve(widgetsBinding: WidgetsFlutterBinding.ensureInitialized());
  await detectTv(); // before the first frame, which already picks phone or TV layout
  if (isTv) {
    // No touchscreen, so always show where focus is. (Flutter otherwise waits for a key it's
    // sure came from a hardware keyboard, and some remotes don't look like one.)
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    // A TV's system splash is just the background (Android 12+ only fits a small icon), so
    // show the full wordmark while loading.
    runApp(const TvSplash());
    FlutterNativeSplash.remove();
  }
  MediaKit.ensureInitialized();
  // Keep more posters in memory so scrolling back doesn't re-download them.
  PaintingBinding.instance.imageCache
    ..maximumSize = 1500
    ..maximumSizeBytes = 200 << 20; // 200 MB (the default is 100 MB)
  storage = await Storage.open(); // before anything that reads a setting
  unawaited(storage.pruneCache(DateTime.now().subtract(AppCache.keepFor)));
  themeController = await ThemeController.load();
  fontController = await FontController.load();
  iconController = await IconController.load();
  playbackSettings = await PlaybackSettings.load();
  homeLayout = await HomeLayoutController.load();

  jellyfin = JellyfinController();
  await jellyfin.load();

  // Chromecast: finds Chromecasts on the network so the player can offer a cast button.
  // Does nothing where casting isn't available (desktop, or devices without Play services).
  await castController.init();

  // Clean up in the background so it doesn't delay startup.
  unawaited(pruneFontCache([fontController.display, fontController.body, playbackSettings.subtitleFont]));

  syncPlay.openPlayer = (itemId) => appRouter.push('/play/$itemId?syncplay=1');

  runApp(const Application());
  FlutterNativeSplash.remove();
  WidgetsBinding.instance.addPostFrameCallback((_) => AppOrientation.init());
}

class Application extends StatelessWidget {
  const Application({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([themeController, fontController, iconController]),
    builder: (context, _) {
      final theme = buildTheme(
        themeController.value.colors,
        displayFont: fontController.display,
        bodyFont: fontController.body,
      );

      return MaterialApp.router(
        debugShowCheckedModeBanner: false,
        scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
        theme: theme,
        builder: (context, child) => TextFieldArrowEscape(
          child: RowFocusNavigation(child: UiScaler(child: child!)),
        ),
        routerConfig: appRouter,
      );
    },
  );
}
