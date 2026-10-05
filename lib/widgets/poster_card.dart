import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import '../utils/jellyfin_controller.dart';
import '../utils/orientation.dart';
import 'hover_lift.dart';

enum LibraryView { poster, thumbnail }

/// null = automatic (thumbnails on wide screens, posters on phones).
/// Set by the toggle, and kept while the app is open.
final libraryViewOverride = ValueNotifier<LibraryView?>(null);

LibraryView libraryViewFor(BuildContext context) =>
    libraryViewOverride.value ??
    (isPhoneLayout(context)
        ? LibraryView.poster
        : LibraryView.thumbnail);

/// An outlined rectangle icon at a given aspect ratio, colored like other icons.
/// A wide one means thumbnails, a tall one means posters.
class AspectIcon extends StatelessWidget {
  const AspectIcon({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 20, // same footprint as a normal icon
    child: Center(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border.all(
            color: IconTheme.of(context).color ?? const Color(0xFFFFFFFF),
            width: 1.6,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

const _gridSpacing = 4.0;
double _tileWidth(LibraryView view) => view == LibraryView.poster ? 170 : 320;
double _aspect(LibraryView view) => view == LibraryView.poster ? 2 / 3 : 16 / 9;

/// Grid sizing for each view: narrow tall posters, or wider 16:9 thumbnails.
SliverGridDelegate libraryGridDelegate(LibraryView view) =>
    SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: _tileWidth(view),
      mainAxisSpacing: _gridSpacing,
      crossAxisSpacing: _gridSpacing,
      childAspectRatio: _aspect(view),
    );

/// The height a grid of [count] items takes at [width], using the same layout rules as Flutter's grid.
/// The library page uses it to work out where each letter section starts.
double libraryGridHeight(int count, double width, LibraryView view) {
  if (count == 0 || width <= 0) return 0;
  final columns = (width / (_tileWidth(view) + _gridSpacing)).ceil().clamp(
    1,
    1000,
  );
  final tileWidth = (width - (columns - 1) * _gridSpacing) / columns;
  final rows = (count / columns).ceil();
  return rows * (tileWidth / _aspect(view)) + (rows - 1) * _gridSpacing;
}

/// How far through an item you are (0–1), or null when there's nothing to show:
/// not started, or already fully watched.
double? watchProgress(JellyfinItem item) {
  final userData = item.raw['UserData'] as Map?;
  if (userData == null) return null;

  // Series: watched episodes ÷ total episodes.
  if (item.type == JellyfinItemKind.series) {
    final total = item.raw['RecursiveItemCount'] as int?;
    final unplayed = userData['UnplayedItemCount'] as int?;
    if (total == null || total <= 0 || unplayed == null) return null;
    final fraction = (total - unplayed) / total;
    return fraction <= 0 || fraction >= 1 ? null : fraction;
  }

  // Movies and episodes: how far into this one you got.
  if (userData['Played'] == true) return null;
  final percent = userData['PlayedPercentage'] as num?;
  if (percent == null || percent <= 0) return null;
  return (percent / 100).clamp(0.0, 1.0);
}

/// True when an item is fully watched: a finished movie or episode, or a series
/// with every episode watched.
bool isWatched(JellyfinItem item) {
  final userData = item.raw['UserData'] as Map?;
  if (userData == null) return false;
  if (userData['Played'] == true) return true;
  // Series: Jellyfin may only report the unwatched count, so zero left means finished.
  return item.type == JellyfinItemKind.series &&
      userData['UnplayedItemCount'] == 0;
}

/// A round check in the theme's primary color, for the corner of watched artwork.
class WatchedBadge extends StatelessWidget {
  const WatchedBadge({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 4),
        ], // lifts it off bright artwork
      ),
      child: Icon(
        appIcons.check,
        size: size * 0.6,
        color: colors.primaryForeground,
        fill: 1
      ),
    );
  }
}

/// A thin progress line: the theme's primary color over a dark track.
class WatchProgressBar extends StatelessWidget {
  const WatchProgressBar(this.value, {super.key});

  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(
            color: Color(0x73000000),
          ), // track: readable on any artwork
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: ColoredBox(color: context.theme.colors.primary),
          ),
        ],
      ),
    ),
  );
}

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onPress,
    this.view = LibraryView.poster,
  });

  final JellyfinItem item;
  final VoidCallback onPress;
  final LibraryView view;

  // TODO(cleanup): the thumbnail fallbacks belong in the shared wide-image helper
  /// Posters use the Primary image. Thumbnails prefer the landscape Thumb image,
  /// then a Backdrop, then fall back to the poster (cropped to fit).
  String? _imageUrl(JellyfinClient client) {
    if (view == LibraryView.thumbnail) {
      final thumb = item.imageTags['Thumb'];
      if (thumb != null) {
        return client.images.url(
          itemId: item.id,
          type: JellyfinImagesApi.typeThumb,
          tag: thumb,
          fillWidth: 640,
          quality: 90,
        );
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
      fillWidth: view == LibraryView.poster ? 340 : 640,
      quality: 90,
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = jellyfin.client; // null for a moment right after sign-out
    final url = client == null ? null : _imageUrl(client);
    final colors = context.theme.colors;

    return Semantics(
      label: item.name,
      button: true,
      child: HoverLift(
        builder: (context, active) => FTappable(
          onPress: onPress,
          child: AnimatedScale(
            scale: active ? 1.0 : 0.94,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              // Hovered or focused: a border drawn over the artwork's edge (it takes up no space).
              foregroundDecoration: BoxDecoration(
                border: Border.all(
                  color: active ? context.theme.colors.primary : const Color(0x00000000),
                  width: 2.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    url == null
                        ? _placeholder(context, colors)
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, _, _) =>
                                _placeholder(context, colors),
                          ),
                    if (watchProgress(item) case final progress?)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: WatchProgressBar(progress),
                      ),
                    if (isWatched(item))
                      const Positioned(top: 8, right: 8, child: WatchedBadge()),
                  ],
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
          item.name,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: context.theme.typography.body.sm.copyWith(
            color: colors.mutedForeground,
          ),
        ),
      ),
    ),
  );
}
