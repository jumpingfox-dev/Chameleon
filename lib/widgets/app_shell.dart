import 'package:chameleon/widgets/profile_actions.dart';
import 'package:forui/forui.dart';
import 'package:forui_phosphor/forui_phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../screens/collection.dart';
import '../screens/genres.dart';
import '../screens/home.dart';
import '../screens/favorites.dart';
import '../screens/library.dart';
import '../screens/movie.dart';
import '../screens/person.dart';
import '../screens/profile.dart';
import '../screens/search.dart';
import '../screens/series.dart';
import '../screens/settings.dart';
import '../utils/jellyfin_controller.dart';
import 'app_logo.dart';
import 'nav_button.dart';

/// Bottom-nav pages (phones). Order = bottom bar order = router branch order.
typedef AppDestination = ({
  String label,
  IconData icon,
  String path,
  Widget Function() screen,
  List<RouteBase> routes, // sub-pages that keep this tab selected
});

final destinations = <AppDestination>[
  (
    label: 'Home',
    icon: FPhosphorIcons.house,
    path: '/home',
    screen: () => const HomeScreen(),
    routes: [
      GoRoute(path: 'favorites', builder: (context, state) => const FavoritesScreen()),
      GoRoute(path: 'genres', builder: (context, state) => const GenresScreen()),
      GoRoute(
        path: 'library/:id',
        builder: (context, state) => LibraryScreen(libraryId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'genre/:name',
        builder: (context, state) => LibraryScreen(genre: state.pathParameters['name']!),
      ),
      GoRoute(
        path: 'collection/:id',
        builder: (context, state) => CollectionScreen(collectionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'movie/:id',
        builder: (context, state) => MovieScreen(movieId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'series/:id',
        builder: (context, state) => SeriesScreen(seriesId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'person/:id',
        builder: (context, state) => PersonScreen(personId: state.pathParameters['id']!),
      ),
    ],
  ),
  (
    label: 'Search',
    icon: FPhosphorIcons.magnifyingGlass,
    path: '/search',
    screen: () => const SearchScreen(),
    routes: [
      GoRoute(
        path: 'person/:id',
        builder: (context, state) => PersonScreen(personId: state.pathParameters['id']!),
      ),
    ],
  ),
  (label: 'Settings', icon: FPhosphorIcons.gear, path: '/settings', screen: () => const SettingsScreen(), routes: const []),
  (label: 'Profile', icon: FPhosphorIcons.user, path: '/profile', screen: () => const ProfileScreen(), routes: const []),
];

const _phoneBreakpoint = 600.0;

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell, required this.location});

  final StatefulNavigationShell navigationShell;
  final String location; // current path, e.g. /home/library/movies

  void _goBranch(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: jellyfin,
    builder: (context, _) {
      // Signed out: the router is about to show the login page. Draw nothing in the meantime,
      // since every page here needs a connected client.
      if (!jellyfin.isConnected) return const SizedBox.shrink();

      final isPhone = MediaQuery.sizeOf(context).width < _phoneBreakpoint;

      return FScaffold(
        childPad: false,
        header: isPhone ? null : SafeArea(bottom: false, child: _TopNavBar(location: location)),
        footer: isPhone
            ? SafeArea(
          top: false,
          child: FBottomNavigationBar(
            index: navigationShell.currentIndex,
            onChange: _goBranch,
            children: [
              for (final d in destinations)
                FBottomNavigationBarItem(icon: Icon(d.icon), label: Text(d.label, style: context.theme.typography.body.xs2)),
            ],
          ),
        )
            : null,
        child: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true, // the shell already made room for the keyboard; pages shouldn't do it again
          child: SafeArea(top: isPhone, bottom: !isPhone, child: navigationShell),
        ),
      );
    }
  );
}

// ─── Top nav bar ─────────────────────────────────────────────────────────────

class _TopNavBar extends StatelessWidget {
  const _TopNavBar({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: jellyfin,
    builder: (context, _) {
      final loc = location;
      return DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.theme.colors.border))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const AppLogo(height: 28),
              const SizedBox(width: 8),

              // Home + libraries + Genres, then search filling any leftover space
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 4,
                    children: [
                      NavButton(
                        label: 'Home',
                        icon: FPhosphorIcons.house,
                        selected: loc == '/home',
                        onPress: () => context.go('/home'),
                      ),
                      NavButton(
                        label: 'Favorites',
                        icon: FPhosphorIcons.heart,
                        selected: loc == '/home/favorites',
                        onPress: () => context.go('/home/favorites'),
                      ),
                      for (final lib in jellyfin.libraries)
                        NavButton(
                          label: lib.name,
                          icon: libraryIcon(lib.collectionType),
                          selected: loc == '/home/library/${lib.id}',
                          onPress: () => context.go('/home/library/${lib.id}'),
                        ),
                      if (jellyfin.genres.isNotEmpty)
                        NavButton(
                          label: 'Genres',
                          icon: FPhosphorIcons.tag,
                          selected: loc.startsWith('/home/genre'),
                          onPress: () => context.go('/home/genres'),
                        ),
                    ],
                  ),
                ),
              ),

              // Right-hand actions: search, settings, profile
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6, // gap between each item, in pixels
                children: [
                  FButton.icon(
                    variant: loc.startsWith('/search') ? .secondary : .ghost, // highlighted while on the search page
                    onPress: () => context.go('/search'),
                    child: const Icon(FPhosphorIcons.magnifyingGlass),
                  ),
                  FButton.icon(
                    variant: loc.startsWith('/settings') ? .secondary : .ghost,
                    onPress: () => context.go('/settings'),
                    child: const Icon(FPhosphorIcons.gear),
                  ),
                  FTappable(
                    onPress: () => context.go('/profile'),
                    child: const UserAvatar(),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}