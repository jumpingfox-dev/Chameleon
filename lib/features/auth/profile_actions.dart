import 'package:material_ui/material_ui.dart';

import '../../theme/app_icons.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import 'profile_picker.dart';

typedef ProfileAction = ({String label, IconData icon, VoidCallback onPress});

/// The profile options, shared by the wide-screen popover and the phone Profile screen.
List<ProfileAction> profileActions(BuildContext context) => [
  (
  label: 'Switch User',
  icon: appIcons.addUser,
  onPress: () => showProfilePicker(context), // "Who's watching?", with Add account at the end
  ),
  if (jellyfin.isConnected)
    (
    label: 'Sign out',
    icon: appIcons.signOut,
    onPress: jellyfin.signOut,
    ),
];

/// The signed-in user's avatar: their Jellyfin picture, or their initials.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: jellyfin,
    // The initials sit under the picture, so they show while it loads or if it can't.
    builder: (context, _) => CircleAvatar(
      radius: size / 2,
      foregroundImage: jellyfin.userImage,
      child: Text(jellyfin.initials),
    ),
  );
}