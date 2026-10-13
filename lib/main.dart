import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:media_kit/media_kit.dart';

import 'app/router.dart';
import 'app/ui_scaler.dart';
import 'core/cast/cast_controller.dart';
import 'core/cast/sync_play_controller.dart';
import 'core/focus/focus_rows.dart';
import 'core/jellyfin/jellyfin_controller.dart';
import 'core/platform/orientation.dart';
import 'features/home/home_layout.dart';
import 'features/player/playback_settings.dart';
import 'theme/app_icons.dart';
import 'theme/font_controller.dart';
import 'theme/theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Keep more posters in memory so scrolling back doesn't re-download them.
  PaintingBinding.instance.imageCache
    ..maximumSize = 1500
    ..maximumSizeBytes = 200 << 20; // 200 MB (the default is 100 MB)
  themeController = await ThemeController.load();
  fontController = await FontController.load();
  iconController = await IconController.load();
  playbackSettings = await PlaybackSettings.load();
  homeLayout = await HomeLayoutController.load();
  await detectTv(); // before the first frame, which already picks phone or TV layout

  jellyfin = JellyfinController();
  await jellyfin.load();

  // Chromecast: finds Chromecasts on the network so the player can offer a cast button.
  // Does nothing where casting isn't available (desktop, or devices without Play services).
  await castController.init();

  // Clean up in the background so it doesn't delay startup.
  unawaited(pruneFontCache([fontController.display, fontController.body, playbackSettings.subtitleFont]));

  syncPlay.openPlayer = (itemId) => appRouter.push('/play/$itemId?syncplay=1');

  runApp(const Application());
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
        supportedLocales: const [
          Locale('en', 'US'),
          ...FLocalizations.supportedLocales,
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme.toApproximateMaterialTheme(),
        builder: (context, child) => TextFieldArrowEscape(
          child: RowFocusNavigation(
            child: UiScaler(
              child: FTheme(
                data: theme,
                child: FToaster(child: FTooltipGroup(child: child!)),
              ),
            ),
          ),
        ),
        routerConfig: appRouter,
      );
    },
  );
}