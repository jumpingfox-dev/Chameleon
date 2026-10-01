import 'dart:async';
import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import '../utils/focus_rows.dart';
import '../utils/home_layout.dart';
import '../utils/jellyfin_controller.dart';
import 'detail_page.dart';
import 'poster_card.dart';
import 'scroll_into_view.dart';

// ─── Definitions ─────────────────────────────────────────────────────────────

/// What a section loaded: its items, and optionally a title that replaces the default
/// (e.g. "Because you watched Dune").
class HomeModuleContent {
  const HomeModuleContent(this.items, {this.title});

  final List<JellyfinItem> items;
  final String? title;
}

/// Loads a section's content. [module] says what it shows (e.g. which collection).
typedef HomeModuleLoader = Future<HomeModuleContent> Function(
  JellyfinClient client,
  HomeModule module,
);

/// What a kind of section shows and how to load it.
class HomeModuleSpec {
  const HomeModuleSpec({
    required this.title,
    required this.description,
    required this.icon,
    required this.load,
    this.view,
  });

  final String title;
  final String description;
  final IconData Function(AppIconSet icons) icon;
  final HomeModuleLoader load;

  /// A fixed default view, or null for posters on phones and thumbnails on wider screens.
  final LibraryView? view;
}

const _moviesAndShows = [JellyfinItemKind.movie, JellyfinItemKind.series];

/// Every section's definition. To add a new kind: add it to HomeModuleType, then here.
final homeModuleSpecs = <HomeModuleType, HomeModuleSpec>{
  HomeModuleType.carousel: HomeModuleSpec(
    title: 'Featured',
    description: 'A rotating banner of highlights',
    icon: (i) => i.featured,
    load: _featured,
  ),
  HomeModuleType.continueWatching: HomeModuleSpec(
    title: 'Continue Watching',
    description: "Movies and episodes you've started",
    icon: (i) => i.continueWatching,
    view: LibraryView.thumbnail,
    load: (client, _) async => HomeModuleContent(
      (await client.items.resume(mediaTypes: const ['Video'], limit: 20)).items,
    ),
  ),
  HomeModuleType.nextUp: HomeModuleSpec(
    title: 'Next Up',
    description: "The next episode of shows you're watching",
    icon: (i) => i.shows,
    view: LibraryView.thumbnail,
    load: (client, _) async => HomeModuleContent(
      (await client.tvShows.nextUp(
            limit: 20,
            enableResumable: false,
          )) // in-progress episodes are in Continue Watching
          .items
          .where((item) => item.type == JellyfinItemKind.episode)
          .toList(),
    ),
  ),
  HomeModuleType.favorites: HomeModuleSpec(
    title: 'Favorites',
    description: 'Your favorite movies and shows',
    icon: (i) => i.favorite,
    load: (client, _) async => HomeModuleContent(
      (await client.items.list(
        filters: const ['IsFavorite'],
        includeItemTypes: _moviesAndShows,
        recursive: true,
        sortBy: const ['SortName'],
        limit: 30,
        fields: const ['RecursiveItemCount'],
      )).items,
    ),
  ),
  HomeModuleType.recentlyAdded: HomeModuleSpec(
    title: 'Recently Added',
    description: 'The newest movies and shows on your server',
    icon: (i) => i.recentlyAdded,
    load: (client, _) async => HomeModuleContent(
      (await client.items.list(
        includeItemTypes: _moviesAndShows,
        recursive: true,
        sortBy: const ['DateCreated'],
        descending: true,
        limit: 30,
        fields: const ['RecursiveItemCount'],
      )).items,
    ),
  ),
  HomeModuleType.recentlyAddedMovies: HomeModuleSpec(
    title: 'Recently Added Movies',
    description: 'The newest movies on your server',
    icon: (i) => i.movies,
    load: (client, _) async => HomeModuleContent(
      (await client.items.list(
        includeItemTypes: const [JellyfinItemKind.movie],
        recursive: true,
        sortBy: const ['DateCreated'],
        descending: true,
        limit: 30,
      )).items,
    ),
  ),
  HomeModuleType.recentlyAddedSeries: HomeModuleSpec(
    title: 'Recently Added Shows',
    description: 'Shows with the newest episodes',
    icon: (i) => i.shows,
    load: (client, _) async => HomeModuleContent(
      (await client.items.list(
        includeItemTypes: const [JellyfinItemKind.series],
        recursive: true,
        sortBy: const ['DateLastContentAdded'],
        descending: true,
        limit: 30,
        fields: const ['RecursiveItemCount'],
      )).items,
    ),
  ),
  HomeModuleType.suggested: HomeModuleSpec(
    title: 'Suggested For You',
    description: 'Picks based on what you watch',
    icon: (i) => i.suggested,
    load: _suggested,
  ),
  HomeModuleType.becauseYouWatched: HomeModuleSpec(
    title: 'Because You Watched…',
    description: 'More like the last thing you watched',
    icon: (i) => i.becauseYouWatched,
    load: _becauseYouWatched,
  ),
  HomeModuleType.collection: HomeModuleSpec(
    title: 'Collection',
    description: 'The movies in a collection you choose',
    icon: (i) => i.collection,
    load: _collection,
  ),
  HomeModuleType.genre: HomeModuleSpec(
    title: 'Genre',
    description: 'Movies and shows from a genre you choose',
    icon: (i) => i.genres,
    load: _genre,
  ),
};

// ─── Loaders ─────────────────────────────────────────────────────────────────

/// A random handful of movies and shows that have backdrop art to show off.
Future<HomeModuleContent> _featured(JellyfinClient client, HomeModule _) async {
  final page = await client.items.list(
    includeItemTypes: _moviesAndShows,
    recursive: true,
    sortBy: const ['Random'],
    limit: 30, // more than needed, since some won't have a backdrop
    fields: const ['Overview'],
  );
  final withArt = page.items
      .where(
        (item) => (item.raw['BackdropImageTags'] as List?)?.isNotEmpty ?? false,
      )
      .take(8)
      .toList();
  return HomeModuleContent(withArt);
}

/// Jellyfin's suggestions for this user, or a random mix when there isn't enough history yet.
Future<HomeModuleContent> _suggested(
  JellyfinClient client,
  HomeModule _,
) async {
  var items = (await client.suggestions.list(
    mediaType: const ['Video'],
    type: _moviesAndShows,
    limit: 30,
  )).items;
  if (items.isEmpty) {
    items = (await client.items.list(
      includeItemTypes: _moviesAndShows,
      recursive: true,
      sortBy: const ['Random'],
      limit: 30,
      fields: const ['RecursiveItemCount'],
    )).items;
  }
  return HomeModuleContent(items);
}

/// Titles similar to the last movie or show you watched: same kind, sharing its genres.
Future<HomeModuleContent> _becauseYouWatched(
  JellyfinClient client,
  HomeModule _,
) async {
  final last = (await client.items.list(
    filters: const ['IsPlayed'],
    includeItemTypes: const [JellyfinItemKind.movie, JellyfinItemKind.episode],
    recursive: true,
    sortBy: const ['DatePlayed'],
    descending: true,
    limit: 1,
  )).items.firstOrNull;
  if (last == null) return const HomeModuleContent([]);

  final isEpisode = last.type == JellyfinItemKind.episode;
  final baselineId = isEpisode ? last.raw['SeriesId'] as String? : last.id;
  if (baselineId == null) return const HomeModuleContent([]);
  final baseline = await client.items.byId(baselineId);
  if (baseline == null) return const HomeModuleContent([]);

  final title = 'Because You Watched ${baseline.name}';
  final genres =
      ((baseline.raw['Genres'] as List?)?.cast<String>() ?? const <String>[])
          .take(2)
          .toList();
  if (genres.isEmpty) return HomeModuleContent(const [], title: title);

  final similar = await client.items.list(
    genres: genres,
    includeItemTypes: [
      isEpisode ? JellyfinItemKind.series : JellyfinItemKind.movie,
    ],
    excludeItemIds: [baseline.id],
    recursive: true,
    sortBy: const ['Random'],
    limit: 20,
    fields: const ['RecursiveItemCount'],
  );
  return HomeModuleContent(similar.items, title: title);
}

/// The movies in the chosen collection, in release order.
Future<HomeModuleContent> _collection(
  JellyfinClient client,
  HomeModule module,
) async {
  final id = module.param;
  if (id == null) return const HomeModuleContent([]);
  final page = await client.items.list(
    parentId: id,
    sortBy: const ['ProductionYear', 'SortName'],
    limit: 50,
    fields: const ['RecursiveItemCount'],
  );
  return HomeModuleContent(page.items, title: module.label);
}

/// A random mix of movies and shows from the chosen genre.
Future<HomeModuleContent> _genre(
  JellyfinClient client,
  HomeModule module,
) async {
  final genre = module.param;
  if (genre == null) return const HomeModuleContent([]);
  final page = await client.items.list(
    genres: [genre],
    includeItemTypes: _moviesAndShows,
    recursive: true,
    sortBy: const ['Random'],
    limit: 30,
    fields: const ['RecursiveItemCount'],
  );
  return HomeModuleContent(page.items, title: genre);
}

// ─── Cache ───────────────────────────────────────────────────────────────────

/// How long a section's content is reused before it refreshes.
const homeCacheDuration = Duration(minutes: 10);

class _CachedContent {
  _CachedContent(this.content) : fetchedAt = DateTime.now();

  final HomeModuleContent content;
  final DateTime fetchedAt;

  bool get isFresh => DateTime.now().difference(fetchedAt) < homeCacheDuration;
}

/// Keyed by section id, since two Genre sections show different things.
final _homeCache = <String, _CachedContent>{};

/// Bumped when Home becomes visible again, so stale sections can refresh.
final homeVisible = ValueNotifier<int>(0);

/// Forgets every section's content, e.g. on sign-out.
void clearHomeCache() => _homeCache.clear();

// ─── Section view ────────────────────────────────────────────────────────────

/// One section on the home screen: its title (with edit controls in edit mode) and its content.
class HomeModuleView extends StatefulWidget {
  const HomeModuleView({
    super.key,
    required this.module,
    required this.editing,
    required this.isFirst,
    required this.isLast,
  });

  final HomeModule module;
  final bool editing;
  final bool isFirst;
  final bool isLast;

  @override
  State<HomeModuleView> createState() => _HomeModuleViewState();
}

class _HomeModuleViewState extends State<HomeModuleView>
    with AutomaticKeepAliveClientMixin {
  HomeModuleContent? _content;
  String? _error;

  HomeModuleSpec get _spec => homeModuleSpecs[widget.module.type]!;

  /// The section's view: your choice if you've changed it; otherwise its fixed default;
  /// otherwise posters on phones and thumbnails on wider screens.
  LibraryView _viewFor(BuildContext context) =>
      LibraryView.values.asNameMap()[widget.module.view] ??
      _spec.view ??
      (MediaQuery.sizeOf(context).width < 600
          ? LibraryView.poster
          : LibraryView.thumbnail);

  /// Keeps this section alive when it scrolls off-screen, so it isn't rebuilt and reloaded.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    favoritesChanged.addListener(_load);
    homeVisible.addListener(_refreshIfStale);

    final cached = _homeCache[widget.module.id];
    _content = cached?.content;
    if (cached == null || !cached.isFresh) _load();
  }

  @override
  void dispose() {
    favoritesChanged.removeListener(_load);
    homeVisible.removeListener(_refreshIfStale);
    super.dispose();
  }

  void _refreshIfStale() {
    final cached = _homeCache[widget.module.id];
    if (cached == null || !cached.isFresh) _load();
  }

  Future<void> _load() async {
    final client = jellyfin.client;
    if (client == null) return;
    try {
      final content = await _spec.load(client, widget.module);
      _homeCache[widget.module.id] = _CachedContent(content);
      if (mounted) {
        setState(() {
          _content = content;
          _error = null;
        });
      }
    } on JellyfinException catch (e) {
      if (mounted && _content == null)
        setState(() => _error = describeJellyfinError(e));
    }
  }

  /// View toggle, move up, move down and remove: shown next to the title in edit mode.
  List<Widget> _editControls(BuildContext context) => [
    if (widget.module.type != HomeModuleType.carousel)
      FButton.icon(
        variant: .ghost,
        onPress: () => homeLayout.setView(
          widget.module.id,
          (_viewFor(context) == LibraryView.poster
                  ? LibraryView.thumbnail
                  : LibraryView.poster)
              .name,
        ),
        // Shows the view you'll switch *to*, like the library pages.
        child: _viewFor(context) == LibraryView.poster
            ? const AspectIcon(width: 18, height: 10)
            : const AspectIcon(width: 11, height: 16),
      ),
    FButton.icon(
      variant: .ghost,
      onPress: widget.isFirst
          ? null
          : () => homeLayout.move(widget.module.id, -1),
      child: Icon(appIcons.moveUp, fill: 1),
    ),
    FButton.icon(
      variant: .ghost,
      onPress: widget.isLast
          ? null
          : () => homeLayout.move(widget.module.id, 1),
      child: Icon(appIcons.moveDown, fill: 1),
    ),
    FButton.icon(
      variant: .ghost,
      onPress: () => homeLayout.remove(widget.module.id),
      child: Icon(
        appIcons.remove,
        color: context.theme.colors.destructive,
        fill: 1
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final module = widget.module;
    final isCarousel = module.type == HomeModuleType.carousel;

    // Loaded and empty: hidden entirely, unless you're editing (then it says so).
    if (!widget.editing &&
        _error == null &&
        (_content?.items.isEmpty ?? false)) {
      return const SizedBox.shrink();
    }

    final title =
        _content?.title ?? module.label ?? module.param ?? _spec.title;
    final captions =
        module.type == HomeModuleType.continueWatching ||
        module.type == HomeModuleType.nextUp;

    return ScrollIntoViewOnFocus(
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: 24,
        ), // every visible section: the same gap below it
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            if (!isCarousel || widget.editing)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: context.theme.typography.display.lg,
                    ),
                  ),
                  if (widget.editing)
                    FocusRow(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _editControls(context),
                      ),
                    ),
                ],
              ),
            if (isCarousel)
              _carousel(context)
            else
              _row(context, _viewFor(context), captions: captions),
          ],
        ),
      ),
    );
  }

  Widget _carousel(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final items = _content?.items;
    final muted = context.theme.typography.body.sm.copyWith(
      color: context.theme.colors.mutedForeground,
    );

    final Widget content;
    if (_error != null) {
      content = Center(child: Text(_error!, style: muted));
    } else if (items == null) {
      content = const Center(child: FCircularProgress());
    } else if (items.isEmpty) {
      content = Center(child: Text('Nothing to feature yet', style: muted));
    } else {
      content = _Carousel(items: items);
    }

    return AspectRatio(aspectRatio: isPhone ? 16 / 9 : 21 / 9, child: content);
  }

  Widget _row(BuildContext context, LibraryView view, {bool captions = false}) {
    final tileWidth = view == LibraryView.poster ? 150.0 : 280.0;
    final imageHeight = view == LibraryView.poster
        ? tileWidth * 3 / 2
        : tileWidth * 9 / 16;
    const captionHeight = 44.0;
    final rowHeight = imageHeight + (captions ? captionHeight : 0);
    final muted = context.theme.typography.body.sm.copyWith(
      color: context.theme.colors.mutedForeground,
    );
    final items = _content?.items;

    final Widget content;
    if (_error != null) {
      content = Align(
        alignment: Alignment.centerLeft,
        child: Text(_error!, style: muted),
      );
    } else if (items == null) {
      content = const Center(child: FCircularProgress());
    } else if (items.isEmpty) {
      content = Align(
        alignment: Alignment.centerLeft,
        child: Text('Nothing here yet', style: muted),
      ); // edit mode only
    } else {
      content = FocusRow(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (context, i) {
            final card = PosterCard(
              item: items[i],
              view: view,
              onPress: () => openItem(context, items[i]),
            );
            return SizedBox(
              width: tileWidth,
              child: captions
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: imageHeight, child: card),
                        _TileCaption(items[i]),
                      ],
                    )
                  : card,
            );
          },
        ),
      );
    }

    return SizedBox(height: rowHeight, child: content);
  }
}

// ─── Adding sections ─────────────────────────────────────────────────────────

/// Shown at the bottom of the home screen in edit mode: the sections you can add,
/// and a way back to the default layout.
class AddHomeModules extends StatelessWidget {
  const AddHomeModules({super.key});

  /// Collection and Genre sections need a choice first; everything else is added directly.
  Future<void> _add(BuildContext context, HomeModuleType type) async {
    final client = jellyfin.client;
    if (client == null) return;

    switch (type) {
      case HomeModuleType.collection:
        final picked = await _showOptionPicker(
          context,
          title: 'Choose a collection',
          options: client.items
              .list(
                includeItemTypes: const ['BoxSet'],
                recursive: true,
                sortBy: const ['SortName'],
                limit: 500,
              )
              .then((page) => [for (final c in page.items) (c.id, c.name)]),
        );
        if (picked != null)
          await homeLayout.add(type, param: picked.$1, label: picked.$2);

      case HomeModuleType.genre:
        final picked = await _showOptionPicker(
          context,
          title: 'Choose a genre',
          options: Future.value([for (final g in jellyfin.genres) (g, g)]),
        );
        if (picked != null)
          await homeLayout.add(type, param: picked.$1, label: picked.$2);

      default:
        await homeLayout.add(type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = homeLayout.available;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text('Add a section', style: context.theme.typography.display.lg),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in available)
              FButton(
                variant: .outline,
                mainAxisSize: .min,
                onPress: () => _add(context, type),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    Icon(homeModuleSpecs[type]!.icon(appIcons), size: 18),
                    Text(homeModuleSpecs[type]!.title),
                  ],
                ),
              ),
          ],
        ),
        FButton(
          variant: .ghost,
          mainAxisSize: .min,
          onPress: () => homeLayout.reset(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Icon(appIcons.reset, size: 18, fill: 1),
              const Text('Reset to default layout'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows a searchable list of (value, label) options and returns the one picked, or null.
Future<(String, String)?> _showOptionPicker(
  BuildContext context, {
  required String title,
  required Future<List<(String, String)>> options,
}) {
  return showGeneralDialog<(String, String)>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: context.theme.colors.barrier,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => Center(
      child: _OptionPicker(title: title, options: options),
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _OptionPicker extends StatefulWidget {
  const _OptionPicker({required this.title, required this.options});

  final String title;
  final Future<List<(String, String)>> options;

  @override
  State<_OptionPicker> createState() => _OptionPickerState();
}

class _OptionPickerState extends State<_OptionPicker> {
  final _search = TextEditingController();
  List<(String, String)>? _all;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {})); // filter as you type
    widget.options.then(
      (options) {
        if (mounted) setState(() => _all = options);
      },
      onError: (_) {
        if (mounted) setState(() => _error = "Couldn't load the list.");
      },
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final muted = context.theme.typography.body.sm.copyWith(
      color: context.theme.colors.mutedForeground,
    );
    final query = _search.text.trim().toLowerCase();
    final shown = _all
        ?.where((o) => o.$2.toLowerCase().contains(query))
        .toList();

    final Widget list;
    if (_error != null) {
      list = Center(child: Text(_error!, style: muted));
    } else if (shown == null) {
      list = const Center(child: FCircularProgress());
    } else if (shown.isEmpty) {
      list = Center(child: Text('Nothing found', style: muted));
    } else {
      list = ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: shown.length,
        itemBuilder: (context, i) => FButton(
          variant: .ghost,
          mainAxisAlignment: .start,
          onPress: () => Navigator.of(context).pop(shown[i]),
          child: Text(
            shown[i].$2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return SizedBox(
      width: math.min(420, size.width - 32),
      height: math.min(560, size.height * 0.8),
      child: FCard(
        builder: (context, style, _) => Padding(
          padding: style.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(widget.title, style: context.theme.typography.display.lg),
              FTextField(
                control: .managed(controller: _search),
                hint: 'Search',
                autofocus: true,
              ),
              Expanded(child: list),
              Align(
                alignment: Alignment.centerRight,
                child: FButton(
                  variant: .outline,
                  mainAxisSize: .min,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Carousel ────────────────────────────────────────────────────────────────

/// A rotating banner of featured items. Advances on its own; arrows, dots and swiping move it by hand.
class _Carousel extends StatefulWidget {
  const _Carousel({required this.items});

  final List<JellyfinItem> items;

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  static const _interval = Duration(seconds: 8);

  /// While someone's on the carousel it holds still, unless they've been idle this long
  /// (probably walked away), after which it resumes advancing.
  static const _idleResume = Duration(seconds: 45);

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  bool _engaged = false; // focus or pointer is on the carousel
  DateTime _lastInteraction = DateTime.now();

  /// Shared by whichever slide is showing, so the same button keeps focus when the slide changes.
  final _playFocus = FocusNode();
  final _infoFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _playFocus.dispose();
    _infoFocus.dispose();
    super.dispose();
  }

  void _touch() => _lastInteraction = DateTime.now();

  /// Starts the countdown to the next slide again, e.g. after someone moves it by hand.
  void _restartTimer() {
    _timer?.cancel();
    if (widget.items.length < 2) return;
    _timer = Timer.periodic(_interval, (_) {
      final idle = DateTime.now().difference(_lastInteraction);
      if (_engaged && idle < _idleResume) return; // someone's here: hold still
      _goTo(_page + 1);
    });
  }

  void _setEngaged(bool engaged) {
    _engaged = engaged;
    _touch();
    if (!engaged)
      _restartTimer(); // leaving: a full 8 seconds before the next slide
  }

  /// Slides to a page, wrapping around at either end.
  void _goTo(int page) {
    if (!_controller.hasClients) return;
    final count = widget.items.length;
    _controller.animateToPage(
      ((page % count) + count) % count,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
  }

  /// → from More info goes to the next slide, ← from Play to the previous one.
  /// Between the two buttons, arrows move focus as usual.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    _touch(); // any key press counts as someone being here
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight && _infoFocus.hasFocus) {
      _goTo(_page + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && _playFocus.hasFocus) {
      _goTo(_page - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;

    return MouseRegion(
      onEnter: (_) => _setEngaged(true),
      onExit: (_) => _setEngaged(false),
      onHover: (_) => _touch(),
      child: Focus(
        // Doesn't take focus itself; notices focus on its buttons, and handles ←/→ from them.
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: _setEngaged,
        onKeyEvent: _onKey,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: count,
                onPageChanged: (page) {
                  // Remember which button had focus, so the new slide's matching one gets it.
                  final refocus = _playFocus.hasFocus
                      ? _playFocus
                      : _infoFocus.hasFocus
                      ? _infoFocus
                      : null;
                  setState(() => _page = page);
                  _restartTimer();
                  if (refocus != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) refocus.requestFocus();
                    });
                  }
                },
                itemBuilder: (context, i) => _CarouselSlide(
                  item: widget.items[i],
                  // Only the showing slide gets the shared nodes; the others build plain buttons.
                  playFocus: i == _page ? _playFocus : null,
                  infoFocus: i == _page ? _infoFocus : null,
                ),
              ),

              // ── Dots ──
              if (count > 1)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Row(
                    spacing: 6,
                    children: [
                      for (var i = 0; i < count; i++)
                        GestureDetector(
                          onTap: () => _goTo(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: i == _page ? 20 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? const Color(0xFFFFFFFF)
                                  : const Color(0x80FFFFFF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One slide: the backdrop, a fade for readability, and the logo, details, Play and More info.
class _CarouselSlide extends StatelessWidget {
  const _CarouselSlide({required this.item, this.playFocus, this.infoFocus});

  final JellyfinItem item;
  final FocusNode? playFocus;
  final FocusNode? infoFocus;

  @override
  Widget build(BuildContext context) {
    final client = jellyfin.client!;
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final backdropTag = (item.raw['BackdropImageTags'] as List).first as String;
    final logoTag = item.imageTags['Logo'];
    final overview = (item.raw['Overview'] as String?)?.trim();
    final year = item.raw['ProductionYear'];
    final rating = item.raw['OfficialRating'] as String?;
    final facts = [
      if (year != null) '$year',
      if (rating != null && rating.isNotEmpty) rating,
    ].join('  ·  ');
    const white = Color(0xFFFFFFFF);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        // Click or tap anywhere on the slide to open it. Not focusable: with a remote,
        // the Play and More info buttons are the way in, so ↑ from them goes straight past.
        behavior: HitTestBehavior.opaque,
        onTap: () => openItem(context, item),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              client.images.url(
                itemId: item.id,
                type: JellyfinImagesApi.typeBackdrop,
                tag: backdropTag,
                fillWidth: 1920,
                quality: 90,
              ),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, _, _) =>
                  ColoredBox(color: context.theme.colors.muted),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: [0.0, 0.65],
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.5, 1.0],
                  colors: [Color(0x00000000), Color(0x99000000)],
                ),
              ),
            ),
            Positioned(
              left: isPhone ? 16 : 32,
              bottom: isPhone ? 16 : 32,
              right: isPhone ? 80 : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isPhone ? 180 : 360,
                        maxHeight: isPhone ? 48 : 96,
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
                              item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.theme.typography.display.xl2
                                  .copyWith(color: white),
                            ),
                    ),
                    if (facts.isNotEmpty)
                      Text(
                        facts,
                        style: context.theme.typography.body.sm.copyWith(
                          color: const Color(0xCCFFFFFF),
                        ),
                      ),
                    if (!isPhone && overview != null && overview.isNotEmpty)
                      Text(
                        overview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.typography.body.md.copyWith(
                          color: const Color(0xE6FFFFFF),
                        ),
                      ),
                    if (!isPhone)
                      FocusRow(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8,
                          children: [
                            FButton(
                              focusNode: playFocus,
                              mainAxisSize: .min,
                              onPress: () => playItem(context, item),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 8,
                                children: [Icon(appIcons.play, size: 18, fill: 1), const Text('Play')],
                              ),
                            ),
                            FButton(
                              focusNode: infoFocus,
                              variant: .secondary,
                              mainAxisSize: .min,
                              onPress: () => openItem(context, item),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 8,
                                children: [Icon(appIcons.info, size: 18, fill: 1), const Text('More info')],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Under a Continue Watching or Next Up tile: the show (or movie) name, then
/// "S1:E2 · Episode name" for episodes, or the year for movies.
class _TileCaption extends StatelessWidget {
  const _TileCaption(this.item);

  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final isEpisode = item.type == JellyfinItemKind.episode;
    final title = isEpisode
        ? (item.raw['SeriesName'] as String?) ?? item.name
        : item.name;

    final season = item.raw['ParentIndexNumber'];
    final episode = item.raw['IndexNumber'];
    final subtitle = isEpisode
        ? [
            if (season != null && episode != null) 'S$season:E$episode',
            item.name,
          ].join(' · ')
        : item.raw['ProductionYear']?.toString();

    return Padding(
      // Lines the text up with the artwork, which sits slightly inset until hovered.
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.theme.typography.body.sm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.theme.typography.body.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
        ],
      ),
    );
  }
}
