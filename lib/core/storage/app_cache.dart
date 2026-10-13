import 'dart:async';
import 'dart:convert';

import 'package:dart_jellyfin/dart_jellyfin.dart';

import 'storage.dart';

/// A cache shared by every page. Entries are reused until they're older than [ttl];
/// pages show cached content instantly and refresh in the background once it's stale.
///
/// An entry put with a `toJson` is also saved to [storage] under the signed-in account, so it
/// shows straight away the next time the app opens (stale, so it refreshes too). Reading it
/// back then needs the matching `fromJson`.
class AppCache {
  AppCache({this.ttl = const Duration(minutes: 10)});

  /// How long an entry counts as fresh.
  final Duration ttl;

  /// After this long unused, a saved entry is deleted at startup.
  static const keepFor = Duration(days: 30);

  /// The account whose saved entries this holds (`<server>|<userId>`), if one is signed in.
  String? _scope;

  final _entries = <String, _Entry>{};

  /// Loads [scope]'s saved entries, dropping whatever another account left in memory.
  Future<void> open(String scope) async {
    if (scope == _scope) return;
    _entries.clear();
    _scope = scope;
    for (final e in await storage.cacheEntries(scope)) {
      _entries[e.key] = _Entry.saved(e.payload, e.storedAt);
    }
  }

  /// The cached value, fresh or not, or null if there isn't one (or it's the wrong type).
  /// [fromJson] reads it back if it was saved by an earlier run of the app.
  T? peek<T>(String key, {T Function(Object? json)? fromJson}) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (entry.json case final json?) {
      if (fromJson == null) return null;
      try {
        entry
          ..value = fromJson(jsonDecode(json))
          ..json = null;
      } catch (_) {
        _entries.remove(key); // saved in a shape this version doesn't read
        return null;
      }
    }
    final value = entry.value;
    return value is T ? value : null;
  }

  bool isFresh(String key) {
    final entry = _entries[key];
    return entry != null && DateTime.now().difference(entry.storedAt) < ttl;
  }

  /// Caches [value]. With [toJson], it's also saved for next time.
  void put<T>(String key, T value, {Object? Function(T value)? toJson}) {
    final now = DateTime.now();
    _entries[key] = _Entry(value, now);
    final scope = _scope;
    if (toJson == null || scope == null) return;
    unawaited(storage.putCache(scope, key, jsonEncode(toJson(value)), now));
  }

  /// Forgets matching entries, e.g. every cached page that shows a particular item.
  void invalidateWhere(bool Function(String key) test) {
    _entries.removeWhere((key, _) => test(key));
    if (_scope case final scope?) unawaited(storage.deleteCache(scope, test));
  }

  /// Empties memory, e.g. when changing user. What's saved stays for when they're back.
  void clear() {
    _entries.clear();
    _scope = null;
  }

  /// Deletes everything saved for an account that's been removed from this device.
  Future<void> forget(String scope) async {
    if (scope == _scope) clear();
    await storage.deleteCache(scope);
  }
}

class _Entry {
  _Entry(this.value, this.storedAt);
  _Entry.saved(this.json, this.storedAt);

  Object? value;
  String? json; // not read back yet
  final DateTime storedAt;
}

final appCache = AppCache();

/// The cache scope for an account.
String cacheScope(String server, String userId) => '$server|$userId';

// ─── JSON for the common cases ───────────────────────────────────────────────

/// An item as saved: the server's own JSON for it, which [itemFromJson] reads back.
Object? itemToJson(JellyfinItem item) => item.raw;

JellyfinItem itemFromJson(Object? json) => JellyfinItem.fromJson(json! as Map<String, dynamic>);

Object? itemsToJson(List<JellyfinItem> items) => [for (final i in items) i.raw];

List<JellyfinItem> itemsFromJson(Object? json) => [for (final j in json! as List) itemFromJson(j)];
