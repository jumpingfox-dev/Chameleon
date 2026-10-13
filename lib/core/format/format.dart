import 'dart:math';

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

/// A random id as [bytes] bytes of hex, e.g. for a device id or a transcoding session.
String randomHexId([int bytes = 16]) {
  final random = Random.secure();
  return List.generate(bytes, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// A size in bytes, readably: `512 B`, `3.4 KB`, `12.8 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var size = bytes / 1024;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[unit]}';
}
