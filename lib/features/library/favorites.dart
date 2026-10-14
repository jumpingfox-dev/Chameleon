import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/app_icons.dart';
import '../../core/storage/app_cache.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../detail/detail_page.dart';
import 'poster_card.dart';
import '../../theme/theme.dart';
import '../../core/platform/page_insets.dart';

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

    final cached = appCache.peek(_cacheKey, fromJson: itemsFromJson); // saved, from last time
    if (cached != null) {
      _show(cached);
      _loading = false;
    }
    if (!appCache.isFresh(_cacheKey)) _load();
  }

  /// Sorts [items] into the three sections.
  void _show(List<JellyfinItem> items) {
    _movies = items.where((i) => i.type == JellyfinItemKind.movie).toList();
    _series = items.where((i) => i.type == JellyfinItemKind.series).toList();
    _collections = items.where((i) => i.type == 'BoxSet').toList();
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
      appCache.put(_cacheKey, page.items, toJson: itemsToJson);
      if (!mounted) return;
      setState(() {
        _show(page.items);
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
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: pageSides(context, extra: 12),
      child: ListenableBuilder(
      listenable: libraryViewOverride, // follow the poster/thumbnail choice
      builder: (context, _) => _buildBody(context),
    ),
    ),
  );

  Widget _buildBody(BuildContext context) {
    final colors = context.colors;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text(_error!),
            FilledButton(
              onPressed: _load,
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
            Icon(appIcons.favorite, size: 40, color: colors.onSurfaceVariant, fill: 1),
            Text(
              'No favorites yet',
              style: context.text.titleLarge,
            ),
            Text(
              'Select Favorite on any movie or show to add it here.',
              style: context.text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: pageTop(context))),
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
