import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';

/// Everything the app keeps on this device, in one SQLite database ([AppDatabase]).
///
/// Settings are read once at startup and kept in memory, so reading one is instant and needs
/// no `await`; saving one writes it through to the database. Accounts and cached pages are
/// read when they're needed.
class Storage {
  Storage._(this._db, this._settings);

  final AppDatabase _db;
  final Map<String, String> _settings;

  /// Opens the database. On the first run after updating from a version that used
  /// shared_preferences, brings everything across first.
  static Future<Storage> open([AppDatabase? db]) async {
    db ??= AppDatabase();
    await _importSharedPreferences(db);
    final rows = await db.select(db.settings).get();
    return Storage._(db, {for (final r in rows) r.key: r.value});
  }

  // ─── Settings ──────────────────────────────────────────────────────────────

  String? getString(String key) => _settings[key];

  bool? getBool(String key) => switch (_settings[key]) {
    'true' => true,
    'false' => false,
    _ => null,
  };

  List<String>? getStringList(String key) {
    final raw = _settings[key];
    if (raw == null) return null;
    try {
      return [for (final s in jsonDecode(raw) as List) s as String];
    } catch (_) {
      return null;
    }
  }

  Future<void> setString(String key, String value) async {
    _settings[key] = value;
    await _db.into(_db.settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: key, value: value),
    );
  }

  Future<void> setBool(String key, bool value) => setString(key, '$value');

  Future<void> setStringList(String key, List<String> value) =>
      setString(key, jsonEncode(value));

  Future<void> remove(String key) async {
    _settings.remove(key);
    await (_db.delete(_db.settings)..where((t) => t.key.equals(key))).go();
  }

  // ─── Accounts ──────────────────────────────────────────────────────────────

  /// Every saved account, in order.
  Future<List<Account>> accounts() =>
      (_db.select(_db.accounts)..orderBy([(t) => OrderingTerm(expression: t.position)])).get();

  /// Replaces the saved accounts with [accounts], in this order.
  Future<void> saveAccounts(List<AccountsCompanion> accounts) => _db.transaction(() async {
    await _db.delete(_db.accounts).go();
    for (final (i, a) in accounts.indexed) {
      await _db.into(_db.accounts).insert(a.copyWith(position: Value(i)));
    }
  });

  // ─── Cached pages ──────────────────────────────────────────────────────────

  /// Every cached page for [scope] (an account), as stored.
  Future<List<CacheEntry>> cacheEntries(String scope) =>
      (_db.select(_db.cacheEntries)..where((t) => t.scope.equals(scope))).get();

  Future<void> putCache(String scope, String key, String payload, DateTime storedAt) =>
      _db.into(_db.cacheEntries).insertOnConflictUpdate(
        CacheEntriesCompanion.insert(scope: scope, key: key, payload: payload, storedAt: storedAt),
      );

  /// Forgets [scope]'s cached pages: all of them, or those whose key passes [test].
  Future<void> deleteCache(String scope, [bool Function(String key)? test]) async {
    if (test == null) {
      await (_db.delete(_db.cacheEntries)..where((t) => t.scope.equals(scope))).go();
      return;
    }
    final query = _db.selectOnly(_db.cacheEntries)
      ..addColumns([_db.cacheEntries.key])
      ..where(_db.cacheEntries.scope.equals(scope));
    final keys = [
      for (final row in await query.get())
        if (row.read(_db.cacheEntries.key) case final key? when test(key)) key,
    ];
    if (keys.isEmpty) return;
    await (_db.delete(_db.cacheEntries)
          ..where((t) => t.scope.equals(scope) & t.key.isIn(keys)))
        .go();
  }

  /// Forgets cached pages not refreshed since [before], from every account.
  Future<void> pruneCache(DateTime before) =>
      (_db.delete(_db.cacheEntries)..where((t) => t.storedAt.isSmallerThanValue(before))).go();

  /// The size of every account's cached pages, in bytes (roughly: the JSON's length).
  Future<int> cacheSize() async {
    final length = _db.cacheEntries.payload.length.sum();
    final row = await (_db.selectOnly(_db.cacheEntries)..addColumns([length])).getSingle();
    return row.read(length) ?? 0;
  }

  Future<void> clearAllCache() => _db.delete(_db.cacheEntries).go();
}

late final Storage storage;

// ─── From shared_preferences ─────────────────────────────────────────────────

const _importedKey = 'imported_shared_preferences';

/// Copies everything from shared_preferences (used before this database) into [db], once.
/// The old values are left where they were, in case this version is rolled back.
Future<void> _importSharedPreferences(AppDatabase db) async {
  final done = await (db.select(db.settings)..where((t) => t.key.equals(_importedKey)))
      .getSingleOrNull();
  if (done != null) return;

  final prefs = await SharedPreferences.getInstance();
  await db.transaction(() async {
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (key == 'jf_accounts' && value is String) {
        await _importAccounts(db, value);
        continue;
      }
      final text = switch (value) {
        final String s => s,
        final List<Object?> list => jsonEncode(list),
        null => null,
        _ => '$value', // bool, int, double
      };
      if (text == null) continue;
      await db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: key, value: text),
      );
    }
    await db.into(db.settings).insert(
      SettingsCompanion.insert(key: _importedKey, value: DateTime.now().toIso8601String()),
    );
  });
}

Future<void> _importAccounts(AppDatabase db, String json) async {
  final List<Object?> list;
  try {
    list = jsonDecode(json) as List<Object?>;
  } catch (_) {
    return;
  }
  for (final (i, a) in list.indexed) {
    if (a is! Map) continue;
    final server = a['server'], userId = a['userId'], token = a['token'];
    if (server is! String || userId is! String || token is! String) continue;
    await db.into(db.accounts).insertOnConflictUpdate(
      AccountsCompanion.insert(
        server: server,
        userId: userId,
        token: token,
        deviceId: a['deviceId'] as String? ?? '',
        name: a['name'] as String? ?? 'User',
        imageTag: Value(a['imageTag'] as String?),
        position: i,
      ),
    );
  }
}
