import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import '../utils/jellyfin_controller.dart';
import 'profile_picker.dart';

typedef ProfileAction = ({String label, IconData icon, VoidCallback onPress});

/// The profile options, shared by the wide-screen popover and the phone Profile screen.
List<ProfileAction> profileActions(
    BuildContext context, {
      bool includeProfileLink = true,
    }) => [
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
    builder: (context, _) => jellyfin.userImage != null
        ? FAvatar(
      image: jellyfin.userImage!,
      fallback: Text(jellyfin.initials),
      size: size,
    )
        : FAvatar.raw(size: size, child: Text(jellyfin.initials)),
  );
}