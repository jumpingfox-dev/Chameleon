import 'package:forui/forui.dart';
import 'package:forui_phosphor/forui_phosphor.dart';
import 'package:material_ui/material_ui.dart';

/// The icon for each kind of Jellyfin library.
IconData libraryIcon(String? type) => switch (type) {
  'movies' => FPhosphorIcons.filmSlate,
  'tvshows' => FPhosphorIcons.television,
  'music' => FPhosphorIcons.musicNotes,
  'boxsets' => FPhosphorIcons.stack,
  'playlists' => FPhosphorIcons.queue,
  'musicvideos' => FPhosphorIcons.monitorPlay,
  'homevideos' => FPhosphorIcons.filmStrip,
  'photos' => FPhosphorIcons.images,
  'books' => FPhosphorIcons.books,
  'livetv' => FPhosphorIcons.broadcast,
  _ => FPhosphorIcons.folder,
};

/// A nav button: icon + label, ghost style, filled in when selected.
class NavButton extends StatelessWidget {
  const NavButton({super.key, required this.label, this.icon, this.selected = false, required this.onPress});

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => FButton(
    variant: selected ? .secondary : .ghost,
    size: .sm,
    mainAxisSize: .min,
    onPress: onPress,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [if (icon != null) Icon(icon, size: 16), Text(label)],
    ),
  );
}