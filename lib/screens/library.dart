import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';
import '../utils/library_cache.dart';
import '../widgets/detail_page.dart';
import '../widgets/poster_card.dart';

/// Shows one library's movies/shows/albums, or everything in one genre.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.libraryId, this.genre});

  final String? libraryId;
  final String? genre;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _pageSize = 60;

  static final _letters = [
    '#',
    for (var c = 65; c <= 90; c++) String.fromCharCode(c),
  ]; // #, A–Z
  static const _sectionHeaderHeight = 64.0;

  double _gridWidth = 0;
  bool _loading = false;
  String? _error;

  late LibraryCacheEntry _cache;
  late final ScrollController _scroll;

  List<JellyfinItem> get _items => _cache.items;
  int? get _total => _cache.total;
  Set<String>? get _availableLetters => _cache.letters;

  /// This page's cache entry, replaced with an empty one if it's missing or stale.
  LibraryCacheEntry _entryFor(LibraryScreen w) {
    final key = w.genre != null ? 'genre:${w.genre}' : 'library:${w.libraryId}';
    final existing = libraryCache[key];
    if (existing != null && existing.isFresh) return existing;
    return libraryCache[key] = LibraryCacheEntry();
  }

  JellyfinLibrary? get _library =>
      jellyfin.libraries.where((l) => l.id == widget.libraryId).firstOrNull;

  /// The section a title belongs in: A–Z, or # for numbers and symbols.
  String _letterFor(JellyfinItem item) {
    final name = (item.raw['SortName'] as String?) ?? item.name;
    if (name.isEmpty) return '#';
    final first = name[0].toUpperCase();
    return RegExp('[A-Z]').hasMatch(first) ? first : '#';
  }

  /// Groups the loaded items into letter sections: # first, then A to Z.
  List<(String, List<JellyfinItem>)> _groupByLetter() {
    final groups = <String, List<JellyfinItem>>{};
    for (final item in _items) {
      groups.putIfAbsent(_letterFor(item), () => []).add(item);
    }
    final letters = groups.keys.toList()
      ..sort(
        (a, b) => a == '#'
            ? -1
            : b == '#'
            ? 1
            : a.compareTo(b),
      );
    return [for (final letter in letters) (letter, groups[letter]!)];
  }

  /// Which item types to list, based on what kind of library this is.
  List<String> get _itemTypes {
    if (widget.genre != null)
      return const [JellyfinItemKind.movie, JellyfinItemKind.series];
    return switch (_library?.collectionType) {
      'movies' => const [JellyfinItemKind.movie],
      'tvshows' => const [JellyfinItemKind.series],
      'music' => const [JellyfinItemKind.musicAlbum],
      'boxsets' => const ['BoxSet'],
      'playlists' => const [JellyfinItemKind.playlist],
      'musicvideos' => const [JellyfinItemKind.musicVideo],
      //'homevideos' => const [JellyfinItemKind.],
      'photos' => const [JellyfinItemKind.photoAlbum],
      'books' => const [JellyfinItemKind.book],
      //'livetv' => const [JellyfinItemKind.],
      _ => const [JellyfinItemKind.movie, JellyfinItemKind.series],
    };
  }

  bool get _hasMore => _total == null || _items.length < _total!;

  @override
  void initState() {
    super.initState();
    _cache = _entryFor(widget);
    _scroll = ScrollController(
      initialScrollOffset: _cache.scrollOffset,
    ); // back where you left off
    _scroll.addListener(() {
      _cache.scrollOffset = _scroll.offset;
      if (_scroll.position.extentAfter < 600) _loadMore();
    });
    if (_items.isEmpty) _loadMore();
    if (_availableLetters == null) _loadLetterCounts();
  }

  @override
  void didUpdateWidget(LibraryScreen old) {
    super.didUpdateWidget(old);
    if (old.libraryId != widget.libraryId || old.genre != widget.genre) {
      _cache = _entryFor(widget);
      _error = null;
      if (_scroll.hasClients) _scroll.jumpTo(_cache.scrollOffset);
      if (_items.isEmpty) _loadMore();
      if (_availableLetters == null) _loadLetterCounts();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    final client = jellyfin.client;
    if (_loading || !_hasMore || client == null) return;
    setState(() => _loading = true);

    try {
      final page = await client.items.list(
        parentId: widget.libraryId,
        genres: widget.genre == null ? const [] : [widget.genre!],
        includeItemTypes: _itemTypes,
        recursive: true,
        sortBy: const ['SortName'],
        fields: const [
          'SortName',
        ], // needed to group by letter the same way the server sorts
        startIndex: _items.length,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cache.total = page.totalRecordCount;
        _error = null;
      });
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = describeJellyfinError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Asks the server which letters have titles. Only counts are fetched, not items.
  Future<void> _loadLetterCounts() async {
    final client = jellyfin.client;
    if (client == null) return;

    final base = <String, dynamic>{
      'userId': client.userId,
      'Recursive': true,
      'IncludeItemTypes': _itemTypes.join(','),
      if (widget.libraryId != null) 'ParentId': widget.libraryId,
      if (widget.genre != null) 'Genres': widget.genre,
      'Limit': 0,
      'EnableTotalRecordCount': true,
    };

    Future<bool> hasTitles(String letter) async {
      final response = await client.request<Map<String, dynamic>>(
        '/Items',
        queryParameters: {
          ...base,
          // # = anything sorting before "A" (numbers and symbols).
          if (letter == '#') 'NameLessThan': 'A' else 'NameStartsWith': letter,
        },
      );
      return ((response.data?['TotalRecordCount'] as int?) ?? 0) > 0;
    }

    try {
      final results = await Future.wait(_letters.map(hasTitles));
      if (!mounted) return;
      setState(
        () => _cache.letters = {
          for (var i = 0; i < _letters.length; i++)
            if (results[i]) _letters[i],
        },
      );
    } on JellyfinException {
      // If counting fails, leave every letter enabled.
    }
  }

  /// Scrolls to a letter's section, loading pages first if it isn't loaded yet.
  Future<void> _jumpTo(String letter) async {
    bool isLoaded() => _items.any((item) => _letterFor(item) == letter);

    while (!isLoaded() && _hasMore) {
      if (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }
      await _loadMore();
      if (_error != null || !mounted) return;
    }
    if (!isLoaded() || !_scroll.hasClients) return;

    await WidgetsBinding.instance.endOfFrame; // let the new sections lay out
    if (!mounted) return;

    final view = libraryViewFor(context);
    var offset = 0.0;
    for (final (sectionLetter, items) in _groupByLetter()) {
      if (sectionLetter == letter) break;
      offset +=
          _sectionHeaderHeight +
          libraryGridHeight(items.length, _gridWidth, view);
    }

    await _scroll.animateTo(
      offset.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: libraryViewOverride,
    builder: (context, _) {
      final view = libraryViewFor(context);
      return FScaffold(
        header: FHeader(
          title: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                // At least as wide as the header, so there's room to center the letters.
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 2,
                  children: [
                    for (final letter in _letters)
                      FButton(
                        variant: .ghost,
                        size: .xs,
                        mainAxisSize: .min,
                        onPress:
                            _availableLetters == null ||
                                _availableLetters!.contains(letter)
                            ? () => _jumpTo(letter)
                            : null,
                        child: Text(letter),
                      ),
                  ],
                ),
              ),
            ),
          ),
          suffixes: [
            FHeaderAction(
              // Shows the view you'll switch *to*: a tall rectangle for posters, a wide one for thumbnails.
              icon: view == LibraryView.poster
                  ? const AspectIcon(width: 18, height: 10) // 16:9 → thumbnails
                  : const AspectIcon(width: 11, height: 16), // 2:3 → posters
              onPress: () =>
                  libraryViewOverride.value = view == LibraryView.poster
                  ? LibraryView.thumbnail
                  : LibraryView.poster,
            ),
          ],
        ),
        child: _buildBody(context, view),
      );
    },
  );

  Widget _buildBody(BuildContext context, LibraryView view) {
    if (_items.isEmpty && _loading) {
      return const Center(child: FCircularProgress());
    }
    if (_items.isEmpty && _error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text(_error!),
            FButton(
              mainAxisSize: .min,
              onPress: _loadMore,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'Nothing here yet',
          style: context.theme.typography.body.md,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _gridWidth =
            constraints.maxWidth; // used by _jumpTo to calculate positions
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            for (final (letter, items) in _groupByLetter()) ...[
              SliverToBoxAdapter(
                child: SizedBox(
                  height: _sectionHeaderHeight,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        letter,
                        style: context.theme.typography.display.xl,
                      ),
                    ),
                  ),
                ),
              ),
              SliverGrid.builder(
                gridDelegate: libraryGridDelegate(view),
                itemCount: items.length,
                itemBuilder: (context, i) => PosterCard(
                  item: items[i],
                  view: view,
                  onPress: () => openItem(context, items[i]),
                ),
              ),
            ],
            if (_hasMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: FCircularProgress()),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        );
      },
    );
  }
}
