import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/jellyfin/jellyfin_controller.dart';
import '../features/auth/login.dart';
import '../features/auth/profile_picker.dart';
import '../features/player/player.dart';
import 'app_shell.dart';

/// Every route in the app. Created on first use, after main() has set up [jellyfin].
final GoRouter appRouter = GoRouter(
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
              GoRoute(path: d.path, builder: (context, state) => d.screen(state), routes: d.routes),
            ],
          ),
      ],
    ),
  ],
);
