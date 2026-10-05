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
