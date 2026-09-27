import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';
import '../widgets/poster_card.dart';

/// One collection: its artwork, name and description, then the movies inside it.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, required this.collectionId});

  final String collectionId;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  JellyfinItem? _collection;
  List<JellyfinItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = jellyfin.client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final (collection, page) = await (
      client.items.byId(widget.collectionId),
      client.items.list(
        parentId: widget.collectionId, // a collection's children are its movies
        sortBy: const ['ProductionYear', 'SortName'], // release order
        limit: 200,
      ),
      ).wait;
      if (!mounted) return;
      setState(() {
        _collection = collection;
        _items = page.items;
      });
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = describeJellyfinError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(JellyfinItem item) {
    if (item.type == JellyfinItemKind.movie) context.push('/play/${item.id}');
  }

  @override
  Widget build(BuildContext context) => FScaffold(
    header: FHeader.nested(
      title: Text(_collection?.name ?? 'Collection'),
      prefixes: [FHeaderAction.back(onPress: () => context.pop())],
    ),
    child: _buildBody(context),
  );

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: FCircularProgress());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text(_error!),
            FButton(mainAxisSize: .min, onPress: _load, child: const Text('Try again')),
          ],
        ),
      );
    }

    final overview = _collection?.raw['Overview'] as String?;
    final muted = context.theme.colors.mutedForeground;

    return CustomScrollView(
      slivers: [
        // Description and movie count above the grid.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text(
                  '${_items.length} ${_items.length == 1 ? 'title' : 'titles'}',
                  style: context.theme.typography.body.sm.copyWith(color: muted),
                ),
                if (overview != null && overview.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720), // readable line length on wide screens
                    child: Text(overview, style: context.theme.typography.body.md),
                  ),
              ],
            ),
          ),
        ),
        if (_items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('This collection is empty', style: TextStyle(color: muted))),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 16),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.55,
              ),
              itemCount: _items.length,
              itemBuilder: (context, i) => PosterCard(item: _items[i], onPress: () => _open(_items[i])),
            ),
          ),
      ],
    );
  }
}