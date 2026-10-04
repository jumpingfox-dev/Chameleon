import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import '../utils/app_cache.dart';
import '../utils/jellyfin_controller.dart';
import '../widgets/detail_page.dart';
import '../widgets/poster_card.dart';

/// Everything you've favorited, in two sections: Movies and Shows.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<JellyfinItem> _movies = const [];
  List<JellyfinItem> _series = const [];
  List<JellyfinItem> _collections = const [];
  bool _loading = true;
  String? _error;

  static const _cacheKey = 'favorites';

  @override
  void initState() {
    super.initState();
    favoritesChanged.addListener(
      _load,
    ); // refresh when a favorite changes anywhere

    final cached = appCache.peek<(List<JellyfinItem>, List<JellyfinItem>, List<JellyfinItem>)>(
      _cacheKey,
    );
    if (cached != null) {
      _movies = cached.$1; // a record's positional fields are $1, $2, ...
      _series = cached.$2;
      _collections = cached.$3;
      _loading = false;
    }
    if (!appCache.isFresh(_cacheKey)) _load();
  }

  @override
  void dispose() {
    favoritesChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final client = jellyfin.client;
    if (client == null) return;
    try {
      final page = await client.items.list(
        filters: const ['IsFavorite'],
        includeItemTypes: const [
          JellyfinItemKind.movie,
          JellyfinItemKind.series,
          'BoxSet',
        ],
        recursive: true,
        sortBy: const ['SortName'],
        limit: 500,
        fields: const ['RecursiveItemCount'],
      );
      final movies = page.items
          .where((i) => i.type == JellyfinItemKind.movie)
          .toList();
      final series = page.items
          .where((i) => i.type == JellyfinItemKind.series)
          .toList();
      final collections = page.items
          .where((i) => i.type == 'BoxSet')
          .toList();
      appCache.put(_cacheKey, (movies, series, collections));
      if (!mounted) return;
      setState(() {
        _movies = movies;
        _series = series;
        _collections = collections;
        _error = null;
      });
    } on JellyfinException catch (e) {
      if (mounted && _movies.isEmpty && _series.isEmpty && _collections.isEmpty) {
        setState(() => _error = describeJellyfinError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => FScaffold(
    child: ListenableBuilder(
      listenable: libraryViewOverride, // follow the poster/thumbnail choice
      builder: (context, _) => _buildBody(context),
    ),
  );

  Widget _buildBody(BuildContext context) {
    final colors = context.theme.colors;

    if (_loading) return const Center(child: FCircularProgress());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text(_error!),
            FButton(
              mainAxisSize: .min,
              onPress: _load,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (_movies.isEmpty && _series.isEmpty && _collections.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(appIcons.favorite, size: 40, color: colors.mutedForeground, fill: 1),
            Text(
              'No favorites yet',
              style: context.theme.typography.display.lg,
            ),
            Text(
              'Select Favorite on any movie or show to add it here.',
              style: context.theme.typography.body.sm.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        if (_movies.isNotEmpty) ...[
          const SliverSectionTitle('Movies'),
          SliverItemGrid(items: _movies),
        ],
        if (_series.isNotEmpty) ...[
          const SliverSectionTitle('Shows'),
          SliverItemGrid(items: _series),
        ],
        if (_collections.isNotEmpty) ...[
          const SliverSectionTitle('Collections'),
          SliverItemGrid(items: _collections),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}
