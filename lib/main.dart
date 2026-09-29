import 'dart:async';

import 'package:chameleon/utils/home_layout.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/login.dart';
import 'screens/player.dart';
import 'widgets/app_shell.dart';
import 'widgets/ui_scaler.dart';
import 'theme/theme.dart';
import 'utils/theme_controller.dart';
import 'utils/font_controller.dart';
import 'utils/jellyfin_controller.dart';
import 'utils/orientation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Keep more posters in memory so scrolling back doesn't re-download them.
  PaintingBinding.instance.imageCache
    ..maximumSize = 1500
    ..maximumSizeBytes = 200 << 20; // 200 MB (the default is 100 MB)
  themeController = await ThemeController.load();
  fontController = await FontController.load();
  homeLayout = await HomeLayoutController.load();

  jellyfin = JellyfinController();
  await jellyfin.load();

  // Clean up in the background so it doesn't delay startup.
  unawaited(pruneFontCache([fontController.display, fontController.body]));

  runApp(const Application());
  WidgetsBinding.instance.addPostFrameCallback((_) => AppOrientation.init());
}

// Router configuration
final GoRouter _router = GoRouter(
  initialLocation: '/home',
  refreshListenable: jellyfin, // re-checks the redirect when you sign in or out
  redirect: (context, state) {
    final atLogin = state.matchedLocation == '/login';
    if (!jellyfin.isConnected) return atLogin ? null : '/login';
    if (atLogin) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/play/:id', builder: (context, state) => PlayerScreen(itemId: state.pathParameters['id']!),),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell, location: state.uri.path),
      branches: [
        for (final d in destinations)
          StatefulShellBranch(
            routes: [GoRoute(path: d.path, builder: (context, state) => d.screen(), routes: d.routes)],
          ),
      ],
    ),
  ],
);

class Application extends StatelessWidget {
  const Application({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([themeController, fontController]),
    builder: (context, _) {
      final theme = buildTheme(
        themeController.value.colors,
        displayFont: fontController.display,
        bodyFont: fontController.body,
      );

      return MaterialApp.router(
        debugShowCheckedModeBanner: false,
        supportedLocales: const [
          Locale('en', 'US'),
          ...FLocalizations.supportedLocales,
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme.toApproximateMaterialTheme(),
        builder: (context, child) => UiScaler(
          child: FTheme(
            data: theme,
            child: FToaster(
              child: FTooltipGroup(child: child!),
            ),
          ),
        ),
        routerConfig: _router,
      );
    },
  );
}