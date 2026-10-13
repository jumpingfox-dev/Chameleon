import 'package:dart_jellyfin/dart_jellyfin.dart';

import '../storage/app_cache.dart';

/// Everything a library page has loaded, kept in [appCache] (and saved, so the page opens with
/// it next time) under `library:<id>` or `genre:<name>`.
class LibraryCacheEntry {
  LibraryCacheEntry({List<JellyfinItem>? items, this.total, this.letters})
    : items = items ?? [];

  final List<JellyfinItem> items;
  int? total;
  Set<String>? letters;

  /// Where the page was scrolled to. Kept while the app's open, not saved.
  double scrollOffset = 0;

  /// The largest number of titles reloaded when an old saved page is refreshed in place.
  static const refreshLimit = 300;

  static Object? toJson(LibraryCacheEntry e) => {
    'items': itemsToJson(e.items),
    'total': e.total,
    'letters': e.letters?.toList(),
  };

  static LibraryCacheEntry fromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return LibraryCacheEntry(
      items: itemsFromJson(map['items']),
      total: map['total'] as int?,
      letters: (map['letters'] as List?)?.cast<String>().toSet(),
    );
  }
}
