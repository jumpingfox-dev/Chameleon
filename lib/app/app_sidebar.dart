part of 'app_shell.dart';

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
        // See-through: open, the shell darkens the page behind it with a gradient instead.
        width: inset + (open ? _openWidth : _railWidth),
        // Only once it's fully open is there room for the Libraries and Settings pages
        // (indented, with an arrow). Showing them while it's still widening overflows.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final roomy = open && constraints.maxWidth >= inset + _openWidth - 0.5;
            return _SidebarFrame(
              // Home, Search, Favorites, Libraries, Genres (if any), Settings, Edit home.
              entries: jellyfin.genres.isNotEmpty ? 7 : 6,
              header: Padding(
                // On the left, the room that centers the mark in the rail, where it stays as
                // the sidebar opens.
                padding: EdgeInsets.fromLTRB(inset + _SidebarLogo.railInset, 0, _sidePadding, 0),
                child: Align(alignment: Alignment.centerLeft, child: _SidebarLogo(open: open)),
              ),
              footer: Padding(
                padding: EdgeInsets.only(left: inset + _SidebarUser.railInset),
                child: const Align(alignment: Alignment.centerLeft, child: _SidebarUser()),
              ),
              children: [
                Padding(
                  padding: EdgeInsets.only(left: inset),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
                        child: Column(
                          spacing: _SidebarFrame.spacing,
                          children: [
                            _SidebarLink(
                              label: 'Home',
                              icon: appIcons.home,
                              focusNode: nodeFor('Home'),
                              open: open,
                              selected: loc == '/home',
                              onPress: () => goTo('/home'),
                            ),
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

/// The logo at the top of the sidebar: just the mark while the sidebar is closed, turning
/// into the full wordmark as it opens.
class _SidebarLogo extends StatelessWidget {
  const _SidebarLogo({required this.open});

  final bool open;

  static const _height = 34.0;

  /// The room left of the logo that centers the mark in the closed rail.
  static const railInset = (_railWidth - _markWidth) / 2;

  // From the SVGs' sizes: the mark is 89 × 101, the whole wordmark 553 × 101.
  static const _markWidth = _height * 89.02 / 101.24;
  static const _wordmarkWidth = _height * 553.35 / 101.24;

  // The wordmark starts with the mark, so it's shown through a window that's just the mark's
  // width while closed and widens with the sidebar, uncovering the name. One picture and no
  // crossfade, so it moves exactly in step with the sidebar.
  @override
  Widget build(BuildContext context) => AnimatedContainer(
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
  );
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
  Widget build(BuildContext context) => _SidebarItem(
    // A fresh item after each time the sidebar closes, so anything you unfolded folds back
    // up, and each time ← needs this section open and it wasn't already. An item only reads
    // initiallyExpanded when it's first built, so forcing it open means rebuilding it.
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
    onPress: () {},
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
  const _SidebarSearch({required this.open, required this.selected, required this.onSearched, this.focusNode});

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
    // Round like the links' highlight, and exactly a link's height, so the links below stay put.
    return SizedBox(
      height: _SidebarItem.height,
      child: TextField(
        controller: _text,
        focusNode: _field,
        textInputAction: TextInputAction.search,
        expands: true, // fills the height above, with the text centered in it
        maxLines: null,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: 'Search',
          prefixIcon: Icon(appIcons.search, size: 18, fill: 1),
          prefixIconConstraints: const BoxConstraints(minWidth: 44),
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: searchFieldBorder,
        ),
        onSubmitted: _submit,
      ),
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
  Widget build(BuildContext context) => _SidebarItem(
    focusNode: focusNode,
    label: switch (icon) {
      final icon? => _IconLabel(icon: icon, label: label, open: open),
      null => _FadingLabel(label, open: open), // the pages under Libraries and Settings
    },
    selected: selected,
    onPress: onPress,
  );
}

/// A sidebar item's icon and label, laid out so the icon
/// can sit in the middle of the closed rail (like the logo and the user picture), and stay
/// there as the sidebar opens and the label fades in beside it.
class _IconLabel extends StatelessWidget {
  const _IconLabel({required this.icon, required this.label, required this.open});

  final IconData icon;
  final String label;
  final bool open;

  static const _iconSize = 24.0;
  static const _gap = 8.0; // between the icon and the label

  @override
  Widget build(BuildContext context) {
    // The room an item's content has in the closed rail, after the list's and the item's
    // own padding, so the icon can be centered in it.
    final closedRoom = _railWidth - 2 * _sidePadding - _SidebarItem.padding.horizontal;
    final centered = ((closedRoom - _iconSize) / 2).clamp(0.0, double.infinity);

    return Row(
      children: [
        SizedBox(width: centered),
        Icon(icon, size: _iconSize, fill: 1, semanticLabel: open ? null : label),
        // The gap is part of the label's room, which is all that shrinks as the sidebar
        // closes, so the icon and spacer never need more than the closed rail has.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: _gap),
            child: _FadingLabel(label, open: open),
          ),
        ),
      ],
    );
  }
}

/// Text that fades out when the sidebar closes, and is cut off cleanly while it narrows.
class _FadingLabel extends StatelessWidget {
  const _FadingLabel(this.text, {required this.open});

  final String text;
  final bool open;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: const Duration(milliseconds: 150),
    opacity: open ? 1 : 0,
    child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
  );
}

/// The signed-in user's picture at the bottom of the sidebar. Selecting it switches user.
class _SidebarUser extends StatelessWidget {
  const _SidebarUser();

  static const _avatarSize = 36.0;
  static const _ringGap = 3.0; // between the picture and its ring
  static const _ringed = _avatarSize + 2 * _ringGap;

  /// The room left of the picture that centers it in the closed rail.
  static const railInset = (_railWidth - _ringed) / 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tappable(
      onPress: () => showProfilePicker(context), // "Who's watching?"
      semanticsLabel: 'Switch user (${jellyfin.userName ?? 'signed in'})',
      // A faint ring around the picture, which lights up when the remote or mouse is on it.
      builder: (context, states, child) {
        final highlighted = isHighlighted(states);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(_ringGap),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: highlighted ? colors.primary : colors.primary.withValues(alpha: 0.35),
              width: highlighted ? 2.5 : 1.5,
            ),
          ),
          child: child,
        );
      },
      child: const UserAvatar(size: _avatarSize),
    );
  }
}

/// The fill behind whatever the remote or mouse is on.
Color _highlight(ColorScheme colors) => colors.onSurface.withValues(alpha: 0.10);

/// The sidebar's surface: [header] (the logo) at the top, [footer] (the avatar) at the
/// bottom, and the links ([children]) between them.
///
/// The links sit in the middle of that space, as they are with the sidebar closed: [entries]
/// links, every section folded. That spot is worked out from the closed sidebar and kept as it
/// opens, so nothing moves; sections unfold downwards, and the list scrolls if it runs out of
/// room.
class _SidebarFrame extends StatelessWidget {
  const _SidebarFrame({
    required this.entries,
    required this.header,
    required this.footer,
    required this.children,
  });

  final int entries;
  final Widget header;
  final Widget footer;
  final List<Widget> children;

  /// Between the links.
  static const spacing = 2.0;

  /// From the top and bottom edges to the logo and the avatar. The logo's top then lines up
  /// with the top of each page's content (see pageTop).
  static const _edge = 32.0;

  /// The least room between the logo or avatar and the links.
  static const _minGap = 16.0;

  @override
  Widget build(BuildContext context) {
    final closedHeight = entries * _SidebarItem.height + (entries - 1) * spacing;
    // See-through, with no edge: the page shows behind the rail, and the shell darkens it with
    // a gradient while the sidebar is open (see AppShell).
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: _edge),
          child: Column(
            children: [
              header,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final gap = ((constraints.maxHeight - closedHeight) / 2).clamp(_minGap, double.infinity);
                    return SingleChildScrollView(
                      padding: EdgeInsets.only(top: gap, bottom: _minGap),
                      child: Column(children: children),
                    );
                  },
                ),
              ),
              footer,
            ],
          ),
        ),
      ),
    );
  }
}

/// One sidebar entry, drawn like a Material navigation drawer's: a pill that fills in when
/// it's the page you're on. With [children] it's a section, and selecting it folds them
/// away or back out.
class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    super.key,
    required this.label,
    required this.onPress,
    this.focusNode,
    this.selected = false,
    this.initiallyExpanded = false,
    this.children = const [],
  });

  final Widget label;
  final VoidCallback onPress;
  final FocusNode? focusNode;
  final bool selected;
  final bool initiallyExpanded; // only read when it's first built
  final List<Widget> children;

  static const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 12);

  /// A link's height: its padding around the icon.
  static double get height => padding.vertical + _IconLabel._iconSize;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  late bool _expanded = widget.initiallyExpanded;

  void _press() {
    if (widget.children.isNotEmpty) setState(() => _expanded = !_expanded);
    widget.onPress();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasChildren = widget.children.isNotEmpty;
    final item = Tappable(
      focusNode: widget.focusNode,
      onPress: _press,
      builder: (context, states, child) {
        final highlighted = isHighlighted(states);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: _SidebarItem.padding,
          decoration: ShapeDecoration(
            color: switch ((widget.selected, highlighted)) {
              (true, _) => colors.secondaryContainer,
              (false, true) => _highlight(colors),
              _ => Colors.transparent,
            },
            shape: const StadiumBorder(),
          ),
          // Already filled in as the page you're on, so the remote shows as a ring. Drawn on top
          // rather than as a border, which would take room: the icon would sit off-center in
          // its circle, and the link would be taller than a link is meant to be.
          foregroundDecoration: ShapeDecoration(
            shape: StadiumBorder(
              side: widget.selected && highlighted
                  ? BorderSide(color: colors.onSecondaryContainer, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: child,
        );
      },
      child: DefaultTextStyle.merge(
        style: context.text.labelLarge?.copyWith(
          color: widget.selected ? colors.onSecondaryContainer : colors.onSurfaceVariant,
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: widget.selected ? colors.onSecondaryContainer : colors.onSurfaceVariant),
          child: Row(
            children: [
              Expanded(child: widget.label),
              if (hasChildren)
                AnimatedRotation(
                  duration: const Duration(milliseconds: 150),
                  turns: _expanded ? 0 : -0.25, // points right while folded, down while open
                  child: Icon(appIcons.expand, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
    if (!hasChildren) return item;
    // No spacing in this column: folded, the pages take no room at all, so the links below
    // don't move when the sidebar opens.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        item,
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(left: 28, top: _SidebarFrame.spacing),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: _SidebarFrame.spacing,
                    children: widget.children,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
