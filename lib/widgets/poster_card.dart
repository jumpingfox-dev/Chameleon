import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';

enum LibraryView { poster, thumbnail }

/// null = automatic (thumbnails on wide screens, posters on phones).
/// Set by the toggle, and kept while the app is open.
final libraryViewOverride = ValueNotifier<LibraryView?>(null);

LibraryView libraryViewFor(BuildContext context) =>
    libraryViewOverride.value ??
        (MediaQuery.sizeOf(context).width < 600 ? LibraryView.poster : LibraryView.thumbnail);

/// Grid sizing for each view: narrow tall posters, or wider 16:9 thumbnails.
const _gridSpacing = 4.0;
double _tileWidth(LibraryView view) => view == LibraryView.poster ? 170 : 320;
double _aspect(LibraryView view) => view == LibraryView.poster ? 2 / 3 : 16 / 9;

/// Grid sizing for each view: narrow tall posters, or wider 16:9 thumbnails.
SliverGridDelegate libraryGridDelegate(LibraryView view) => SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: _tileWidth(view),
  mainAxisSpacing: _gridSpacing,
  crossAxisSpacing: _gridSpacing,
  childAspectRatio: _aspect(view),
);

/// The height a grid of [count] items takes at [width], using the same layout rules as Flutter's grid.
/// The library page uses it to work out where each letter section starts.
double libraryGridHeight(int count, double width, LibraryView view) {
  if (count == 0 || width <= 0) return 0;
  final columns = (width / (_tileWidth(view) + _gridSpacing)).ceil().clamp(1, 1000);
  final tileWidth = (width - (columns - 1) * _gridSpacing) / columns;
  final rows = (count / columns).ceil();
  return rows * (tileWidth / _aspect(view)) + (rows - 1) * _gridSpacing;
}

class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onPress,
    this.view = LibraryView.poster,
  });

  final JellyfinItem item;
  final VoidCallback onPress;
  final LibraryView view;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;
  bool _hovered = false;

  /// Scale up on mouse hover, or on focus from a remote/keyboard. A mouse click also
  /// focuses the card, but that shouldn't leave it enlarged, hence the highlight-mode check.
  bool get _active =>
      _hovered || (_focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional);

  String? _imageUrl(JellyfinClient client) {
    final item = widget.item;
    if (widget.view == LibraryView.thumbnail) {
      final thumb = item.imageTags['Thumb'];
      if (thumb != null) {
        return client.images.url(itemId: item.id, type: JellyfinImagesApi.typeThumb, tag: thumb, fillWidth: 640, quality: 90);
      }
      final backdrops = item.raw['BackdropImageTags'] as List?;
      if (backdrops != null && backdrops.isNotEmpty) {
        return client.images.url(
          itemId: item.id,
          type: JellyfinImagesApi.typeBackdrop,
          tag: backdrops.first as String,
          fillWidth: 640,
          quality: 90,
        );
      }
    }
    final primary = item.imageTags['Primary'];
    if (primary == null) return null;
    return client.images.url(
      itemId: item.id,
      type: JellyfinImagesApi.typePrimary,
      tag: primary,
      fillWidth: widget.view == LibraryView.poster ? 340 : 640,
      quality: 90,
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = _imageUrl(jellyfin.client!);
    final colors = context.theme.colors;

    return Semantics(
      label: widget.item.name,
      button: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          // Doesn't take focus itself; just reports when the FTappable inside it does.
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: AnimatedScale(
            scale: _active ? 1.0 : 0.94,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: FTappable(
              onPress: widget.onPress,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: url == null
                    ? _placeholder(context, colors)
                    : Image.network(
                  url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, _, _) => _placeholder(context, colors),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context, FColors colors) => ColoredBox(
    color: colors.muted,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          widget.item.name,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: context.theme.typography.body.sm.copyWith(color: colors.mutedForeground),
        ),
      ),
    ),
  );
}