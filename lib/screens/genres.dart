import 'package:forui/forui.dart';
import 'package:forui_phosphor/forui_phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';

/// Keywords → icons. The first keyword found in a genre's name wins, so more
/// specific ones ("science fiction") come before general ones ("fiction").
const _genreIcons = <(String, IconData)>[
  ('science fiction', FPhosphorIcons.rocket),
  ('sci-fi', FPhosphorIcons.rocket),
  ('action', FPhosphorIcons.lightning),
  ('adventure', FPhosphorIcons.compass),
  ('animation', FPhosphorIcons.paintBrush),
  ('anime', FPhosphorIcons.sparkle),
  ('children', FPhosphorIcons.baby),
  ('comedy', FPhosphorIcons.smiley),
  ('crime', FPhosphorIcons.fingerprint),
  ('documentary', FPhosphorIcons.videoCamera),
  ('drama', FPhosphorIcons.maskSad),
  ('family', FPhosphorIcons.users),
  ('kids', FPhosphorIcons.baby),
  ('fantasy', FPhosphorIcons.magicWand),
  ('food', FPhosphorIcons.hamburger),
  ('history', FPhosphorIcons.scroll),
  ('horror', FPhosphorIcons.skull),
  ('mini', FPhosphorIcons.monitorPlay),
  ('music', FPhosphorIcons.musicNotes),
  ('mystery', FPhosphorIcons.magnifyingGlass),
  ('romance', FPhosphorIcons.heart),
  ('suspense', FPhosphorIcons.hourglassMedium),
  ('talk', FPhosphorIcons.microphone),
  ('thriller', FPhosphorIcons.knife),
  ('tv', FPhosphorIcons.television),
  ('war', FPhosphorIcons.sword),
  ('western', FPhosphorIcons.horse),
  ('sport', FPhosphorIcons.football),
  ('reality', FPhosphorIcons.television),
];

IconData _iconFor(String genre) {
  final name = genre.toLowerCase();
  for (final (keyword, icon) in _genreIcons) {
    if (name.contains(keyword)) return icon;
  }
  return FPhosphorIcons.tag; // anything without a match
}

class GenresScreen extends StatelessWidget {
  const GenresScreen({super.key});

  @override
  Widget build(BuildContext context) => FScaffold(
    child: ListenableBuilder(
      listenable: jellyfin,
      builder: (context, _) {
        final genres = jellyfin.genres;
        if (genres.isEmpty) {
          return Center(child: Text('No genres found', style: context.theme.typography.body.md));
        }

        return GridView.builder(
          padding: const EdgeInsets.symmetric(vertical: 16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200, // tile width; more columns on wider screens
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 16 / 9,
          ),
          itemCount: genres.length,
          itemBuilder: (context, i) {
            final genre = genres[i];
            return FButton(
              variant: .outline,
              onPress: () => context.go('/home/genre/${Uri.encodeComponent(genre)}'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Icon(_iconFor(genre), size: 32, color: context.theme.colors.primary),
                  Text(
                    genre,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}