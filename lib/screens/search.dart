import 'dart:async';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';
import '../widgets/poster_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

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
  bool _loading = false;
  String? _error;

  List<JellyfinItem> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _query.addListener(_onTextChanged);
    _loadSuggestions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A search submitted from the top bar arrives as /search?q=...
    final q = GoRouterState.of(context).uri.queryParameters['q'];
    if (q != null && q != _routeQuery) {
      _routeQuery = q;
      _query.text = q; // triggers _onTextChanged, which runs the search
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_query.text == _lastSearched) return; // cursor moves also notify; ignore them
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(_query.text));
  }

  Future<void> _search(String text) async {
    final query = text.trim();
    _lastSearched = text;
    final client = jellyfin.client;
    if (query.isEmpty || client == null) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }

    final id = ++_requestId;
    setState(() => _loading = true);
    try {
      final page = await client.items.list(
        searchTerm: query,
        includeItemTypes: const [JellyfinItemKind.movie, JellyfinItemKind.series],
        recursive: true,
        sortBy: const ['SortName'],
        limit: 60,
      );
      if (!mounted || id != _requestId) return; // a newer search has started; drop this one
      setState(() {
        _results = page.items;
        _error = null;
      });
    } on JellyfinException catch (e) {
      if (mounted && id == _requestId) setState(() => _error = describeJellyfinError(e));
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  /// Shown while the search box is empty: suggestions from your history, or random titles as a fallback.
  Future<void> _loadSuggestions() async {
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
          includeItemTypes: const [JellyfinItemKind.movie, JellyfinItemKind.series],
          recursive: true,
          sortBy: const ['Random'],
          limit: 24,
        )).items;
      }
      if (mounted) setState(() => _suggestions = items);
    } on JellyfinException {
      // Suggestions are a nice extra; if they fail, the plain empty message shows instead.
    }
  }

  void _open(JellyfinItem item) {
    if (item.type == JellyfinItemKind.movie) context.push('/play/${item.id}');
  }

  @override
  Widget build(BuildContext context) => FScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        FTextField(
          control: .managed(controller: _query),
          hint: 'Movies and shows',
          autofocus: _routeQuery == null, // open the keyboard when arriving from the bottom bar
          textInputAction: TextInputAction.search,
          onSubmit: (text) {
            _debounce?.cancel();
            _search(text);
          },
        ),
        const SizedBox(height: 16),
        Expanded(child: _buildResults(context)),
      ],
    ),
  );

  Widget _buildResults(BuildContext context) {
    final muted = context.theme.typography.body.md.copyWith(color: context.theme.colors.mutedForeground);
    if (_loading && _results.isEmpty) return const Center(child: FCircularProgress());
    if (_error != null) return Center(child: Text(_error!));
    if (_query.text.trim().isEmpty) {
      if (_suggestions.isEmpty) return Center(child: Text('Search your library', style: muted));
      final view = libraryViewFor(context);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Suggested for you', style: context.theme.typography.display.lg),
            ),
          ),
          SliverGrid.builder(
            gridDelegate: libraryGridDelegate(view),
            itemCount: _suggestions.length,
            itemBuilder: (context, i) =>
                PosterCard(item: _suggestions[i], view: view, onPress: () => _open(_suggestions[i])),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      );
    }
    if (_results.isEmpty) return Center(child: Text('No results for "${_query.text.trim()}"', style: muted));

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.55,
      ),
      itemCount: _results.length,
      itemBuilder: (context, i) => PosterCard(item: _results[i], onPress: () => _open(_results[i])),
    );
  }
}