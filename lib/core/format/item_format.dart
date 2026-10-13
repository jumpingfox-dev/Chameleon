// Formatting for things read off a JellyfinItem or its raw JSON.

/// "2h 42m" from a runtime in Jellyfin's ticks (100 nanoseconds each), or null if there isn't
/// one, e.g. `formatRuntime(item.raw['RunTimeTicks'])`.
String? formatRuntime(Object? ticks) {
  if (ticks is! int || ticks <= 0) return null;
  final minutes = ticks ~/ 600000000;
  final h = minutes ~/ 60, m = minutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// "S1:E3" from an episode's season and episode numbers, or null if either is missing,
/// e.g. `seasonEpisode(item.raw['ParentIndexNumber'], item.raw['IndexNumber'])`.
String? seasonEpisode(Object? season, Object? episode) =>
    season != null && episode != null ? 'S$season:E$episode' : null;

/// "S1:E3 · The Name", or just the name if there's no season or episode number.
String episodeLabel(Object? season, Object? episode, String name) =>
    [?seasonEpisode(season, episode), name].join(' · ');

/// A wide picture's address, from candidates in priority order: each is (image type, the
/// item that has it, its tag), and the first with a tag wins, e.g.
/// `wideImageUrl(base, [('Backdrop', item.id, ownBackdrop), ('Backdrop', parentId, parentBackdrop),
/// ('Primary', item.id, primary)])`. Null if none of them have a tag.
String? wideImageUrl(
  String base,
  List<(String type, String itemId, String? tag)> candidates, {
  int fillWidth = 400,
  int? quality,
}) {
  for (final (type, itemId, tag) in candidates) {
    if (tag == null) continue;
    final q = quality == null ? '' : '&quality=$quality';
    return '$base/Items/$itemId/Images/$type?fillWidth=$fillWidth$q&tag=$tag';
  }
  return null;
}
