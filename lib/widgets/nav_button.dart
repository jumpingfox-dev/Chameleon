import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import '../theme/theme.dart';

/// The icon for each kind of Jellyfin library.
IconData libraryIcon(String? type) => switch (type) {
  'movies' => appIcons.movies,
  'tvshows' => appIcons.shows,
  'music' => appIcons.music,
  'boxsets' => appIcons.collection,
  'playlists' => appIcons.playlists,
  'musicvideos' => appIcons.musicVideos,
  'homevideos' => appIcons.homeVideos,
  'photos' => appIcons.photos,
  'books' => appIcons.books,
  'livetv' => appIcons.liveTv,
  _ => appIcons.folder,
};

/// A nav button: icon + label, outlined like the settings tabs, in the same muted color as
/// the TV sidebar's links. Filled in when [selected].
class NavButton extends StatelessWidget {
  const NavButton({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    required this.onPress,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Shaped and sized like the settings tabs (Material's chips), but built as a button:
    // a chip leaves its label a fraction of a pixel short, which cuts the end off.
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      foregroundColor: WidgetStatePropertyAll(
        selected ? colors.onSecondaryContainer : colors.onSurfaceVariant,
      ),
      textStyle: WidgetStatePropertyAll(context.text.labelLarge),
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [if (icon != null) Icon(icon, size: 18, fill: 1), Text(label)],
    );
    return selected
        ? FilledButton.tonal(onPressed: onPress, style: style, child: content)
        : OutlinedButton(onPressed: onPress, style: style, child: content);
  }
}
