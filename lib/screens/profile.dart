import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';
import '../widgets/profile_actions.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => FScaffold(
    child: ListenableBuilder(
      listenable: jellyfin,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          FCard(
            builder: (context, style, _) => Padding(
              padding: style.padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  // Who's signed in
                  const Center(child: UserAvatar(size: 80)),
                  Text(
                    jellyfin.userName ?? 'Not signed in',
                    textAlign: TextAlign.center,
                    style: context.theme.typography.display.lg,
                  ),
                  if (jellyfin.lastServer != null)
                    Text(
                      jellyfin.lastServer!,
                      textAlign: TextAlign.center,
                      style: context.theme.typography.body.sm.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),

                  const FDivider(), // separates the profile from the actions
                  // Actions
                  for (final action in profileActions(context))
                    FButton(
                      variant: .outline,
                      mainAxisAlignment: .start,
                      onPress: action.onPress,
                      child: Row(
                        spacing: 12,
                        children: [
                          Icon(action.icon, size: 20),
                          Text(action.label),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
