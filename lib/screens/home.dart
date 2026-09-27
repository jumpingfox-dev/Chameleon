import 'package:forui/forui.dart';
import 'package:forui_phosphor/forui_phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';
import '../widgets/nav_button.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => FScaffold(
    child: ListenableBuilder(
      listenable: jellyfin, // libraries arrive after sign-in, so rebuild when they do
      builder: (context, _) {
        final isPhone = MediaQuery.sizeOf(context).width < 600;

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // Library pills: phones only, since wider screens have them in the top bar.
            if (isPhone && (jellyfin.libraries.isNotEmpty || jellyfin.genres.isNotEmpty)) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal, // scrolls sideways if there are many libraries
                child: Row(
                  spacing: 4,
                  children: [
                    for (final library in jellyfin.libraries)
                      NavButton(
                        label: library.name,
                        icon: libraryIcon(library.collectionType),
                        onPress: () => context.go('/home/library/${library.id}'),
                      ),
                    if (jellyfin.genres.isNotEmpty)
                      NavButton(
                        label: 'Genres',
                        icon: FPhosphorIcons.tag,
                        onPress: () => context.go('/home/genres'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ...the rest of your home page content
          ],
        );
      },
    ),
  );
}