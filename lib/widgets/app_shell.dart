import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../screens/collection.dart';
import '../screens/genres.dart';
import '../screens/home.dart';
import '../screens/favorites.dart';
import '../screens/library.dart';
import '../screens/movie.dart';
import '../screens/person.dart';
import '../screens/search.dart';
import '../screens/series.dart';
import '../screens/settings.dart';
import '../theme/app_icons.dart';
import '../utils/focus_rows.dart';
import '../utils/jellyfin_controller.dart';
import 'app_logo.dart';
import 'nav_button.dart';
import 'profile_actions.dart';

/// Bottom-nav pages (phones). Order = bottom bar order = router branch order.
typedef AppDestination = ({
String label,
IconData Function(AppIconSet icons) icon, // looked up in the current icon style when drawn
String path,
Widget Function() screen,
List<RouteBase> routes, // sub-pages that keep this tab selected
});

final destinations = <AppDestination>[
  (
    label: 'Home',
    icon: (i) => i.home,
    path: '/home',
    screen: () => const HomeScreen(),
    routes: [
      GoRoute(
        path: 'favorites',
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: 'genres',
        builder: (context, state) => const GenresScreen(),
      ),
      GoRoute(
        path: 'library/:id',
        builder: (context, state) =>
            LibraryScreen(libraryId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'genre/:name',
        builder: (context, state) =>
            LibraryScreen(genre: state.pathParameters['name']!),
      ),
      GoRoute(
        path: 'collection/:id',
        builder: (context, state) =>
            CollectionScreen(collectionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'movie/:id',
        builder: (context, state) =>
            MovieScreen(movieId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'series/:id',
        builder: (context, state) =>
            SeriesScreen(seriesId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'person/:id',
        builder: (context, state) =>
            PersonScreen(personId: state.pathParameters['id']!),
      ),
    ],
  ),
  (
    label: 'Search',
    icon: (i) => i.search,
    path: '/search',
    screen: () => const SearchScreen(),
    routes: [
      GoRoute(
        path: 'person/:id',
        builder: (context, state) =>
            PersonScreen(personId: state.pathParameters['id']!),
      ),
    ],
  ),
  (
    label: 'Settings',
    icon: (i) => i.settings,
    path: '/settings',
    screen: () => const SettingsScreen(),
    routes: const [],
  ),
  (
    label: 'Profile',
    icon: (i) => i.profile,
    path: '/profile',
    screen: () => const SettingsScreen(initialTab: 'Account'),
    routes: const [],
  ),
];

const _phoneBreakpoint = 600.0;

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.location,
  });

  final StatefulNavigationShell navigationShell;
  final String location; // current path, e.g. /home/library/movies

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Each page lives in its own navigator, and arrow keys can't cross from a page into the
  // nav bar (or back) on their own. These two scopes let the shell move focus between them.
  final _navScope = FocusScopeNode(debugLabel: 'Nav bar');
  final _pageScope = FocusScopeNode(debugLabel: 'Page');

  @override
  void dispose() {
    _navScope.dispose();
    _pageScope.dispose();
    super.dispose();
  }

  void _goBranch(int index) => widget.navigationShell.goBranch(
    index,
    initialLocation: index == widget.navigationShell.currentIndex,
  );

  bool _isArrow(KeyEvent event, LogicalKeyboardKey key) =>
      (event is KeyDownEvent || event is KeyRepeatEvent) &&
          event.logicalKey == key;

  /// ↑ on a page: move up within the page if anything's there, otherwise to the nav bar.
  KeyEventResult _onPageKey(FocusNode node, KeyEvent event) {
    if (!_isArrow(event, LogicalKeyboardKey.arrowUp)) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus;
    final focusedContext = focused?.context;
    if (focused == null || focusedContext == null) {
      return KeyEventResult.ignored;
    }

    // Popouts, dialogs and pickers keep ↑ to themselves.
    if (ModalRoute.of(focusedContext) is PopupRoute) {
      return KeyEventResult.ignored;
    }

    if (!moveFocus(TraversalDirection.up)) _focusFirstOrRemembered(_navScope);
    return KeyEventResult.handled;
  }

  /// ↓ from the nav bar: back into the page, where you were.
  KeyEventResult _onNavKey(FocusNode node, KeyEvent event) {
    if (!_isArrow(event, LogicalKeyboardKey.arrowDown)) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) return KeyEventResult.ignored;

    if (!moveFocus(TraversalDirection.down)) {
      _focusFirstOrRemembered(_pageScope);
    }
    return KeyEventResult.handled;
  }

  /// Focuses whatever last had focus inside [scope], or else its first focusable item.
  void _focusFirstOrRemembered(FocusScopeNode scope) {
    final remembered = scope.focusedChild;
    if (remembered != null && remembered.canRequestFocus) {
      remembered.requestFocus();
    } else {
      scope.traversalDescendants
          .where((n) => n.canRequestFocus && !n.skipTraversal)
          .firstOrNull
          ?.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Rebuild when signing in or out, or when the icon style changes.
    listenable: Listenable.merge([jellyfin]),
    builder: (context, _) {
      // Signed out: the router is about to show the login page. Draw nothing in the meantime,
      // since every page here needs a connected client.
      if (!jellyfin.isConnected) return const SizedBox.shrink();

      final isPhone = MediaQuery.sizeOf(context).width < _phoneBreakpoint;

      return FScaffold(
        childPad: false,
        header: isPhone
            ? null
            : SafeArea(
          bottom: false,
          child: FocusScope(
            node: _navScope,
            onKeyEvent: _onNavKey, // ↓ back into the page
            child: _TopNavBar(location: widget.location),
          ),
        ),
        footer: isPhone
            ? SafeArea(
          top: false,
          child: FBottomNavigationBar(
            index: widget.navigationShell.currentIndex,
            onChange: _goBranch,
            children: [
              for (final d in destinations)
                FBottomNavigationBarItem(
                  icon: Icon(d.icon(appIcons), fill: 1),
                  label: Text(
                    d.label,
                    style: context.theme.typography.body.xs2,
                  ),
                ),
            ],
          ),
        )
            : null,
        child: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true, // the shell already made room for the keyboard; pages shouldn't do it again
          child: SafeArea(
            top: isPhone,
            bottom: !isPhone,
            child: FocusScope(
              node: _pageScope,
              onKeyEvent: _onPageKey, // ↑ to the nav bar when nothing's above
              child: widget.navigationShell,
            ),
          ),
        ),
      );
    },
  );
}

// ─── Top nav bar ─────────────────────────────────────────────────────────────

class _TopNavBar extends StatelessWidget {
  const _TopNavBar({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([jellyfin]),
    builder: (context, _) {
      final loc = location;
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: context.theme.colors.border),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const AppLogo(height: 28, variant: AppLogoVariant.auto),
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
                        icon: appIcons.home,
                        selected: loc == '/home',
                        onPress: () => context.go('/home'),
                      ),
                      NavButton(
                        label: 'Favorites',
                        icon: appIcons.favorite,
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
                          icon: appIcons.genres,
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
                    variant: loc.startsWith('/search')
                        ? .secondary
                        : .ghost, // highlighted while on the search page
                    onPress: () => context.go('/search'),
                    child: Icon(appIcons.search, fill: 1),
                  ),
                  FButton.icon(
                    variant: loc.startsWith('/settings') ? .secondary : .ghost,
                    onPress: () => context.go('/settings'),
                    child: Icon(appIcons.settings, fill: 1),
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