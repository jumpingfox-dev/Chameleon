import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import '../utils/app_cache.dart';
import '../utils/focus_rows.dart';
import '../utils/jellyfin_controller.dart';
import '../utils/orientation.dart';
import 'expandable_text.dart';
import 'hover_lift.dart';
import 'person_tile.dart';
import 'poster_card.dart';
import 'scroll_into_view.dart';

/// Bumped whenever a favorite is added or removed, so pages listing favorites can refresh.
final favoritesChanged = ValueNotifier<int>(0);

// ─── Navigation ──────────────────────────────────────────────────────────────

/// Where selecting an item goes. One place for every page, so they all behave the same.
void openItem(BuildContext context, JellyfinItem item) {
  switch (item.type) {
    case JellyfinItemKind.movie:
      showDetailPopout(
        context,
        load: movieDetails(item.id),
        layout: const MovieLayout(),
        cacheKey: 'movie:${item.id}',
      );
    case JellyfinItemKind.series:
      showDetailPopout(
        context,
        load: seriesDetails(item.id),
        layout: const SeriesLayout(),
        cacheKey: 'series:${item.id}',
      );
    case JellyfinItemKind.episode:
      context.push('/play/${item.id}');
    case 'BoxSet':
      showDetailPopout(
        context,
        load: collectionDetails(item.id),
        layout: const CollectionLayout(),
        cacheKey: 'collection:${item.id}',
      );
    case JellyfinItemKind.person:
      openPerson(context, item.id);
  }
}

/// Opens a person's popout by id (cast rows and search results only have the id).
void openPerson(BuildContext context, String personId) => showDetailPopout(
  context,
  load: personDetails(personId),
  layout: const PersonLayout(),
  cacheKey: 'person:$personId',
);

/// Plays an item: a movie (or episode) directly, or a series from where you left off.
Future<void> playItem(BuildContext context, JellyfinItem item) async {
  final router = GoRouter.of(context); // grab it before any await
  if (item.type != JellyfinItemKind.series) {
    router.push('/play/${item.id}');
    return;
  }
  final episode = await nextEpisodeFor(item.id);
  if (episode != null) router.push('/play/${episode.id}');
}

/// The episode to play next in a series: Jellyfin's "Next Up", or else the first episode
/// of the first regular season (skipping Specials).
Future<JellyfinItem?> nextEpisodeFor(String seriesId) async {
  final client = jellyfin.client!;

  final nextUp = await client.tvShows.nextUp(
    seriesId: seriesId,
    limit: 1,
    enableResumable: true,
  );
  if (nextUp.items.firstOrNull case final episode?) return episode;

  final seasons = (await client.tvShows.seasons(seriesId: seriesId)).items;
  final firstSeason =
      seasons
          .where((s) => ((s.raw['IndexNumber'] as int?) ?? 0) > 0)
          .firstOrNull ??
          seasons.firstOrNull;
  if (firstSeason == null) return null;

  final episodes = await client.tvShows.episodes(
    seriesId: seriesId,
    seasonId: firstSeason.id,
  );
  return episodes.items.firstOrNull;
}

/// Shows a detail layout in a large card floating over the current screen's content,
/// leaving the nav bars visible and usable. Any popout already open is closed first.
Future<void> showDetailPopout(
    BuildContext context, {
      required DetailLoader load,
      required DetailLayout layout,
      String? cacheKey,
    }) {
  // The tab's navigator covers only the area between the nav bars, so the popout does too.
  // Read everything needed from `context` now: if it belongs to a popout, it's about to close.
  final navigator = Navigator.of(context);
  final barrierColor = context.theme.colors.barrier;

  navigator.popUntil((route) => route is! PopupRoute); // close any open popouts

  return showGeneralDialog(
    context: navigator.context,
    useRootNavigator: false, // stay inside the tab, below the top bar and above the bottom bar
    barrierDismissible: true, // click outside to close
    barrierLabel: 'Close',
    barrierColor: barrierColor,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) {
      final isPhone = isPhoneLayout(context);
      // Size to the space the tab actually has, not the whole screen.
      return _CloseOnNavigation(
        child: Padding(
          // Phones in landscape: keep the card clear of the camera cutout and rounded corners.
          padding: EdgeInsets.only(
            left: MediaQuery.paddingOf(context).left,
            right: MediaQuery.paddingOf(context).right,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              // Full height, so content scrolls right off the top and bottom of the screen
              // instead of being sliced off at an invisible edge. The gap it used to have
              // above and below is now space inside the scroll.
              child: SizedBox(
                width: math.min(constraints.maxWidth - (isPhone ? 16 : 48), 1100),
                height: constraints.maxHeight,
                child: DetailPage(
                  load: load,
                  layout: layout,
                  popout: true,
                  cacheKey: cacheKey,
                  popoutGap: constraints.maxHeight * (isPhone ? 0.02 : 0.04),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Closes every open detail popout, e.g. before going to a full page like a genre.
void closeDetailPopouts(BuildContext context) =>
    Navigator.of(context).popUntil((route) => route is! PopupRoute);

// ─── Data ────────────────────────────────────────────────────────────────────

/// What a detail page loads: the main item, the items that belong to it,
/// and anything extra a particular layout needs (seasons, tracks, ...).
class DetailData {
  const DetailData({
    required this.item,
    this.children = const [],
    this.extra = const {},
  });

  final JellyfinItem item;
  final List<JellyfinItem> children;
  final Map<String, Object?> extra;
}

// ─── Loaders ─────────────────────────────────────────────────────────────────

typedef DetailLoader = Future<DetailData> Function(JellyfinClient client);

DetailLoader movieDetails(String id) =>
        (client) async => DetailData(item: (await client.items.byId(id))!);

DetailLoader collectionDetails(String id) => (client) async {
  final (collection, page) = await (
  client.items.byId(id),
  client.items.list(
    parentId: id,
    sortBy: const ['ProductionYear', 'SortName'],
    limit: 200,
    fields: const ['Genres', 'OfficialRating', 'ProductionYear'],
  ),
  ).wait;
  return DetailData(item: collection!, children: page.items);
};

DetailLoader personDetails(String id) => (client) async {
  final (person, page) = await (
  client.items.byId(id),
  client.items.list(
    personIds: [id],
    includeItemTypes: const [JellyfinItemKind.movie, JellyfinItemKind.series],
    recursive: true,
    sortBy: const ['ProductionYear', 'SortName'],
    descending: true,
  ),
  ).wait;
  return DetailData(item: person!, children: page.items);
};

DetailLoader seriesDetails(String id) => (client) async {
  final (series, seasons) = await (
  client.items.byId(id),
  client.tvShows.seasons(seriesId: id),
  ).wait;
  // Regular seasons in order, with "Specials" (season 0) at the end.
  final ordered = [...seasons.items]
    ..sort((a, b) {
      final ai = (a.raw['IndexNumber'] as int?) ?? 0,
          bi = (b.raw['IndexNumber'] as int?) ?? 0;
      if (ai == 0) return 1;
      if (bi == 0) return -1;
      return ai.compareTo(bi);
    });
  return DetailData(item: series!, children: ordered);
};

// ─── Layouts ─────────────────────────────────────────────────────────────────

/// How a detail page looks. Each kind of page gets its own subclass,
/// free to lay things out however it wants.
abstract class DetailLayout {
  const DetailLayout();

  /// Text in the header next to the back button, if any.
  String? headerTitle(DetailData data) => null;

  /// The page's content, as slivers.
  List<Widget> buildSlivers(BuildContext context, DetailData data);

  /// True if the back button should float over the content (a white arrow on a dark circle)
  /// instead of sitting in a normal header row.
  bool get floatingBackButton => false;

  /// Space above the page's content.
  double get topPadding => 24;

  /// Where the floating back button sits, measured from the top-left of the page's content
  /// (below the top padding).
  Offset get backButtonOffset => const Offset(12, 12);
}

/// A person: round photo, name, how many of their titles you have, biography,
/// then the movies and shows they appear in.
class PersonLayout extends DetailLayout {
  const PersonLayout();

  @override
  List<Widget> buildSlivers(BuildContext context, DetailData data) {
    final count = data.children.length;
    return [
      SliverDetailCard(
        image: (size) => PersonPhoto(person: data.item, size: size),
        title: data.item.name,
        subtitle: '$count ${count == 1 ? 'title' : 'titles'} in your library',
        description: data.item.raw['Overview'] as String?,
        footer: [
          if (data.children.isNotEmpty) ...[
            const _CardDivider(),
            Text('Movies & Shows', style: context.theme.typography.display.lg),
            _InlineItemGrid(data.children),
          ],
        ],
      ),
    ];
  }

  @override
  bool get floatingBackButton => true;

  @override
  Offset get backButtonOffset => const Offset(4, 4); // tucked into the card's corner

  @override
  double get topPadding => 24;
}

/// A collection: backdrop banner with the logo, then an info card (count, years, age rating,
/// description, genres, and its movies).
class CollectionLayout extends DetailLayout {
  const CollectionLayout();

  @override
  List<Widget> buildSlivers(BuildContext context, DetailData data) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _BackdropBanner(item: data.item, topPadding: topPadding),
      ),
    ),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _CollectionInfoCard(collection: data.item, items: data.children),
      ),
    ),
  ];

  @override
  bool get floatingBackButton => true;

  @override
  Offset get backButtonOffset => const Offset(6, 6); // tucked into the banner's corner
}

/// A movie: backdrop banner with the logo, then an info card (year, runtime, age rating,
/// score, Play, description, genres, and the cast).
class MovieLayout extends DetailLayout {
  const MovieLayout();

  @override
  List<Widget> buildSlivers(BuildContext context, DetailData data) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _BackdropBanner(item: data.item, topPadding: topPadding),
      ),
    ),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _MovieInfoCard(movie: data.item),
      ),
    ),
  ];

  @override
  bool get floatingBackButton => true;

  @override
  Offset get backButtonOffset => const Offset(6, 6); // tucked into the banner's corner
}

/// A series: backdrop banner with the logo, then an info card (years, seasons, age rating,
/// score, description, genres), a season picker and that season's episodes.
class SeriesLayout extends DetailLayout {
  const SeriesLayout();

  @override
  List<Widget> buildSlivers(BuildContext context, DetailData data) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _BackdropBanner(item: data.item, topPadding: topPadding),
      ),
    ),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _SeriesInfoCard(series: data.item, seasons: data.children),
      ),
    ),
  ];

  @override
  bool get floatingBackButton => true;

  @override
  Offset get backButtonOffset => const Offset(6, 6); // tucked into the banner's corner
}

// To add a new kind of page later, add a layout here, for example:
//
// class AlbumLayout extends DetailLayout {
//   const AlbumLayout();
//
//   @override
//   List<Widget> buildSlivers(BuildContext context, DetailData data) => [
//     // cover art, artist, track list...
//   ];
// }

// ─── The page ────────────────────────────────────────────────────────────────

/// A detail page: loads its data, shows loading and errors, and hands the result to a layout.
class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.load,
    required this.layout,
    this.popout = false,
    this.cacheKey,
    this.popoutGap = 0,
  });

  /// Fetches the page's data. Called on open and on "Try again".
  final DetailLoader load;

  final DetailLayout layout;

  /// True when shown as a floating card: no scaffold, and a close button instead of back.
  final bool popout;

  /// When set, the page's data is cached under this key and reused for 10 minutes.
  final String? cacheKey;

  /// Popouts: empty space above the first card and below the last, inside the scroll,
  /// so the page starts a little way down but can scroll right to the screen's edges.
  final double popoutGap;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  DetailData? _data;
  bool _loading = true;
  String? _error;
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final scrolled = _scroll.offset > 4;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });

    // Show cached data straight away; refresh quietly if it's old.
    final key = widget.cacheKey;
    final cached = key == null ? null : appCache.peek<DetailData>(key);
    if (cached != null) {
      _data = cached;
      _loading = false;
    }
    if (key == null || !appCache.isFresh(key)) _load(silent: cached != null);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// [silent] refreshes in the background, keeping current content on screen instead of a spinner.
  Future<void> _load({bool silent = false}) async {
    final client = jellyfin.client;
    if (client == null) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await widget.load(client);
      if (widget.cacheKey case final key?) appCache.put(key, data);
      if (mounted) setState(() => _data = data);
    } on JellyfinException catch (e) {
      if (mounted && !silent) setState(() => _error = describeJellyfinError(e)); // keep cached content on failure
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = widget.layout.topPadding;

    final Widget body;
    if (_loading) {
      body = const Center(child: FCircularProgress());
    } else if (_error != null || _data == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text(_error ?? 'Nothing to show'),
            FButton(
              mainAxisSize: .min,
              onPress: _load,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    } else {
      body = CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: topPadding + widget.popoutGap)),
          ...widget.layout.buildSlivers(context, _data!),
          SliverToBoxAdapter(child: SizedBox(height: 8 + widget.popoutGap)),
        ],
      );
    }

    // Popout: tapping any empty space closes it (cards absorb their own taps), and each
    // info card shows its own close button.
    if (widget.popout) {
      final isPhone = isPhoneLayout(context);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: _PopoutScope(
          gap: widget.popoutGap,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isPhone ? 12 : 24),
              child: body,
            ),
          ),
        ),
      );
    }

    // Layouts with a floating back button use it in every state (loading, error and loaded),
    // so the button never changes style or position.
    if (widget.layout.floatingBackButton) {
      return FScaffold(
        child: Stack(
          children: [
            body,
            Positioned(
              top: topPadding + widget.layout.backButtonOffset.dy,
              left: widget.layout.backButtonOffset.dx,
              child: _FloatingIconButton(
                icon: appIcons.back,
                label: 'Back',
                filled: _scrolled,
                onPress: () => context.pop(),
              ),
            ),
          ],
        ),
      );
    }

    final back = [FHeaderAction.back(onPress: () => context.pop())];
    final title = _data == null ? null : widget.layout.headerTitle(_data!);
    final header = title == null
        ? FHeader.nested(prefixes: back)
        : FHeader.nested(title: Text(title), prefixes: back);

    return FScaffold(header: header, child: body);
  }
}

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

// ─── Backdrop banner (collections, movies) ───────────────────────────────────

/// An item's backdrop, with a parallax effect and its logo in the bottom-left.
class _BackdropBanner extends StatelessWidget {
  const _BackdropBanner({required this.item, required this.topPadding});

  final JellyfinItem item;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final client = jellyfin.client!;
    final colors = context.theme.colors;
    final isPhone = isPhoneLayout(context);

    final backdrops = item.raw['BackdropImageTags'] as List?;
    final backdropTag = backdrops != null && backdrops.isNotEmpty
        ? backdrops.first as String
        : null;
    final logoTag = item.imageTags['Logo'];

    return _TapShield(
      child: Container(
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: isPhone ? 16 / 9 : 21 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (backdropTag != null)
                  _ParallaxBackdrop(
                    topPadding: topPadding,
                    child: Image.network(
                      client.images.url(
                        itemId: item.id,
                        type: JellyfinImagesApi.typeBackdrop,
                        tag: backdropTag,
                        fillWidth: 1600,
                        quality: 90,
                      ),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter, // crop from the bottom, keep the top of the image
                      errorBuilder: (_, _, _) =>
                          ColoredBox(color: colors.muted),
                    ),
                  )
                else
                  ColoredBox(color: colors.muted),

                // Darkens the bottom so the logo stands out on any backdrop.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.4, 1.0],
                      colors: [Color(0x00000000), Color(0xB3000000)],
                    ),
                  ),
                ),

                Positioned(
                  left: 16,
                  bottom: 16,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isPhone ? 200 : 360,
                      maxHeight: isPhone ? 56 : 96,
                    ),
                    child: logoTag != null
                        ? Image.network(
                      client.images.url(
                        itemId: item.id,
                        type: JellyfinImagesApi.typeLogo,
                        tag: logoTag,
                        fillWidth: 720,
                      ),
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomLeft,
                    )
                        : Text(
                      // No logo: the name, in large white text.
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.typography.display.xl2
                          .copyWith(
                        color: const Color(0xFFFFFFFF),
                        shadows: const [
                          Shadow(
                            blurRadius: 8,
                            color: Color(0x99000000),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // ── Close (popouts only) ──
                if (_PopoutScope.of(context))
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Focus(
                      // Doesn't take focus itself: notices when the button gets it from the keyboard or remote,
                      // and scrolls the popout back to the top so the whole banner is in view.
                      canRequestFocus: false,
                      skipTraversal: true,
                      onFocusChange: (hasFocus) {
                        if (!hasFocus || FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
                        Scrollable.maybeOf(context)?.position.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      child: _FloatingIconButton(
                        icon: appIcons.close,
                        label: 'Close',
                        filled: true,
                        autofocus:
                        FocusManager.instance.highlightMode ==
                            FocusHighlightMode.traditional,
                        onPress: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Moves its child down at a fraction of the scroll speed once the banner reaches the top
/// of the view, so the image appears to scroll more slowly than the page.
class _ParallaxBackdrop extends StatelessWidget {
  const _ParallaxBackdrop({required this.topPadding, required this.child});

  final double topPadding;
  final Widget child;

  static const _speed = 0.7; // 0 = no parallax, 1 = the image stays fixed

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.of(context).position;
    final start = topPadding + _PopoutScope.gapOf(context); // where the banner sits before scrolling
    return AnimatedBuilder(
      animation: position,
      builder: (context, child) {
        // Start only once the banner's top edge has scrolled out of view,
        // so no gap ever opens above the image.
        final scrolledPastTop = math.max(0.0, position.pixels - start);
        return Transform.translate(
          offset: Offset(0, scrolledPastTop * _speed),
          child: child,
        );
      },
      child:
      child, // the image itself isn't rebuilt while scrolling, only moved
    );
  }
}

// ─── Collection pieces ───────────────────────────────────────────────────────

/// Count, year span and age rating, then the description, genres and movies.
class _CollectionInfoCard extends StatelessWidget {
  const _CollectionInfoCard({required this.collection, required this.items});

  final JellyfinItem collection;
  final List<JellyfinItem> items;

  /// US film and TV ratings, mildest to strictest, used to find the collection's range.
  static const _ratingOrder = [
    'G',
    'TV-Y',
    'TV-Y7',
    'TV-G',
    'PG',
    'TV-PG',
    'PG-13',
    'TV-14',
    'R',
    'TV-MA',
    'NC-17',
  ];

  /// "2009–2022", or a single year if every movie shares it.
  String? get _years {
    final years = [
      for (final item in items)
        if (item.raw['ProductionYear'] case final int year) year,
    ]..sort();
    if (years.isEmpty) return null;
    return years.first == years.last
        ? '${years.first}'
        : '${years.first}–${years.last}';
  }

  /// "PG-13" if every movie shares it, otherwise the mildest–strictest range, e.g. "PG–R".
  String? get _rating {
    final ratings = {
      for (final item in items)
        if (item.raw['OfficialRating'] case final String r when r.isNotEmpty) r,
    };
    if (ratings.isEmpty) return null;

    final known = ratings.where(_ratingOrder.contains).toList()
      ..sort(
            (a, b) => _ratingOrder.indexOf(a).compareTo(_ratingOrder.indexOf(b)),
      );
    if (known.isEmpty) return ratings .first; // a rating system outside the US list: show it as-is
    return known.first == known.last
        ? known.first
        : '${known.first} – ${known.last}';
  }

  /// The collection's own genres, or else every genre its movies use, most common first.
  List<String> get _genres {
    final own =
        (collection.raw['Genres'] as List?)?.cast<String>() ?? const <String>[];
    if (own.isNotEmpty) return own;

    final counts = <String, int>{};
    for (final item in items) {
      for (final genre
      in (item.raw['Genres'] as List?)?.cast<String>() ??
          const <String>[]) {
        counts[genre] = (counts[genre] ?? 0) + 1;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isPhone = isPhoneLayout(context);
    final muted = context.theme.typography.body.sm.copyWith(
      color: colors.mutedForeground,
    );
    final description = (collection.raw['Overview'] as String?)?.trim();
    final years = _years;
    final rating = _rating;
    final genres = _genres;

    return _DetailCard(
      showClose: false,
      edgeToEdge: true,
      child: _CardColumn(
        children: [
          // ── Count, years, age rating ──
          _FactsRow(
            children: [
              Text(
                '${items.length} ${items.length == 1 ? 'title' : 'titles'}',
                style: muted,
              ),
              if (years != null) Text(years, style: muted),
              if (rating != null) _RatingBadge(rating),
            ],
          ),

          // ── Description ──
          if (description != null && description.isNotEmpty)
            ExpandableText(
              description,
              limit: isPhone ? 150 : 400,
              style: context.theme.typography.body.md,
            ),

          // ── Genres ──
          if (genres.isNotEmpty) _GenreButtons(genres),

          // ── Movies ──
          if (items.isNotEmpty) ...[
            const _CardDivider(),
            Text('Movies', style: context.theme.typography.display.lg),
            _InlineItemGrid(items),
          ],
        ],
      ),
    );
  }
}

// ─── Movie pieces ────────────────────────────────────────────────────────────

/// Year, runtime, age rating and score, then Play, the description, genres and the cast.
class _MovieInfoCard extends StatelessWidget {
  const _MovieInfoCard({required this.movie});

  final JellyfinItem movie;

  /// "2h 42m" from Jellyfin's runtime (stored in 100-nanosecond ticks).
  String? get _runtime {
    final ticks = movie.raw['RunTimeTicks'];
    if (ticks is! int || ticks <= 0) return null;
    final minutes = ticks ~/ 600000000;
    final h = minutes ~/ 60, m = minutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// Actors only, in billing order, as Jellyfin lists them.
  List<Map<String, dynamic>> get _cast => [
    for (final p in (movie.raw['People'] as List?) ?? const [])
      if (p is Map<String, dynamic> && p['Type'] == 'Actor') p,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isPhone = isPhoneLayout(context);
    final muted = context.theme.typography.body.sm.copyWith(
      color: colors.mutedForeground,
    );

    final year = movie.raw['ProductionYear'];
    final runtime = _runtime;
    final rating = movie.raw['OfficialRating'] as String?;
    final score = movie.raw['CommunityRating'] as num?;
    final description = (movie.raw['Overview'] as String?)?.trim();
    final genres =
        (movie.raw['Genres'] as List?)?.cast<String>() ?? const <String>[];
    final cast = _cast;

    return _DetailCard(
      showClose: false,
      edgeToEdge: true,
      child: _CardColumn(
        children: [
          // ── Year, runtime, age rating, score ──
          _FactsRow(
            children: [
              if (year != null) Text('$year', style: muted),
              if (runtime != null) Text(runtime, style: muted),
              if (rating != null && rating.isNotEmpty) _RatingBadge(rating),
              if (score != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Icon(appIcons.star, size: 14, color: colors.primary, fill: 1),
                    Text(score.toStringAsFixed(1), style: muted),
                  ],
                ),
            ],
          ),

          // ── Play, Favorite ──
          ScrollIntoViewOnFocus(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FButton(
                  mainAxisSize: .min,
                  onPress: () => context.push('/play/${movie.id}'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      Icon(appIcons.play, size: 18, fill: 1),
                      const Text('Play'),
                    ],
                  ),
                ),
                _FavoriteButton(item: movie),
              ],
            ),
          ),

          // ── Description ──
          if (description != null && description.isNotEmpty)
            ExpandableText(
              description,
              limit: isPhone ? 150 : 400,
              style: context.theme.typography.body.md,
            ),

          // ── Genres ──
          if (genres.isNotEmpty) _GenreButtons(genres),

          // ── Cast ──
          if (cast.isNotEmpty) ...[
            const _CardDivider(),
            Text('Cast', style: context.theme.typography.display.lg),
            _EdgeToEdge(
              // Runs to the card's edges, so the cast scrolls all the way across.
              builder: (padding) => ScrollIntoViewOnFocus(
                child: SizedBox(
                  height: 155,
                  child: FocusRow(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: padding,
                      itemCount: cast.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => _CastTile(person: cast[i]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Series pieces ───────────────────────────────────────────────────────────

/// Years, season count, age rating and score, then the description, genres,
/// a season picker and the chosen season's episodes.
class _SeriesInfoCard extends StatefulWidget {
  const _SeriesInfoCard({required this.series, required this.seasons});

  final JellyfinItem series;
  final List<JellyfinItem> seasons;

  @override
  State<_SeriesInfoCard> createState() => _SeriesInfoCardState();
}

class _SeriesInfoCardState extends State<_SeriesInfoCard> {
  late JellyfinItem? _season = widget.seasons.firstOrNull;
  final _episodes =
  <String, List<JellyfinItem>>{}; // season id → its episodes, once loaded
  String? _loadingSeasonId;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_season != null) _loadEpisodes(_season!);
  }

  Future<void> _loadEpisodes(JellyfinItem season) async {
    if (_episodes.containsKey(season.id)) return; // already loaded: switching back is instant

    final cacheKey = 'episodes:${season.id}';
    if (appCache.isFresh(cacheKey)) {
      setState(
            () =>
        _episodes[season.id] = appCache.peek<List<JellyfinItem>>(cacheKey)!,
      );
      return;
    }

    setState(() {
      _loadingSeasonId = season.id;
      _error = null;
    });
    try {
      final page = await jellyfin.client!.tvShows.episodes(
        seriesId: widget.series.id,
        seasonId: season.id,
        fields: const ['Overview'],
      );
      if (mounted) setState(() => _episodes[season.id] = page.items);
      appCache.put(cacheKey, page.items);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = describeJellyfinError(e));
    } finally {
      if (mounted && _loadingSeasonId == season.id) setState(() => _loadingSeasonId = null);
    }
  }

  /// "2008–2013", "2019–present" for a show still airing, or a single year.
  String? get _years {
    final start = widget.series.raw['ProductionYear'];
    if (start is! int) return null;
    if (widget.series.raw['Status'] == 'Continuing') return '$start–present';
    final end = DateTime.tryParse(
      (widget.series.raw['EndDate'] as String?) ?? '',
    )?.year;
    return end == null || end == start ? '$start' : '$start–$end';
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final colors = context.theme.colors;
    final isPhone = isPhoneLayout(context);
    final muted = context.theme.typography.body.sm.copyWith(
      color: colors.mutedForeground,
    );

    final years = _years;
    final seasonCount = widget.seasons.length;
    final rating = series.raw['OfficialRating'] as String?;
    final score = series.raw['CommunityRating'] as num?;
    final description = (series.raw['Overview'] as String?)?.trim();
    final genres =
        (series.raw['Genres'] as List?)?.cast<String>() ?? const <String>[];
    final season = _season;
    final episodes = season == null ? null : _episodes[season.id];

    return _DetailCard(
      showClose: false,
      edgeToEdge: true,
      child: _CardColumn(
        children: [
          // ── Years, seasons, age rating, score ──
          _FactsRow(
            children: [
              if (years != null) Text(years, style: muted),
              if (seasonCount > 0)
                Text(
                  '$seasonCount ${seasonCount == 1 ? 'season' : 'seasons'}',
                  style: muted,
                ),
              if (rating != null && rating.isNotEmpty) _RatingBadge(rating),
              if (score != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Icon(appIcons.star, size: 14, color: colors.primary, fill: 1),
                    Text(score.toStringAsFixed(1), style: muted),
                  ],
                ),
            ],
          ),

          // ── Play, Favorite ──
          ScrollIntoViewOnFocus(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SeriesPlayButton(series: series, seasons: widget.seasons),
                _FavoriteButton(item: series),
              ],
            ),
          ),

          // ── Description ──
          if (description != null && description.isNotEmpty)
            ExpandableText(
              description,
              limit: isPhone ? 150 : 400,
              style: context.theme.typography.body.md,
            ),

          // ── Genres ──
          if (genres.isNotEmpty) _GenreButtons(genres),

          // ── Seasons and episodes ──
          if (season != null) ...[
            const _CardDivider(),
            // ── Seasons: a compact dropdown on phones (touch only); buttons elsewhere, which work
            // with a remote (a dropdown traps the arrow keys) ──
            if (isPhone)
              SizedBox(
                width: 240,
                child: FSelect<JellyfinItem>(
                  items: {for (final s in widget.seasons) s.name: s},
                  control: FSelectControl.lifted(
                    value: season,
                    onChange: (picked) {
                      if (picked == null || picked.id == season.id) return;
                      setState(() => _season = picked);
                      _loadEpisodes(picked);
                    },
                  ),
                ),
              )
            else
              ScrollIntoViewOnFocus(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8, // many seasons flow onto more lines instead of scrolling sideways
                  children: [
                    for (final s in widget.seasons)
                      FButton(
                        variant: s.id == season.id
                            ? .primary
                            : .outline, // the current season stands out
                        size: .sm,
                        mainAxisSize: .min,
                        onPress: () {
                          if (s.id == season.id) return;
                          setState(() => _season = s);
                          _loadEpisodes(s);
                        },
                        child: Text(s.name),
                      ),
                  ],
                ),
              ),
            if (_loadingSeasonId == season.id && episodes == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: FCircularProgress()),
              )
            else if (_error != null && episodes == null)
              Text(_error!, style: muted)
            else if (episodes != null && episodes.isEmpty)
                Text('No episodes in this season yet.', style: muted)
              else if (episodes != null)
                  Column(
                    spacing: 8,
                    children: [
                      for (final episode in episodes)
                        _EpisodeTile(episode: episode),
                    ],
                  ),
          ],
        ],
      ),
    );
  }
}

/// One episode: thumbnail on the left; number, title, runtime, air date and description beside it.
/// Lifts on hover or remote focus, and plays when selected.
class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode});

  final JellyfinItem episode;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String? get _runtime {
    final ticks = episode.raw['RunTimeTicks'];
    if (ticks is! int || ticks <= 0) return null;
    final minutes = ticks ~/ 600000000;
    final h = minutes ~/ 60, m = minutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// "Jan 20, 2008" from the episode's premiere date.
  String? get _airDate {
    final date = DateTime.tryParse(
      (episode.raw['PremiereDate'] as String?) ?? '',
    );
    return date == null
        ? null
        : '${_months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isPhone = isPhoneLayout(context);
    final number = episode.raw['IndexNumber'];
    final tag = episode.imageTags['Primary']; // an episode's Primary image is its 16:9 thumbnail
    final overview = (episode.raw['Overview'] as String?)?.trim();
    final details = [_runtime, _airDate].whereType<String>().join(' · ');
    final thumbWidth = isPhone ? 140.0 : 240.0;

    return ScrollIntoViewOnFocus(
      alignment: 0.4, // episodes are tall rows: settle a little lower so the previous one stays visible
      child: HoverLift(
        builder: (context, active) => FTappable(
          onPress: () => context.push('/play/${episode.id}'),
          child: AnimatedScale(
            scale: active ? 1.0 : 0.98, // a gentle lift: rows are wide, so a small scale is plenty
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                // ── Thumbnail ──
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(
                      color: active ? colors.primary : const Color(0x00000000),
                      width: 2.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: thumbWidth,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            tag == null
                                ? ColoredBox(
                              color: colors.muted,
                              child: Icon(
                                appIcons.play,
                                color: colors.mutedForeground,
                                fill: 1,
                              ),
                            )
                                : Image.network(
                              jellyfin.client!.images.url(
                                itemId: episode.id,
                                type: JellyfinImagesApi.typePrimary,
                                tag: tag,
                                fillWidth: (thumbWidth * 2).round(),
                                quality: 90,
                              ),
                              fit: BoxFit.cover,
                            ),
                            if (watchProgress(episode) case final progress?)
                              Positioned(
                                left: 6,
                                right: 6,
                                bottom: 6,
                                child: WatchProgressBar(progress),
                              ),
                            if (isWatched(episode))
                              const Positioned(
                                top: 6,
                                right: 6,
                                child: WatchedBadge(size: 20),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Text ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        number != null
                            ? '$number. ${episode.name}'
                            : episode.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.typography.body.md.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details,
                          style: context.theme.typography.body.xs.copyWith(
                            color: colors.mutedForeground,
                          ),
                        ),
                      if (overview != null && overview.isNotEmpty)
                        Text(
                          overview,
                          maxLines: isPhone ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: context.theme.typography.body.sm,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An actor in the cast row: photo, name and character. Lifts on hover or remote focus.
class _CastTile extends StatelessWidget {
  const _CastTile({required this.person});

  final Map<String, dynamic> person;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final id = person['Id'] as String;
    final name = (person['Name'] as String?) ?? '';
    final role = person['Role'] as String?;
    final tag = person['PrimaryImageTag'] as String?;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join();

    return HoverLift(
      builder: (context, active) => FTappable(
        onPress: () => openPerson(context, id),
        child: SizedBox(
          width: 110,
          child: Column(
            spacing: 4,
            children: [
              AnimatedScale(
                scale: active ? 1.0 : 0.94,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  // Hovered or focused: a ring drawn over the photo's edge (it takes up no space).
                  foregroundDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active ? colors.primary : const Color(0x00000000),
                      width: 2.5,
                    ),
                  ),
                  child: ClipOval(
                    child: SizedBox.square(
                      dimension: 96,
                      child: tag == null
                          ? ColoredBox(
                        color: colors.muted,
                        child: Center(
                          child: Text(
                            initials,
                            style: TextStyle(color: colors.mutedForeground),
                          ),
                        ),
                      )
                          : Image.network(
                        jellyfin.client!.images.url(
                          itemId: id,
                          type: JellyfinImagesApi.typePrimary,
                          tag: tag,
                          fillWidth: 192,
                          quality: 90,
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.theme.typography.body.xs,
              ),
              if (role != null && role.isNotEmpty)
                Text(
                  role,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.body.xs.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
        final active =
            states.contains(FTappableVariant.hovered) ||
                states.contains(FTappableVariant.focused);
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

// ─── Action buttons ──────────────────────────────────────────────────────────

/// Toggles an item as a favorite in Jellyfin. Updates instantly, and reverts if the server fails.
class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({required this.item});

  final JellyfinItem item;

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  // Jellyfin includes the user's own data (favorite, watched, ...) with each item.
  late bool _favorite =
      ((widget.item.raw['UserData'] as Map?)?['IsFavorite'] as bool?) ?? false;
  bool _saving = false;

  Future<void> _toggle() async {
    if (_saving) return;
    final next = !_favorite;
    setState(() {
      _favorite = next; // show the change right away
      _saving = true;
    });
    try {
      await jellyfin.client!.userData.setFavorite(widget.item.id, next);
      favoritesChanged.value++; // tell the Favorites page to refresh
      // Cached pages for this item, and the Favorites list, now show the wrong heart.
      appCache.invalidateWhere(
            (key) => key.endsWith(':${widget.item.id}') || key == 'favorites',
      );
    } on JellyfinException {
      if (mounted) setState(() => _favorite = !next); // the server refused: undo
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FButton(
    variant: _favorite ? .secondary : .outline,
    mainAxisSize: .min,
    onPress: _toggle,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Icon(
          _favorite ? appIcons.favorite : appIcons.favoriteOutline,
          size: 18,
          color: _favorite ? context.theme.colors.primary : null,
          fill: _favorite ? 1 : 0,
        ),
        Text(_favorite ? 'Favorited' : 'Favorite'),
      ],
    ),
  );
}

/// Plays the series from where you left off: the next unwatched episode,
/// or the very first episode for a show you haven't started.
class _SeriesPlayButton extends StatefulWidget {
  const _SeriesPlayButton({required this.series, required this.seasons});

  final JellyfinItem series;
  final List<JellyfinItem> seasons;

  @override
  State<_SeriesPlayButton> createState() => _SeriesPlayButtonState();
}

class _SeriesPlayButtonState extends State<_SeriesPlayButton> {
  JellyfinItem? _next;

  @override
  void initState() {
    super.initState();
    _findNext();
  }

  Future<void> _findNext() async {
    final client = jellyfin.client!;
    try {
      // Jellyfin's "Next Up": the next episode after the last one you watched.
      final nextUp = await client.tvShows.nextUp(
        seriesId: widget.series.id,
        limit: 1,
        enableResumable: true,
      );
      var next = nextUp.items.firstOrNull;

      // Not started yet: fall back to the first episode of the first season.
      if (next == null && widget.seasons.isNotEmpty) {
        final first = await client.tvShows.episodes(
          seriesId: widget.series.id,
          seasonId: widget.seasons.first.id,
        );
        next = first.items.firstOrNull;
      }
      if (mounted) setState(() => _next = next);
    } on JellyfinException {
      // Leave the button disabled if nothing can be found.
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = _next;
    final season = next?.raw['ParentIndexNumber'];
    final episode = next?.raw['IndexNumber'];
    final label = next == null
        ? 'Play'
        : season != null && episode != null
        ? 'Play S$season:E$episode'
        : 'Play';

    return FButton(
      mainAxisSize: .min,
      onPress: next == null
          ? null
          : () => context.push('/play/${next.id}'), // disabled until found
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [Icon(appIcons.play, size: 18, fill: 1), Text(label)],
      ),
    );
  }
}