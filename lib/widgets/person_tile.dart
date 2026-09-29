import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';
import 'hover_lift.dart';

/// A round photo with the person's name underneath. Lifts on hover or remote focus.
class PersonTile extends StatelessWidget {
  const PersonTile({super.key, required this.person, required this.onPress, this.size = 96});

  final JellyfinItem person;
  final VoidCallback onPress;
  final double size;

  @override
  Widget build(BuildContext context) => HoverLift(
    builder: (context, active) => FTappable(
      onPress: onPress,
      child: SizedBox(
        width: size + 14,
        child: Column(
          spacing: 6,
          children: [
            AnimatedScale(
              scale: active ? 1.0 : 0.94,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: PersonPhoto(person: person, size: size),
            ),
            Flexible(
              // Takes only the space that's left, and truncates the name instead of overflowing.
              child: Text(
                person.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.theme.typography.body.xs,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A person's round photo, or their initials if there isn't one. No hover effects.
class PersonPhoto extends StatelessWidget {
  const PersonPhoto({super.key, required this.person, this.size = 96});

  final JellyfinItem person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final tag = person.imageTags['Primary'];
    final initials = person.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join();

    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: tag == null
            ? ColoredBox(
          color: colors.muted,
          child: Center(child: Text(initials, style: TextStyle(color: colors.mutedForeground))),
        )
            : Image.network(
          jellyfin.client!.images.url(
            itemId: person.id,
            type: JellyfinImagesApi.typePrimary,
            tag: tag,
            fillWidth: (size * 2).round(),
            quality: 90,
          ),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}