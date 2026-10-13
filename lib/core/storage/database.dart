import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Small settings, one row each: the theme, fonts, the home layout, playback settings, ...
/// Values are strings; anything structured is stored as JSON.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Accounts signed in on this device, in the order "Who's watching?" shows them.
class Accounts extends Table {
  TextColumn get server => text()();
  TextColumn get userId => text()();
  TextColumn get token => text()();
  TextColumn get deviceId => text()(); // the id this account signed in with
  TextColumn get name => text()();
  TextColumn get imageTag => text().nullable()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {server, userId};
}

/// What pages last loaded from the server, so they open straight away next time and refresh in
/// the background. [scope] is the account it belongs to (`<server>|<userId>`): another account
/// sees different progress, favorites and recommendations.
class CacheEntries extends Table {
  TextColumn get scope => text()();
  TextColumn get key => text()();
  TextColumn get payload => text()(); // JSON, see cache_codec.dart
  DateTimeColumn get storedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {scope, key};
}

@DriftDatabase(tables: [Settings, Accounts, CacheEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'chameleon',
              // App support, not documents: on Linux, documents is ~/Documents.
              native: const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory),
            ),
      );

  @override
  int get schemaVersion => 1;
}
