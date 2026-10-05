import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import '../theme/tappable_states.dart';
import '../utils/app_cache.dart';
import '../utils/focus_rows.dart';
import '../utils/format.dart';
import '../utils/item_format.dart';
import '../utils/jellyfin_controller.dart';
import '../utils/orientation.dart';
import 'expandable_text.dart';
import 'hover_lift.dart';
import 'person_tile.dart';
import 'poster_card.dart';
import 'scroll_into_view.dart';

part 'detail_blocks.dart';
part 'detail_cards.dart';

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

/// Plays an item: a movie (or episode) directly, a series from where you left off, or a
/// collection through from its first unwatched title.
Future<void> playItem(BuildContext context, JellyfinItem item) async {
  final router = GoRouter.of(context); // grab it before any await
  switch (item.type) {
    case JellyfinItemKind.series:
      final episode = await nextEpisodeFor(item.id);
      if (episode != null) router.push('/play/${episode.id}');
    case 'BoxSet':
      try {
        final data = await collectionDetails(item.id)(jellyfin.client!);
        playQueue(router, collectionQueue(data.children));
      } on JellyfinException {
        // Couldn't load the collection: nothing to play.
      }
    default:
      router.push('/play/${item.id}');
  }
}

/// The titles to play through for a collection, as item ids: in order from the first one
/// you haven't finished, or all of them in random order with [shuffle].
/// Only movies and videos play directly; a series inside a collection is left out.
List<String> collectionQueue(List<JellyfinItem> items, {bool shuffle = false}) {
  final playable = [
    for (final item in items)
      if (item.type == JellyfinItemKind.movie ||
          item.type == JellyfinItemKind.episode ||
          item.type == 'Video')
        item,
  ];
  if (shuffle) return [for (final item in playable) item.id]..shuffle();

  final firstUnwatched = playable.indexWhere(
        (item) => (item.raw['UserData'] as Map?)?['Played'] != true,
  );
  final from = firstUnwatched == -1 ? 0 : firstUnwatched; // all watched: from the top
  return [for (final item in playable.skip(from)) item.id];
}

/// Opens the player on the first of [ids], playing the rest after it.
void playQueue(GoRouter router, List<String> ids) {
  if (ids.isEmpty) return;
  router.push(
    Uri(path: '/play/${ids.first}', queryParameters: {'queue': ids.join(',')}).toString(),
  );
}

/// The episode to play next in a series: Jellyfin's "Next Up", or else the first episode
/// of the first regular season (skipping Specials).
///
/// _SeriesPlayButton below works this out again on its own, falling back to the first
/// *listed* season rather than skipping Specials. Left as two routines for this pass: folding
/// one into the other changes what Play does for a show whose first season is Specials,
/// which is a behaviour call rather than a tidy-up.
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
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isPhone ? 12 : 24),
            child: body,
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
