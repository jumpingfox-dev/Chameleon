/// An in-memory cache shared by every page. Entries are reused until they're older than [ttl];
/// pages show cached content instantly and refresh in the background once it's stale.
class AppCache {
  AppCache({this.ttl = const Duration(minutes: 10)});

  /// How long an entry counts as fresh.
  final Duration ttl;

  final _entries = <String, ({Object? value, DateTime storedAt})>{};

  /// The cached value, fresh or not, or null if there isn't one.
  T? peek<T>(String key) => _entries[key]?.value as T?;

  bool isFresh(String key) {
    final entry = _entries[key];
    return entry != null && DateTime.now().difference(entry.storedAt) < ttl;
  }

  void put(String key, Object? value) =>
      _entries[key] = (value: value, storedAt: DateTime.now());

  /// Forgets matching entries, e.g. every cached page that shows a particular item.
  void invalidateWhere(bool Function(String key) test) =>
      _entries.removeWhere((key, _) => test(key));

  void clear() => _entries.clear();
}

final appCache = AppCache();
