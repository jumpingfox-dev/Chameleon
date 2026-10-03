import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import '../utils/jellyfin_controller.dart';
import '../utils/home_layout.dart';
import '../utils/page_insets.dart';
import '../utils/orientation.dart';
import '../widgets/nav_button.dart';
import '../widgets/home_modules.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// While true, the home screen's modules can be added, removed and rearranged.
  bool _editing = false;

  void _toggleEditing() => setState(() => _editing = !_editing);
  GoRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_router != null) return; // set up once
    _router = GoRouter.of(context);
    _router!.routerDelegate.addListener(_onNavigate);
  }

  /// Leaving Home (to a library, another tab, the player, ...) ends edit mode.
  void _onNavigate() {
    final path = _router!.routerDelegate.currentConfiguration.uri.path;
    if (_editing && path != '/home' && mounted) setState(() => _editing = false);
    if (path == '/home') homeVisible.value++; // lets sections older than 10 minutes refresh
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onNavigate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FScaffold(
    // No side padding here: each part adds its own (pageSides), so rows can scroll to the edge.
    childPad: false,
    child: Stack(
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([jellyfin, homeLayout]),
          builder: (context, _) {
            final isPhone = isPhoneLayout(context);

            return ListView(
              // Extra space at the bottom so the last module isn't hidden behind the Edit button.
              // No side padding: rows scroll edge to edge, everything else adds pageSides.
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 48),
              children: [
                // Library links: phones only, since wider screens have them in the top bar.
                if (isPhone &&
                    (jellyfin.libraries.isNotEmpty ||
                        jellyfin.genres.isNotEmpty)) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: pageSides(context),
                    child: Row(
                      spacing: 4,
                      children: [
                        NavButton(
                          label: 'Favorites',
                          icon: appIcons.favorite,
                          onPress: () => context.go('/home/favorites'),
                        ),
                        for (final library in jellyfin.libraries)
                          NavButton(
                            label: library.name,
                            icon: libraryIcon(library.collectionType),
                            onPress: () =>
                                context.go('/home/library/${library.id}'),
                          ),
                        if (jellyfin.genres.isNotEmpty)
                          NavButton(
                            label: 'Genres',
                            icon: appIcons.genres,
                            onPress: () => context.go('/home/genres'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_editing)
                  Padding(padding: pageSides(context), child: const _EditModeBanner()),

                for (final (i, module) in homeLayout.value.indexed)
                  HomeModuleView(
                    key: ValueKey(
                      module.id,
                    ), // keeps each section's content attached when it moves
                    module: module,
                    editing: _editing,
                    isFirst: i == 0,
                    isLast: i == homeLayout.value.length - 1,
                  ),

                if (homeLayout.value.isEmpty && !_editing)
                  Padding(
                    padding: pageSides(context).copyWith(top: 48, bottom: 48),
                    child: Center(
                      child: Text(
                        'Your home screen is empty. Select the pencil to add sections.',
                        style: context.theme.typography.body.md.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                    ),
                  ),

                if (_editing)
                  Padding(padding: pageSides(context), child: const AddHomeModules()),
              ],
            );
          },
        ),

        // ── Edit / Done ──
        Positioned(
          right: pageSides(context).right,
          bottom: 16,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            // Keep both buttons pinned to the bottom-right corner while they crossfade,
            // instead of centering them (which makes the smaller one slide sideways).
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.bottomRight,
              children: [...previous, ?current],
            ),
            // Fade plus a slight scale, growing from the corner the button sits in.
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: 0.9, end: 1.0).animate(animation),
                alignment: Alignment.bottomRight,
                child: child,
              ),
            ),
            child: _editing
                ? FButton(
              key: const ValueKey('done'),
              mainAxisSize: .min,
              onPress: _toggleEditing,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Icon(appIcons.check, size: 18, fill: 1),
                  Text('Done'),
                ],
              ),
            )
                : Semantics(
              key: const ValueKey('edit'),
              label: 'Edit home screen',
              button: true,
              child: FButton.icon(
                onPress: _toggleEditing,
                child: Icon(appIcons.edit, fill: 1),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Shown at the top of the home screen while editing.
class _EditModeBanner extends StatelessWidget {
  const _EditModeBanner();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.primary),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            spacing: 12,
            children: [
              Icon(appIcons.edit, color: colors.primary, fill: 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      'Editing your home screen',
                      style: context.theme.typography.body.md,
                    ),
                    Text(
                      'Add, remove and rearrange sections. Select Done when you\'re finished.',
                      style: context.theme.typography.body.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}