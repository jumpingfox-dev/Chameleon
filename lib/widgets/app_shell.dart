import 'package:forui/forui.dart';
import 'package:forui_phosphor/forui_phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../screens/home.dart';
import '../screens/library.dart';
import '../screens/profile.dart';
import '../screens/search.dart';
import '../screens/settings.dart';
import '../utils/jellyfin_controller.dart';
import 'app_logo.dart';

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
    GoRoute(
      path: 'library/:id',
      builder: (context, state) => LibraryScreen(libraryId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: 'genre/:name',
      builder: (context, state) => LibraryScreen(genre: state.pathParameters['name']!),
    ),
  ],
  ),
  (label: 'Search', icon: FPhosphorIcons.magnifyingGlass, path: '/search', screen: () => const SearchScreen(), routes: const []),
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
  Widget build(BuildContext context) {
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
              FBottomNavigationBarItem(icon: Icon(d.icon), label: Text(d.label)),
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
}

// ─── Top nav bar ─────────────────────────────────────────────────────────────

class _TopNavBar extends StatefulWidget {
  const _TopNavBar({required this.location});

  final String location;

  @override
  State<_TopNavBar> createState() => _TopNavBarState();
}

class _TopNavBarState extends State<_TopNavBar> {
  bool _searching = false;

  IconData _libraryIcon(String? type) => switch (type) {
    'movies' => FPhosphorIcons.filmSlate,
    'tvshows' => FPhosphorIcons.television,
    'music' => FPhosphorIcons.musicNotes,
    _ => FPhosphorIcons.folder,
  };

  Widget _navButton({required String label, IconData? icon, required bool selected, required VoidCallback onPress}) =>
      FButton(
        variant: selected ? .secondary : .ghost,
        size: .sm,
        mainAxisSize: .min,
        onPress: onPress,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [if (icon != null) Icon(icon, size: 16), Text(label)],
        ),
      );

  void _submitSearch(String query) {
    final q = query.trim();
    setState(() => _searching = false);
    context.go(q.isEmpty ? '/search' : '/search?q=${Uri.encodeQueryComponent(q)}');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: jellyfin,
    builder: (context, _) {
      final loc = widget.location;
      final resizeKey = ValueKey(MediaQuery.sizeOf(context));
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
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      ConstrainedBox(
                        // While searching, the nav buttons can use at most 60% of the space,
                        // so the search field always gets at least 40%.
                        constraints: BoxConstraints(
                          maxWidth: _searching ? constraints.maxWidth * 0.6 : constraints.maxWidth,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            spacing: 6,
                            children: [
                              _navButton(
                                label: 'Home',
                                icon: FPhosphorIcons.house,
                                selected: loc == '/home',
                                onPress: () => context.go('/home'),
                              ),
                              for (final lib in jellyfin.libraries)
                                _navButton(
                                  label: lib.name,
                                  icon: _libraryIcon(lib.collectionType),
                                  selected: loc == '/home/library/${lib.id}',
                                  onPress: () => context.go('/home/library/${lib.id}'),
                                ),
                              if (jellyfin.genres.isNotEmpty)
                                _GenresMenu(key: resizeKey, genres: jellyfin.genres, location: loc),
                            ],
                          ),
                        ),
                      ),
                      if (_searching)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: FTextField(
                              autofocus: true,
                              hint: 'Search',
                              onSubmit: _submitSearch,
                            ),
                          ),
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
                    variant: .ghost,
                    onPress: () => setState(() => _searching = !_searching),
                    child: Icon(_searching ? FPhosphorIcons.x : FPhosphorIcons.magnifyingGlass),
                  ),
                  FButton.icon(
                    variant: loc.startsWith('/settings') ? .secondary : .ghost,
                    onPress: () => context.go('/settings'),
                    child: const Icon(FPhosphorIcons.gear),
                  ),
                  _ProfileMenu(key: resizeKey),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _GenresMenu extends StatelessWidget {
  const _GenresMenu({super.key, required this.genres, required this.location});

  final List<String> genres;
  final String location;

  @override
  Widget build(BuildContext context) => FPopover(
    control: const .managed(),
    popoverBuilder: (context, controller) => IntrinsicWidth(
      // Sized to its contents, no wider than it needs to be.
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              // Long genre lists scroll instead of running off the screen.
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 4,
                  children: [
                    for (final genre in genres)
                      FButton(
                        variant: location == '/home/genre/${Uri.encodeComponent(genre)}' ? .secondary : .ghost,
                        size: .sm,
                        mainAxisAlignment: .start,
                        onPress: () {
                          controller.hide();
                          context.go('/home/genre/${Uri.encodeComponent(genre)}');
                        },
                        child: Row(
                          spacing: 8,
                          children: [Text(genre)],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    builder: (context, controller, _) => FButton(
      variant: location.startsWith('/home/genre/') ? .secondary : .ghost,
      size: .sm,
      mainAxisSize: .min,
      onPress: controller.toggle,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [Text('Genres'), Icon(FPhosphorIcons.caretDown, size: 14)],
      ),
    ),
  );
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({super.key});

  @override
  Widget build(BuildContext context) => FPopover(
    control: const .managed(),
    childAnchor: Alignment.bottomRight,   // attach to the avatar's bottom-right corner…
    popoverAnchor: Alignment.topRight,    // …by the popover's top-right corner
    overflow: FPortalOverflow.allow, // don't "correct" using the unscaled window size
    popoverBuilder: (context, controller) => IntrinsicWidth(
      // Sized to its contents, no wider than it needs to be.
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Padding(
            //   padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            //   child: Text(jellyfin.userName ?? 'Not signed in', style: context.theme.typography.display.md),
            // ),
            for (final (label, icon, onPress) in <(String, IconData, VoidCallback)>[
              ('Profile', FPhosphorIcons.user, () => context.go('/profile')),
              ('Add User', FPhosphorIcons.userPlus, () => context.go('/settings')),
              if (jellyfin.isConnected) ('Sign out', FPhosphorIcons.signOut, jellyfin.signOut),
            ])
            FButton(
              variant: .ghost,
              size: .sm,
              mainAxisAlignment: .start,
              onPress: () {
                controller.hide();
                onPress();
              },
              child: Row(
                spacing: 8,
                children: [Icon(icon, size: 16), Text(label)],
              ),
            ),
          ],
        ),
      ),
    ),
    builder: (context, controller, _) => FTappable(
      onPress: controller.toggle,
      child: jellyfin.userImage != null
          ? FAvatar(image: jellyfin.userImage!, fallback: Text(jellyfin.initials))
          : FAvatar.raw(child: Text(jellyfin.initials)),
    ),
  );
}