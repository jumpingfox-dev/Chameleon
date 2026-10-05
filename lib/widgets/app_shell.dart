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

// TODO(cleanup): the sidebar is half this file; move it into a part of its own
// ─── Sidebar ─────────────────────────────────────────────────────────────────

/// Wider screens' navigation: a rail of icons down the left side that opens out, with labels,
/// when it gets focus or the mouse moves over it.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.open,
    required this.closings,
    required this.forceOpen,
    required this.location,
    required this.tab,
    required this.onLeave,
    required this.nodeFor,
  });

  final bool open;
  final int closings; // how many times it has closed; folds the sections back up
  final Map<String, int> forceOpen; // see _AppShellState._forceOpen
  final String location;
  final String? tab;
  final VoidCallback onLeave; // closes the sidebar and moves focus into the page
  final FocusNode Function(String id) nodeFor; // each entry's own focus node (see _AppShellState)

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([jellyfin, homeEditing]),
    builder: (context, _) {
      final loc = location;
      final inset = MediaQuery.paddingOf(context).left;
      final onSettings = loc == '/settings';
      // Settings opens on its first page when no tab is given.
      final settingsTab = tab ?? settingsTabLabels.first;
      final editing = homeEditing.value;


      // Opens a page and closes the sidebar, moving into the page, even if you were already
      // somewhere in the same section (another settings page, say).
      void goTo(String path) {
        context.go(path);
        onLeave();
      }

      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: inset + (open ? _openWidth : _railWidth),
        // A shadow while open, since it's covering the page.
        decoration: BoxDecoration(
          boxShadow: [
            if (open) const BoxShadow(color: Color(0x59000000), blurRadius: 24),
          ],
        ),
        // Only once it's fully open is there room for the Libraries and Settings pages
        // (indented, with an arrow). Showing them while it's still widening overflows.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final roomy = open && constraints.maxWidth >= inset + _openWidth - 0.5;
            return FSidebar(
              header: Padding(
                padding: EdgeInsets.fromLTRB(inset + _sidePadding, 4, _sidePadding, 4),
                child: Align(
                  alignment: Alignment.center,
                  child: _SidebarLogo(open: open, focusNode: nodeFor('Home'), onPress: () => goTo('/home')),
                ),
              ),
              footer: Padding(
                padding: EdgeInsets.only(left: inset),
                child: _SidebarUser(open: open),
              ),
              children: [
                Padding(
                  padding: EdgeInsets.only(left: inset),
                  child: Column(
                    children: [
                      FSidebarGroup(
                        style: const .delta(padding: .value(EdgeInsets.symmetric(horizontal: _sidePadding))),
                        children: [
                          _SidebarSearch(
                            open: open,
                            focusNode: nodeFor('Search'),
                            selected: loc.startsWith('/search'),
                            onSearched: onLeave,
                          ),
                          _SidebarLink(
                            label: 'Favorites',
                            icon: appIcons.favorite,
                            focusNode: nodeFor('Favorites'),
                            open: open,
                            selected: loc == '/home/favorites',
                            onPress: () => goTo('/home/favorites'),
                          ),
                          // Libraries, Genres and Settings fold up under one icon each. While the
                          // sidebar is closed only those icons show; open it and they list their pages.
                          _SidebarSection(
                            label: 'Libraries',
                            icon: appIcons.folder,
                            focusNode: nodeFor('Libraries'),
                            open: open,
                            closings: closings,
                            forceOpen: forceOpen['Libraries'] ?? 0,
                            active: loc.startsWith('/home/library'),
                            showPages: roomy,
                            children: [
                              for (final lib in jellyfin.libraries)
                                _SidebarLink(
                                  label: lib.name,
                                  focusNode: nodeFor('Libraries/${lib.id}'),
                                  open: open,
                                  selected: loc == '/home/library/${lib.id}',
                                  onPress: () => goTo('/home/library/${lib.id}'),
                                ),
                            ],
                          ),
                          // Genres: its own section between Libraries and Settings, listing each genre.
                          if (jellyfin.genres.isNotEmpty)
                            _SidebarSection(
                              label: 'Genres',
                              icon: appIcons.genres,
                              focusNode: nodeFor('Genres'),
                              open: open,
                              closings: closings,
                              forceOpen: forceOpen['Genres'] ?? 0,
                              active: loc.startsWith('/home/genre'),
                              showPages: roomy,
                              children: [
                                _SidebarLink(
                                  label: 'All genres',
                                  focusNode: nodeFor('Genres/All'),
                                  open: open,
                                  selected: loc == '/home/genres',
                                  onPress: () => goTo('/home/genres'),
                                ),
                                for (final genre in jellyfin.genres)
                                  _SidebarLink(
                                    label: genre,
                                    focusNode: nodeFor('Genres/${Uri.encodeComponent(genre)}'),
                                    open: open,
                                    selected: loc == '/home/genre/${Uri.encodeComponent(genre)}',
                                    onPress: () => goTo('/home/genre/${Uri.encodeComponent(genre)}'),
                                  ),
                              ],
                            ),
                          _SidebarSection(
                            label: 'Settings',
                            icon: appIcons.settings,
                            focusNode: nodeFor('Settings'),
                            open: open,
                            closings: closings,
                            forceOpen: forceOpen['Settings'] ?? 0,
                            active: onSettings,
                            showPages: roomy,
                            children: [
                              for (final label in settingsTabLabels)
                                _SidebarLink(
                                  label: label,
                                  focusNode: nodeFor('Settings/$label'),
                                  open: open,
                                  selected: onSettings && settingsTab == label,
                                  onPress: () => goTo('/settings?tab=$label'),
                                ),
                            ],
                          ),
                          // Edit mode for the home screen (phones have a button on Home instead).
                          _SidebarLink(
                            label: editing ? 'Done editing' : 'Edit home',
                            icon: editing ? appIcons.check : appIcons.edit,
                            focusNode: nodeFor('Edit'),
                            open: open,
                            selected: editing,
                            onPress: () {
                              homeEditing.value = !editing;
                              if (loc != '/home') context.go('/home');
                              onLeave(); // onto the home screen, to edit it
                            },
                          ),
                        ],
                      ),
                    ],
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

/// The logo at the top of the sidebar, which takes you home: just the mark while the sidebar
/// is closed, turning into the full wordmark as it opens.
class _SidebarLogo extends StatelessWidget {
  const _SidebarLogo({required this.open, required this.onPress, this.focusNode});

  final bool open;
  final VoidCallback onPress; // home
  final FocusNode? focusNode;

  static const _height = 28.0;

  // From the SVGs' sizes: the mark is 89 × 101, the whole wordmark 553 × 101.
  static const _markWidth = _height * 89.02 / 101.24;
  static const _wordmarkWidth = _height * 553.35 / 101.24;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      label: 'Home',
      button: true,
      // .static: no shrink when pressed.
      child: FTappable.static(
        focusNode: focusNode,
        onPress: onPress,
        builder: (context, states, child) {
          final highlighted = isHighlighted(states);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: highlighted ? colors.secondary : null, // only to show the remote is on it
              borderRadius: BorderRadius.circular(10),
            ),
            child: child,
          );
        },
        // The wordmark starts with the mark, so it's shown through a window that's just the
        // mark's width while closed and widens with the sidebar, uncovering the name. One
        // picture and no crossfade, so it moves exactly in step with the sidebar.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180), // the same as the sidebar opening
          curve: Curves.easeOutCubic,
          width: open ? _wordmarkWidth : _markWidth,
          height: _height,
          child: const UnconstrainedBox(
            alignment: Alignment.centerLeft,
            constrainedAxis: Axis.vertical,
            clipBehavior: Clip.hardEdge, // cut off quietly (no overflow warning)
            child: AppLogo(
              asset: 'assets/images/text_logo.svg',
              colorAsset: 'assets/images/text_logo_color.svg',
              height: _height,
              variant: AppLogoVariant.auto,
            ),
          ),
        ),
      ),
    );
  }
}

/// A sidebar entry that folds a list of pages (the libraries, the settings pages) under one
/// icon. While the sidebar is closed it's just the icon, lit up if you're on one of its pages;
/// open, it shows its pages, and selecting it folds them away or back out.
class _SidebarSection extends StatelessWidget {
  const _SidebarSection({
    required this.label,
    this.icon,
    this.focusNode,
    required this.open,
    required this.closings,
    required this.forceOpen,
    required this.active,
    required this.showPages,
    required this.children,
  });

  final String label;
  final IconData? icon; // none when it's inside another section (Genres)
  final FocusNode? focusNode;
  final bool open;
  final int closings; // see _Sidebar.closings
  final int forceOpen; // see _AppShellState._forceOpen: a fresh value forces this open
  final bool active; // on one of its pages
  final bool showPages; // the sidebar is fully open, so there's room for them
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => FSidebarItem(
    // A fresh item after each time the sidebar closes, so anything you unfolded folds back
    // up, and each time ← needs this section open and it wasn't already. forui only reads
    // initiallyExpanded once, in its own initState, so forcing it open means rebuilding it.
    key: ValueKey((label, closings, forceOpen)),
    focusNode: focusNode,
    label: switch (icon) {
      final icon? => _IconLabel(icon: icon, label: label, open: open),
      null => _FadingLabel(label, open: open),
    },
    // Each time the sidebar opens, only the section you're in starts unfolded — unless ←
    // has already forced this one open to reach a page inside it.
    initiallyExpanded: active || forceOpen > 0,
    // Only lit up while closed: once open, the page itself shows as selected.
    selected: active && !open,
    // No pages until the sidebar is fully open, so the rail stays a single icon (and the
    // arrow hides).
    children: showPages ? children : const [],
  );
}

/// Search in the sidebar: looks like the other links until you select it, then turns into a
/// search box in its place. Submitting opens the Search page with the results.
///
/// It only becomes a box when selected, not just when the remote passes over it, so the
/// on-screen keyboard doesn't pop up every time you move down the sidebar.
class _SidebarSearch extends StatefulWidget {
  const _SidebarSearch({
    required this.open,
    required this.selected,
    required this.onSearched,
    this.focusNode,
  });

  final bool open;
  final FocusNode? focusNode;
  final bool selected; // on the Search page
  final VoidCallback onSearched;

  @override
  State<_SidebarSearch> createState() => _SidebarSearchState();
}

class _SidebarSearchState extends State<_SidebarSearch> {
  final _text = TextEditingController();
  final _field = FocusNode(debugLabel: 'Sidebar search');
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    // Moving away from the box (↑/↓, or the sidebar closing) turns it back into the link.
    _field.addListener(() {
      if (!_field.hasFocus && _typing && mounted) setState(() => _typing = false);
    });
  }

  @override
  void didUpdateWidget(covariant _SidebarSearch old) {
    super.didUpdateWidget(old);
    if (!widget.open && _typing) _typing = false;
  }

  @override
  void dispose() {
    _text.dispose();
    _field.dispose();
    super.dispose();
  }

  void _start() {
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _field.requestFocus();
    });
  }

  void _submit(String text) {
    final query = text.trim();
    if (query.isEmpty) return;
    context.go(Uri(path: '/search', queryParameters: {'q': query}).toString());
    _text.clear();
    setState(() => _typing = false);
    widget.onSearched(); // into the results
  }

  @override
  Widget build(BuildContext context) {
    if (!(_typing && widget.open)) {
      return _SidebarLink(
        label: 'Search',
        icon: appIcons.search,
        focusNode: widget.focusNode,
        open: widget.open,
        selected: widget.selected,
        // Closed (a tap on a touch screen): straight to the Search page instead.
        onPress: widget.open ? _start : () => context.go('/search'),
      );
    }
    return FTextField(
      control: .managed(controller: _text),
      focusNode: _field,
      hint: 'Search',
      textInputAction: TextInputAction.search,
      prefixBuilder: (context, style, _) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 10),
        child: Icon(appIcons.search, size: 18, fill: 1),
      ),
      onSubmit: _submit,
    );
  }
}

/// One sidebar link. Its label fades out when the sidebar closes, leaving just the icon.
class _SidebarLink extends StatelessWidget {
  const _SidebarLink({
    required this.label,
    this.icon,
    this.focusNode,
    required this.open,
    required this.onPress,
    this.selected = false,
  });

  final String label;
  final IconData? icon; // none for the pages under Libraries and Settings
  final FocusNode? focusNode;
  final bool open;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => FSidebarItem(
    focusNode: focusNode,
    label: switch (icon) {
      final icon? => _IconLabel(icon: icon, label: label, open: open),
      null => _FadingLabel(label, open: open), // the pages under Libraries and Settings
    },
    selected: selected,
    onPress: onPress,
  );
}

/// A sidebar item's icon and label. Laid out here rather than by [FSidebarItem] so the icon
/// can sit in the middle of the closed rail (like the logo and the user picture), then slide
/// over to the left as the sidebar opens and the label fades in beside it.
class _IconLabel extends StatelessWidget {
  const _IconLabel({required this.icon, required this.label, required this.open});

  final IconData icon;
  final String label;
  final bool open;

  static const _iconSize = 20.0;
  static const _gap = 8.0; // between the icon and the label, while open
  static const _duration = Duration(milliseconds: 180); // the same as the sidebar opening

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    // The room an item's content has in the closed rail, after the group's and the item's
    // own padding (which is wider on touch screens), so the icon can be centered in it.
    final itemPadding = theme.sidebarStyle.groupStyle.itemStyle.padding.horizontal;
    final closedRoom = _railWidth - 2 * _sidePadding - itemPadding;
    final centered = ((closedRoom - _iconSize) / 2).clamp(0.0, double.infinity);

    return Row(
      children: [
        AnimatedContainer(duration: _duration, curve: Curves.easeOutCubic, width: open ? 0 : centered),
        Icon(
          icon,
          size: _iconSize,
          fill: 1,
          color: theme.colors.foreground,
          semanticLabel: open ? null : label,
        ),
        AnimatedContainer(duration: _duration, curve: Curves.easeOutCubic, width: open ? _gap : 0),
        Expanded(child: _FadingLabel(label, open: open)),
      ],
    );
  }
}

/// Text that fades out when the sidebar closes, and is cut off cleanly while it narrows.
class _FadingLabel extends StatelessWidget {
  const _FadingLabel(this.text, {required this.open, this.style});

  final String text;
  final bool open;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: const Duration(milliseconds: 150),
    opacity: open ? 1 : 0,
    child: Text(text, style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
  );
}

/// The signed-in user at the bottom of the sidebar, as a card. Selecting it switches user.
/// While the sidebar is closed it tightens up to just the picture.
class _SidebarUser extends StatelessWidget {
  const _SidebarUser({required this.open});

  final bool open;

  static const _duration = Duration(milliseconds: 180); // the same as the sidebar opening

  static const _avatarSize = 32.0;
  static const _ringGap = 3.0; // between the picture and its ring
  static const _ringed = _avatarSize + 2 * _ringGap;

  /// While closed, the side padding inside the card that puts the picture in the middle.
  static const _closedInner = (_railWidth - 2 * _sidePadding - _ringed) / 2;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _sidePadding), // lines up with the list
      child: FTappable.static(
        onPress: () => showProfilePicker(context), // "Who's watching?"
        // Focused (remote) or hovered (mouse): the card fills in, like the other sidebar items.
        builder: (context, states, child) {
          final highlighted = isHighlighted(states);
          return Stack(
            children: [
              // The card fades in behind the picture and name as the sidebar opens, so while
              // it's closed there's just the picture.
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: _duration,
                  opacity: open ? 1 : 0,
                  child: const FCard(child: SizedBox.expand()),
                ),
              ),
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: highlighted ? 1 : 0,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: theme.colors.secondary,
                      shape: RoundedSuperellipseBorder(borderRadius: theme.style.borderRadius.lg),
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child:             AnimatedPadding(
          duration: _duration,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: open ? 12 : _closedInner),
          child: Row(
            children: [
              // A faint ring around the picture.
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colors.primary.withValues(alpha: 0.35), width: 1.5),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(_ringGap),
                  child: UserAvatar(size: _avatarSize),
                ),
              ),
              // The gap closes up with the sidebar, so the picture can sit in the middle.
              AnimatedContainer(duration: _duration, curve: Curves.easeOutCubic, width: open ? 10 : 0),
              Expanded(
                child: _FadingLabel(
                  jellyfin.userName ?? 'Switch user',
                  open: open,
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colors.foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}