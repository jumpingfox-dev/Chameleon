import 'package:dart_jellyfin/dart_jellyfin.dart';

/// Everything a library page has loaded, kept for the session.
class LibraryCacheEntry {
  final items = <JellyfinItem>[];
  int? total;
  Set<String>? letters;
  double scrollOffset = 0;
  final fetchedAt = DateTime.now();

  /// After this long, the next visit reloads, so new additions to the server show up.
  bool get isFresh =>
      DateTime.now().difference(fetchedAt) < const Duration(minutes: 10);
}

/// Keyed by 'library:<id>' or 'genre:<name>'.
final libraryCache = <String, LibraryCacheEntry>{};
