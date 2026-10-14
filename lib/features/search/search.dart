import 'dart:async';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/storage/app_cache.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../detail/detail_page.dart';
import '../detail/person_tile.dart';
import '../library/poster_card.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.query});

  /// A search to run straight away, from /search?q=... (the sidebar's search box).
  final String? query;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _lastSearched = '';
  String? _routeQuery;
  int _requestId = 0;

  List<JellyfinItem> _results = const [];
  List<JellyfinItem> _people = const [];
  List<JellyfinItem> _suggestions = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onTextChanged);
    _takeRouteQuery();
    _loadSuggestions();
  }

  /// A search submitted from the sidebar arrives as /search?q=..., passed in as [SearchScreen.query].
  void _takeRouteQuery() {
    final q = widget.query;
    if (q != null && q != _routeQuery) {
      _routeQuery = q;
      _query.text = q; // triggers _onTextChanged, which runs the search
    }
  }

  @override
  void didUpdateWidget(covariant SearchScreen old) {
    super.didUpdateWidget(old);
    _takeRouteQuery(); // a new search while this page is already open
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_query.text == _lastSearched) {
      return; // cursor moves also notify; ignore them
    }
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
          () => _search(_query.text),
    );
  }

  Future<void> _search(String text) async {
    final query = text.trim();
    _lastSearched = text;
    final client = jellyfin.client;
    if (query.isEmpty || client == null) {
      setState(() {
        _results = const [];
        _people = const [];
        _error = null;
      });
      return;
    }

    final id = ++_requestId;
    setState(() => _loading = true);
    try {
      final (page, people) = await (
      client.items.list(
        searchTerm: query,
        includeItemTypes: const [
          JellyfinItemKind.movie,
          JellyfinItemKind.series,
        ],
        recursive: true,
        sortBy: const ['SortName'],
        limit: 60,
      ),
      client.persons.list(
        searchTerm: query,
        personTypes: const ['Actor'],
        limit: 20,
      ),
      ).wait;
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = page.items;
        _people = people.items;
        _error = null;
      });
    } on JellyfinException catch (e) {
      if (mounted && id == _requestId) {
        setState(() => _error = describeJellyfinError(e));
      }
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  /// Shown while the search box is empty: suggestions from your history, or random titles as a fallback.
  Future<void> _loadSuggestions() async {
    const cacheKey = 'search:suggestions';
    if (appCache.peek<List<JellyfinItem>>(cacheKey) case final cached?) {
      setState(() => _suggestions = cached);
      if (appCache.isFresh(cacheKey)) return;
    }
    final client = jellyfin.client;
    if (client == null) return;
    try {
      var items = (await client.suggestions.list(
        mediaType: const ['Video'],
        type: const [JellyfinItemKind.movie, JellyfinItemKind.series],
        limit: 24,
      )).items;

      // Little or no watch history: show a random mix instead.
      if (items.isEmpty) {
        items = (await client.items.list(
          includeItemTypes: const [
            JellyfinItemKind.movie,
            JellyfinItemKind.series,
          ],
          recursive: true,
          sortBy: const ['Random'],
          limit: 24,
        )).items;
      }
      appCache.put(cacheKey, items);
      if (mounted) setState(() => _suggestions = items);
    } on JellyfinException {
      // Suggestions are a nice extra; if they fail, the plain empty message shows instead.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        TextField(
          controller: _query,
          autofocus: _routeQuery == null, // open the keyboard when arriving from the bottom bar
          textInputAction: TextInputAction.search,
          onSubmitted: (text) {
            _debounce?.cancel();
            _search(text);
          },
          decoration: InputDecoration(
            hintText: 'Search movies, shows, and actors',
            prefixIcon: Icon(appIcons.search, fill: 1),
            // A clear button while there's something to clear.
            suffixIcon: ListenableBuilder(
              listenable: _query,
              builder: (context, _) => _query.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(onPressed: _query.clear, icon: Icon(appIcons.close), tooltip: 'Clear'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: _buildResults(context)),
      ],
    ),
    ),
  );

  Widget _buildResults(BuildContext context) {
    final muted = context.text.bodyLarge?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return Center(child: Text(_error!));
    if (_query.text.trim().isEmpty) {
      if (_suggestions.isEmpty) {
        return Center(child: Text('Search your library', style: muted));
      }
      final view = libraryViewFor(context);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Suggested For You',
                style: context.text.titleLarge,
              ),
            ),
          ),
          SliverGrid.builder(
            gridDelegate: libraryGridDelegate(view),
            itemCount: _suggestions.length,
            itemBuilder: (context, i) => PosterCard(
              item: _suggestions[i],
              view: view,
              onPress: () => openItem(context, _suggestions[i]),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      );
    }

    if (_results.isEmpty && _people.isEmpty) {
      return Center(
        child: Text('No results for "${_query.text.trim()}"', style: muted),
      );
    }

    final view = libraryViewFor(context);
    return CustomScrollView(
      slivers: [
        if (_people.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionTitle(context, 'People')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _people.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => PersonTile(
                  person: _people[i],
                  onPress: () => openPerson(context, _people[i].id),
                ),
              ),
            ),
          ),
        ],
        if (_results.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionTitle(context, 'Movies & Shows')),
          SliverGrid.builder(
            gridDelegate: libraryGridDelegate(view),
            itemCount: _results.length,
            itemBuilder: (context, i) => PosterCard(
              item: _results[i],
              view: view,
              onPress: () => openItem(context, _results[i]),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Text(text, style: context.text.titleLarge),
  );
}