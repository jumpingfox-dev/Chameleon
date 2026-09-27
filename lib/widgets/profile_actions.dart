import 'package:forui/forui.dart';
import 'package:forui_phosphor/forui_phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';

typedef ProfileAction = ({String label, IconData icon, VoidCallback onPress});

/// The profile options, shared by the wide-screen popover and the phone Profile screen.
List<ProfileAction> profileActions(BuildContext context, {bool includeProfileLink = true}) => [
  (label: 'Add User', icon: FPhosphorIcons.userPlus, onPress: () => context.go('/settings')),
  if (jellyfin.isConnected) (label: 'Sign out', icon: FPhosphorIcons.signOut, onPress: jellyfin.signOut),
];

/// The signed-in user's avatar: their Jellyfin picture, or their initials.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: jellyfin,
    builder: (context, _) => jellyfin.userImage != null
        ? FAvatar(image: jellyfin.userImage!, fallback: Text(jellyfin.initials), size: size)
        : FAvatar.raw(size: size, child: Text(jellyfin.initials)),
  );
}