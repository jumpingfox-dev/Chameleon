// Plain formatting and ids shared across the app: nothing here reads a JellyfinItem.

/// Two letters from a name, for an avatar with no picture: the first and last word's first
/// letter, or just one for a single word. '?' for a name that's empty or only whitespace.
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.length == 1
      ? words.first[0].toUpperCase()
      : (words.first[0] + words.last[0]).toUpperCase();
}

/// "1:02:03" or "4:05".
String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
