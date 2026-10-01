import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';
import '../theme/app_icons.dart';

IconData _iconFor(String genre) {
  final name = genre.toLowerCase();
  for (final (keyword, icon) in appIcons.genreIcons) {
    if (name.contains(keyword)) return icon;
  }
  return appIcons.genres; // anything without a match, in the current icon style
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
          return Center(
            child: Text(
              'No genres found',
              style: context.theme.typography.body.md,
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.symmetric(vertical: 16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent:
                200, // tile width; more columns on wider screens
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 16 / 9,
          ),
          itemCount: genres.length,
          itemBuilder: (context, i) {
            final genre = genres[i];
            return FButton(
              variant: .outline,
              onPress: () =>
                  context.go('/home/genre/${Uri.encodeComponent(genre)}'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Icon(
                    _iconFor(genre),
                    size: 32,
                    color: context.theme.colors.primary,
                    fill: 1,
                  ),
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
