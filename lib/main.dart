import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/login.dart';
import 'screens/player.dart';
import 'widgets/app_shell.dart';
import 'widgets/profile_picker.dart';
import 'widgets/ui_scaler.dart';
import 'theme/theme.dart';
import 'theme/app_icons.dart';
import 'utils/theme_controller.dart';
import 'utils/font_controller.dart';
import 'utils/cast_controller.dart';
import 'utils/jellyfin_controller.dart';
import 'utils/orientation.dart';
import 'utils/focus_rows.dart';
import 'utils/home_layout.dart';
import 'utils/playback_settings.dart';
import 'utils/sync_play_controller.dart';

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

  jellyfin = JellyfinController();
  await jellyfin.load();

  // Chromecast: finds Chromecasts on the network so the player can offer a cast button.
  // Does nothing where casting isn't available (desktop, or devices without Play services).
  await castController.init();

  // Clean up in the background so it doesn't delay startup.
  unawaited(pruneFontCache([fontController.display, fontController.body, playbackSettings.subtitleFont]));

  syncPlay.openPlayer = (itemId) => _router.push('/play/$itemId?syncplay=1');

  runApp(const Application());
  WidgetsBinding.instance.addPostFrameCallback((_) => AppOrientation.init());
}

// Router configuration
final GoRouter _router = GoRouter(
  initialLocation: '/home',
  refreshListenable: jellyfin, // re-checks the redirect when you sign in or out
  redirect: (context, state) {
    final loc = state.matchedLocation;
    final atLogin = loc == '/login';
    final atProfiles = loc == '/profiles';

    // Changing user: wait on "Who's watching?" so no page shows the old user's things.
    if (jellyfin.switching) return atProfiles ? null : '/profiles';

    if (!jellyfin.isConnected) {
      if (atLogin || atProfiles) return null;
      // Others are saved on this device: let them pick. Nobody yet: sign in.
      return jellyfin.accounts.isEmpty ? '/login' : '/profiles';
    }

    // Signed in. Login is still allowed when adding another account (/login?add=1).
    if (atLogin && state.uri.queryParameters['add'] == '1') return null;
    if (atLogin || atProfiles) return '/home';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) => const NoTransitionPage(child: LoginScreen()),
    ),
    GoRoute(
      path: '/profiles',
      pageBuilder: (context, state) => const NoTransitionPage(child: ProfilePickerScreen()),
    ),
    GoRoute(
      path: '/play/:id',
      builder: (context, state) => PlayerScreen(
        itemId: state.pathParameters['id']!,
        queue: state.uri.queryParameters['queue']?.split(',') ?? const [],
        fromGroup: state.uri.queryParameters['syncplay'] == '1',
      ),
    ),
    StatefulShellRoute(
      // No animation in or out: when switching users, the shell is taken down and put back
      // up in quick succession, and two copies animating at once would share its key.
      pageBuilder: (context, state, navigationShell) => NoTransitionPage(
        child: AppShell(
          navigationShell: navigationShell,
          location: state.uri.path,
          tab: state.uri.queryParameters['tab'],
        ),
      ),
      navigatorContainerBuilder: (context, navigationShell, children) => IndexedStack(
        index: navigationShell.currentIndex,
        children: [
          for (final (i, child) in children.indexed)
            ExcludeFocus(
              excluding: i != navigationShell.currentIndex,
              child: TickerMode(enabled: i == navigationShell.currentIndex, child: child),
            ),
        ],
      ),
      branches: [
        for (final d in destinations)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: d.path,
                builder: (context, state) => d.screen(state),
                routes: d.routes,
              ),
            ],
          ),
      ],
    ),
  ],
);

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
        routerConfig: _router,
      );
    },
  );
}