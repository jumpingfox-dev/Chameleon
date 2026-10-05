// Formatting for things read off a JellyfinItem or its raw JSON.

/// "2h 42m" from a runtime in Jellyfin's ticks (100 nanoseconds each), or null if there isn't
/// one, e.g. `formatRuntime(item.raw['RunTimeTicks'])`.
String? formatRuntime(Object? ticks) {
  if (ticks is! int || ticks <= 0) return null;
  final minutes = ticks ~/ 600000000;
  final h = minutes ~/ 60, m = minutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}
