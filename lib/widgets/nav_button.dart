import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';

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

/// A nav button: icon + label, a text button that turns tonal when selected.
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
    const style = ButtonStyle(visualDensity: VisualDensity.compact);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [if (icon != null) Icon(icon, size: 16, fill: 1), Text(label)],
    );
    return selected
        ? FilledButton.tonal(onPressed: onPress, style: style, child: content)
        : TextButton(onPressed: onPress, style: style, child: content);
  }
}
