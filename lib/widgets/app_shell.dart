import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../screens/detail_screens.dart';
import '../screens/genres.dart';
import '../screens/home.dart';
import '../screens/favorites.dart';
import '../screens/library.dart';
import '../screens/search.dart';
import '../screens/settings.dart';
import '../theme/app_icons.dart';
import '../theme/tappable_states.dart';
import '../utils/focus_rows.dart';
import '../utils/home_layout.dart';
import '../utils/jellyfin_controller.dart';
import '../utils/orientation.dart';
import 'app_logo.dart';
import 'profile_actions.dart';
import 'profile_picker.dart';

part 'app_sidebar.dart';

/// Bottom-nav pages (phones). Order = bottom bar order = router branch order.
typedef AppDestination = ({
String label,
IconData Function(AppIconSet icons) icon, // looked up in the current icon style when drawn
String path,
Widget Function(GoRouterState state) screen, // state: e.g. the ?tab= on Settings
List<RouteBase> routes, // sub-pages that keep this tab selected
});

final destinations = <AppDestination>[
  (
  label: 'Home',
  icon: (i) => i.home,
  path: '/home',
  screen: (_) => const HomeScreen(),
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
  screen: (state) => SearchScreen(query: state.uri.queryParameters['q']),
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
  screen: (state) => SettingsScreen(initialTab: state.uri.queryParameters['tab']),
  routes: const [],
  ),
  (
  label: 'Profile',
  icon: (i) => i.profile,
  path: '/profile',
  screen: (state) => SettingsScreen(initialTab: state.uri.queryParameters['tab'] ?? 'Account'),
  routes: const [],
  ),
];

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.location,
    this.tab,
  });

  final StatefulNavigationShell navigationShell;
  final String location; // current path, e.g. /home/library/movies
  final String? tab; // the ?tab= on Settings, e.g. Playback

  @override
  State<AppShell> createState() => _AppShellState();
}

/// The sidebar's width while it shows just icons, and while it's open with labels.
const _railWidth = 64.0;
const _openWidth = 264.0;

/// Side padding for the sidebar's list (forui's default is 16, which makes the closed rail
/// chunky). The header and footer use the same, so everything lines up down the middle.
const _sidePadding = 8.0;

class _AppShellState extends State<AppShell> {
  // Each page lives in its own navigator, and arrow keys can't cross from a page into the
  // sidebar (or back) on their own. These two scopes let the shell move focus between them.
  final _navScope = FocusScopeNode(debugLabel: 'Sidebar');
  final _pageScope = FocusScopeNode(debugLabel: 'Page');

  /// The sidebar opens while it has focus (remote, keyboard) or the mouse is over it.
  final _hovering = ValueNotifier(false);
  late final _sidebarOpen = Listenable.merge([_navScope, _hovering]);

  /// How many times the sidebar has closed. Every section's key includes this, so anything
  /// unfolded folds back up after each close. Counted on close rather than open: by then
  /// nothing in the sidebar has focus, so rebuilding its items can't lose your place.
  int _closings = 0;
  bool _wasOpen = false;

  /// Bumped for one label each time [_enterSidebar] needs that section open to reach a page
  /// inside it — its own section may be sitting collapsed from an earlier visit, if the page
  /// became "active" by a route pushed from outside the sidebar (a Genre button on a movie's
  /// details, say). A section's key includes its own entry here, so forui always builds it
  /// fresh with [FSidebarItem.initiallyExpanded] true when this changes. Pressing a section
  /// to fold or unfold it by hand never touches this, so that keeps its usual animation.
  final _forceOpen = <String, int>{};

  /// A focus node for each sidebar entry, by name ('Settings', 'Settings/Playback', ...),
  /// so ← from a page can land on the entry for where you are. Each entry keeps its own node
  /// for good; nothing is handed from one entry to another.
  final _navNodes = <String, FocusNode>{};
  FocusNode _navNode(String id) =>
      _navNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'Sidebar: $id'));

  /// The sidebar entries for where you are: its link or section, and the page inside that
  /// section, if there is one.
  (String, String?) get _here {
    final loc = widget.location;
    final last = loc.split('/').last;
    if (loc.startsWith('/search')) return ('Search', null);
    if (loc == '/home/favorites') return ('Favorites', null);
    if (loc.startsWith('/home/library/')) return ('Libraries', 'Libraries/$last');
    if (loc == '/home/genres') return ('Genres', 'Genres/All');
    if (loc.startsWith('/home/genre/')) return ('Genres', 'Genres/$last');
    if (loc == '/settings') return ('Settings', 'Settings/${widget.tab ?? settingsTabLabels.first}');
    if (loc == '/profile') return ('Settings', 'Settings/${widget.tab ?? 'Account'}');
    return ('Home', null); // home, and the pages opened from it (a movie, a show, ...)
  }

  /// The bottom nav bar, measured after each frame so pages know where it starts.
  final _footerKey = GlobalKey();
  double _footerHeight = 0;

  void _measureFooter() {
    final box = _footerKey.currentContext?.findRenderObject();
    final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
    if (mounted && height != _footerHeight) setState(() => _footerHeight = height);
  }

  @override
  void dispose() {
    _navScope.dispose();
    _pageScope.dispose();
    _hovering.dispose();
    for (final node in _navNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _goBranch(int index) => widget.navigationShell.goBranch(
    index,
    initialLocation: index == widget.navigationShell.currentIndex,
  );

  bool _isArrow(KeyEvent event, LogicalKeyboardKey key) =>
      (event is KeyDownEvent || event is KeyRepeatEvent) &&
          event.logicalKey == key;

  /// ← on a page: move left within the page if anything's there, otherwise into the sidebar.
  KeyEventResult _onPageKey(FocusNode node, KeyEvent event) {
    if (!_isArrow(event, LogicalKeyboardKey.arrowLeft)) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus;
    final focusedContext = focused?.context;
    if (focused == null || focusedContext == null) {
      return KeyEventResult.ignored;
    }

    // Popouts, dialogs and pickers keep ← to themselves.
    if (ModalRoute.of(focusedContext) is PopupRoute) {
      return KeyEventResult.ignored;
    }

    // In a text field, ← moves the cursor until it reaches the start.
    final editable = focusedContext.findAncestorStateOfType<EditableTextState>();
    if (editable != null) {
      final selection = editable.textEditingValue.selection;
      if (!selection.isCollapsed || selection.baseOffset > 0) {
        return KeyEventResult.ignored;
      }
    }

    if (!moveFocus(TraversalDirection.left)) _enterSidebar();
    return KeyEventResult.handled;
  }

  /// → from the sidebar: back into the page, where you were.
  KeyEventResult _onNavKey(FocusNode node, KeyEvent event) {
    if (!_isArrow(event, LogicalKeyboardKey.arrowRight)) {
      return KeyEventResult.ignored;
    }
    // In the search box, → moves the cursor until it reaches the end.
    final editable = FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>();
    if (editable != null) {
      final value = editable.textEditingValue;
      if (!value.selection.isCollapsed || value.selection.baseOffset < value.text.length) {
        return KeyEventResult.ignored;
      }
    }
    _focusFirstOrRemembered(_pageScope);
    return KeyEventResult.handled;
  }

  /// Into the sidebar, on the entry for where you are: the page itself (Settings › Appearance)
  /// if it's in a section, otherwise its link.
  void _enterSidebar() {
    final (entry, page) = _here;
    final node = _navNodes[entry];
    if (node == null || node.context == null) {
      _focusFirstOrRemembered(_navScope);
      return;
    }
    if (page != null) {
      // Force the section open. It might already be (because it's the one you're on), but it
      // might just as well be sitting collapsed from an earlier visit, if this page became
      // "active" by a route pushed from outside the sidebar (a Genre button on a movie's
      // details, say) rather than by pressing into the sidebar.
      setState(() => _forceOpen[entry] = (_forceOpen[entry] ?? 0) + 1);
    }
    // The section first: that opens the sidebar. Its page only appears once the sidebar has
    // finished widening and the section has finished unfolding, so wait for it.
    node.requestFocus();
    if (page != null) _focusSidebarPage(node, page);
  }

  /// Waits for [page]'s entry to become focusable — the sidebar widening and the section
  /// unfolding both take a moment — then focuses it. Gives up quietly if you've already
  /// moved on, or if it never becomes focusable at all.
  void _focusSidebarPage(FocusNode sectionNode, String page, [int attempt = 0]) {
    if (!mounted || FocusManager.instance.primaryFocus != sectionNode) return; // moved on
    final pageNode = _navNodes[page];
    if (pageNode != null && pageNode.canRequestFocus) {
      pageNode.requestFocus();
      if (pageNode.context case final context?) Scrollable.ensureVisible(context, alignment: 0.5);
      return;
    }
    if (attempt >= 20) return; // ~1 s: give up rather than wait forever
    Future.delayed(const Duration(milliseconds: 50), () => _focusSidebarPage(sectionNode, page, attempt + 1));
  }

  /// After picking a page in the sidebar: focus that page's first item, not wherever you were
  /// on the last page. Pages that load their content first (a library, a genre) have nothing
  /// to focus at the start, so it checks again for a moment.
  void _focusNewPage([int attempt = 0]) {
    if (!mounted) return;
    // You've already moved on (into the page, or back into the sidebar): leave focus be.
    if (attempt > 0 && (_pageScope.hasFocus || _navScope.hasFocus)) return;

    final first = firstFocusable(_pageScope, mainOnly: true) ??
        (attempt >= 20 ? firstFocusable(_pageScope) : null); // ~2 s, then anything
    if (first != null) {
      first.requestFocus();
      if (first.context case final context?) Scrollable.ensureVisible(context);
      return;
    }
    // Close the sidebar while the page loads, without leaving focus somewhere ← can't reach:
    // unlike _navScope.unfocus() (which moves it to the scope above both scopes), requesting
    // _pageScope keeps it at or below the scope _onPageKey listens on.
    if (attempt == 0) _pageScope.requestFocus();
    if (attempt >= 40) return; // nothing to focus on this page at all
    Future.delayed(const Duration(milliseconds: 100), () => _focusNewPage(attempt + 1));
  }

  /// Focuses whatever last had focus inside [scope] if it's still on the page you're looking
  /// at, or else that page's first item.
  void _focusFirstOrRemembered(FocusScopeNode scope) {
    final remembered = _rememberedIn(scope);
    if (remembered != null) {
      remembered.requestFocus();
    } else {
      firstFocusable(scope)?.requestFocus();
    }
  }

  /// The item last focused inside [scope], following its scopes down (each page keeps its
  /// own), or null if there isn't one or it's on a page that's now hidden.
  FocusNode? _rememberedIn(FocusScopeNode scope) {
    FocusNode? node = scope.focusedChild;
    while (node is FocusScopeNode && node.focusedChild != null) {
      node = node.focusedChild;
    }
    if (node == null || node is FocusScopeNode || !node.canRequestFocus) return null;
    return isOnTopPage(node) ? node : null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Rebuild when signing in or out.
    listenable: jellyfin,
    builder: (context, _) {
      // Signed out: the router is about to show the login page. Draw nothing in the meantime,
      // since every page here needs a connected client.
      if (!jellyfin.isConnected) return const SizedBox.shrink();

      final isPhone = isPhoneLayout(context);

      return FScaffold(
        childPad: false,
        footer: isPhone
            ? SafeArea(
          key: _footerKey,
          top: false,
          child: FBottomNavigationBar(
            index: widget.navigationShell.currentIndex,
            onChange: _goBranch,
            children: [
              for (final d in destinations)
                FBottomNavigationBarItem(
                  icon: Icon(
                    d.icon(appIcons),
                    fill: 1,
                    size: 26,
                    semanticLabel: d.label,
                  ),
                ),
            ],
          ),
        )
            : null,
        child: Builder(
          builder: (context) {
            Widget page = MediaQuery.removeViewInsets(
              context: context,
              removeBottom: true, // the shell already made room for the keyboard; pages shouldn't do it again
              child: SafeArea(
                bottom: !isPhone,
                left: false,
                right: false,
                child: FocusScope(
                  node: _pageScope,
                  onKeyEvent: isPhone ? null : _onPageKey, // ← into the sidebar when nothing's left of you
                  child: widget.navigationShell,
                ),
              ),
            );

            // Phones: dropdowns and menus decide whether to open up or down by measuring the
            // screen. Tell pages the screen ends where the bottom nav bar starts, so nothing
            // opens behind the bar: it flips upwards (or slides) instead. The bar is measured
            // after each frame rather than during layout, which the page navigators can't handle.
            if (isPhone) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _measureFooter());
              final screen = MediaQuery.sizeOf(context);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(screen.width, screen.height - _footerHeight),
                ),
                child: page,
              );
            }

            // Wider screens: the page sits right of the icon rail, and the sidebar opens over
            // it rather than pushing it aside, so nothing on the page moves.
            final inset = MediaQuery.paddingOf(context).left; // camera cutout, if any
            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(left: inset + _railWidth),
                  // The sidebar already clears the cutout, so pages don't add room for it again.
                  child: MediaQuery.removePadding(context: context, removeLeft: true, child: page),
                ),
                // Dims the page while the sidebar is open, like the popups on the detail pages.
                // Selecting the dimmed page closes it and goes back to where you were.
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: _sidebarOpen,
                    builder: (context, _) {
                      final open = _hovering.value || _navScope.hasFocus;
                      return IgnorePointer(
                        ignoring: !open,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _hovering.value = false;
                            _focusFirstOrRemembered(_pageScope);
                          },
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: open ? 1 : 0,
                            child: ColoredBox(color: context.theme.colors.barrier),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: MouseRegion(
                    onEnter: (_) => _hovering.value = true,
                    onExit: (_) => _hovering.value = false,
                    child: ListenableBuilder(
                      listenable: _sidebarOpen,
                      builder: (context, _) {
                        final open = _hovering.value || _navScope.hasFocus;
                        if (_wasOpen && !open) {
                          _closings++;
                          _forceOpen.clear(); // moot now: the next open starts fresh anyway
                        }
                        _wasOpen = open;
                        return FocusScope(
                          node: _navScope,
                          onKeyEvent: _onNavKey, // → back into the page
                          child: _Sidebar(
                            open: open,
                            closings: _closings,
                            forceOpen: _forceOpen,
                            location: widget.location,
                            tab: widget.tab,
                            // Closes the sidebar and moves to the new page's first item, once it has
                            // been built.
                            onLeave: () {
                              _hovering.value = false;
                              WidgetsBinding.instance.addPostFrameCallback((_) => _focusNewPage());
                            },
                            nodeFor: _navNode,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
