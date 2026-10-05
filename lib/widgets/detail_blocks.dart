part of 'detail_page.dart';

// ─── Building blocks, shared by layouts ──────────────────────────────────────

/// An info card: image, title, subtitle and expandable description.
/// Side by side on wide screens, stacked and centered on phones.
class SliverDetailCard extends StatelessWidget {
  const SliverDetailCard({
    super.key,
    required this.image,
    required this.title,
    this.subtitle,
    this.description,
    this.footer = const [],
  });

  /// Builds the image at the given size (160 on wide screens, 120 on phones).
  final Widget Function(double size) image;
  final String title;
  final String? subtitle;
  final String? description;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final isPhone = isPhoneLayout(context);
    final text = description?.trim();

    final details = [
      Text(
        title,
        textAlign: isPhone ? TextAlign.center : TextAlign.start,
        style: context.theme.typography.display.xl,
      ),
      if (subtitle != null)
        Text(
          subtitle!,
          style: context.theme.typography.body.sm.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
      if (text != null && text.isNotEmpty) ...[
        const SizedBox(height: 8),
        ExpandableText(
          text,
          limit: isPhone ? 150 : 400,
          style: context.theme.typography.body.md,
        ),
      ],
    ];

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              if (isPhone)
                Column(spacing: 8, children: [image(120), ...details])
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 24,
                  children: [
                    image(160),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: details,
                      ),
                    ),
                  ],
                ),
              ...footer,
            ],
          ),
        ),
      ),
    );
  }
}

/// A rectangular 2:3 poster for info cards (collections, series, ...).
class DetailPoster extends StatelessWidget {
  const DetailPoster({super.key, required this.item, this.width = 140});

  final JellyfinItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final tag = item.imageTags['Primary'];
    return SizedBox(
      width: width,
      height: width * 1.5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: tag == null
            ? ColoredBox(color: context.theme.colors.muted)
            : Image.network(
          jellyfin.client!.images.url(
            itemId: item.id,
            type: JellyfinImagesApi.typePrimary,
            tag: tag,
            fillWidth: (width * 2).round(),
            quality: 90,
          ),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// An outlined age-rating badge, e.g. [PG-13].
class _RatingBadge extends StatelessWidget {
  const _RatingBadge(this.rating);

  final String rating;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.mutedForeground),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          rating,
          style: context.theme.typography.body.sm.copyWith(
            color: colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}

/// Genre buttons, each opening its genre page.
class _GenreButtons extends StatelessWidget {
  const _GenreButtons(this.genres);

  final List<String> genres;

  @override
  Widget build(BuildContext context) => ScrollIntoViewOnFocus(
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final genre in genres)
          FButton(
            variant: .outline,
            size: .xs,
            mainAxisSize: .min,
            onPress: () {
              final router = GoRouter.of(
                context,
              ); // grab it before the popout (and this context) closes
              closeDetailPopouts(context);
              router.push('/home/genre/${Uri.encodeComponent(genre)}');
            },
            child: Text(genre),
          ),
      ],
    ),
  );
}

/// The divider between a card's details and its list (movies, cast, ...).
class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) => const FDivider(
    style: .delta(padding: .value(.all(8))),
    axis: .horizontal,
  );
}

/// A grid of posters or thumbnails inside a card. It doesn't scroll on its own;
/// it lays out all its items and the page scrolls around it.
class _InlineItemGrid extends StatelessWidget {
  const _InlineItemGrid(this.items);

  final List<JellyfinItem> items;

  @override
  Widget build(BuildContext context) {
    final view = libraryViewFor(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: libraryGridDelegate(view),
      itemCount: items.length,
      itemBuilder: (context, i) => ScrollIntoViewOnFocus(
        child: PosterCard(
          item: items[i],
          view: view,
          onPress: () => openItem(context, items[i]),
        ),
      ),
    );
  }
}

/// Marks everything below it as inside a popout, so cards can show a close button.
class _PopoutScope extends InheritedWidget {
  const _PopoutScope({required super.child, this.gap = 0});

  /// The empty space above the popout's first card (see [DetailPage.popoutGap]).
  final double gap;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PopoutScope>() != null;

  static double gapOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PopoutScope>()?.gap ?? 0;

  @override
  bool updateShouldNotify(_PopoutScope oldWidget) => oldWidget.gap != gap;
}

/// Catches taps that land on its child, so they don't count as "clicking outside" a popout.
/// Buttons and posters inside still receive their own taps.
class _TapShield extends StatelessWidget {
  const _TapShield({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {},
    child: child,
  );
}

/// The card used by every detail layout. It absorbs taps, and in a popout shows a
/// close button in its top-right corner.
class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child, this.showClose = true, this.edgeToEdge = false});

  final Widget child;

  /// False for cards under a backdrop banner, which carries the close button instead.
  final bool showClose;

  /// True when [child] is a [_CardColumn]: the card then leaves out its side padding and
  /// the column adds it to each piece, so sideways rows can scroll to the card's edges.
  final bool edgeToEdge;

  @override
  Widget build(BuildContext context) => _TapShield(
    child: FCard(
      builder: (context, style, _) {
        final padding = style.padding.resolve(Directionality.of(context));
        return Stack(
          children: [
            if (edgeToEdge)
              Padding(
                padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
                child: _CardSides(left: padding.left, right: padding.right, child: child),
              )
            else
              Padding(padding: padding, child: child),
            if (showClose && _PopoutScope.of(context))
              Positioned(
                top: 8,
                right: 8,
                child: FButton.icon(
                  variant: .ghost,
                  autofocus:
                  FocusManager.instance.highlightMode ==
                      FocusHighlightMode.traditional,
                  onPress: () => Navigator.of(context).pop(),
                  child: Icon(appIcons.close, fill: 1),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// The card's side padding, passed down to its [_CardColumn].
class _CardSides extends InheritedWidget {
  const _CardSides({required this.left, required this.right, required super.child});

  final double left;
  final double right;

  static _CardSides? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_CardSides>();

  @override
  bool updateShouldNotify(_CardSides old) => old.left != left || old.right != right;
}

/// A card's contents, one piece under another. Each piece gets the card's side padding,
/// except [_EdgeToEdge] ones, which run to the card's edges (and put the padding inside).
class _CardColumn extends StatelessWidget {
  const _CardColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final sides = _CardSides.of(context);
    final inset = EdgeInsets.only(left: sides?.left ?? 0, right: sides?.right ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        for (final child in children)
          child is _RunsToCardEdges
              ? child
              : Padding(
            padding: inset,
            child: Align(alignment: AlignmentDirectional.centerStart, child: child),
          ),
      ],
    );
  }
}

/// Marks a [_CardColumn] piece that runs to the card's edges instead of getting its side padding.
mixin _RunsToCardEdges on Widget {}

/// A sideways-scrolling row inside a [_CardColumn] that runs to the card's edges.
/// [builder] gets the padding to put inside the scroll view, so its first item still
/// lines up with the rest of the card.
class _EdgeToEdge extends StatelessWidget with _RunsToCardEdges {
  const _EdgeToEdge({required this.builder});

  final Widget Function(EdgeInsets padding) builder;

  @override
  Widget build(BuildContext context) {
    final sides = _CardSides.of(context);
    return builder(EdgeInsets.only(left: sides?.left ?? 0, right: sides?.right ?? 0));
  }
}

/// A section heading, e.g. "Movies & Shows".
class SliverSectionTitle extends StatelessWidget {
  const SliverSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(text, style: context.theme.typography.display.lg),
    ),
  );
}

/// A grid of posters or thumbnails, following the poster/thumbnail toggle.
class SliverItemGrid extends StatelessWidget {
  const SliverItemGrid({super.key, required this.items});

  final List<JellyfinItem> items;

  @override
  Widget build(BuildContext context) {
    final view = libraryViewFor(context);
    return SliverGrid.builder(
      gridDelegate: libraryGridDelegate(view),
      itemCount: items.length,
      itemBuilder: (context, i) => ScrollIntoViewOnFocus(
        child: PosterCard(
          item: items[i],
          view: view,
          onPress: () => openItem(context, items[i]),
        ),
      ),
    );
  }
}

/// Closes the popout it's in when the app navigates somewhere else: another library,
/// a genre, another tab, ... Playing something doesn't count, because the player opens
/// over the popout and closing it should return you here.
class _CloseOnNavigation extends StatefulWidget {
  const _CloseOnNavigation({required this.child});

  final Widget child;

  @override
  State<_CloseOnNavigation> createState() => _CloseOnNavigationState();
}

class _CloseOnNavigationState extends State<_CloseOnNavigation> {
  GoRouter? _router;
  late Uri _openedAt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_router != null) return; // set up once
    _router = GoRouter.of(context);
    _openedAt = _router!
        .routerDelegate
        .currentConfiguration
        .uri; // where the app was when this opened
    _router!.routerDelegate.addListener(_onNavigate);
  }

  void _onNavigate() {
    final uri = _router!.routerDelegate.currentConfiguration.uri;
    if (uri == _openedAt || uri.path.startsWith('/play')) return;

    // Close this popout specifically, after the current navigation has finished.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    });
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onNavigate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The first line of a details card (year, seasons, age rating, score...), on one line
/// that scrolls sideways when it doesn't fit.
class _FactsRow extends StatelessWidget with _RunsToCardEdges {
  const _FactsRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _EdgeToEdge(
    // Runs to the card's edges, so anything past the end scrolls in from there.
    builder: (padding) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(spacing: 16, children: children),
    ),
  );
}

// ─── Floating buttons ────────────────────────────────────────────────────────

/// A white icon that floats over the content, on a translucent dark circle when [filled].
class _FloatingIconButton extends StatelessWidget {
  const _FloatingIconButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onPress,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onPress;
  final bool autofocus;
  static const size = 40.0;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: FTappable(
      autofocus: autofocus,
      onPress: onPress,
      builder: (context, states, _) {
        final active = isHighlighted(states);
        return AnimatedScale(
          scale: active
              ? 1.1
              : 1.0, // grows slightly under the pointer or remote
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? const Color(0x99000000) // a little darker
                  : filled
                  ? const Color(0x73000000)
                  : const Color(0x00000000),
              border: Border.all(
                color: active
                    ? const Color(0xFFFFFFFF)
                    : const Color(0x00FFFFFF), // white ring
                width: 2,
              ),
            ),
            child: Icon(icon, size: size / 2, color: const Color(0xFFFFFFFF), fill: 1),
          ),
        );
      },
    ),
  );
}
