import 'dart:convert';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../../features/home/home_modules.dart';
import '../storage/app_cache.dart';
import '../storage/database.dart';
import '../storage/storage.dart';
import '../format/format.dart';

class JellyfinLibrary {
  const JellyfinLibrary({
    required this.id,
    required this.name,
    this.collectionType,
  });

  final String id;
  final String name;
  final String? collectionType; // 'movies', 'tvshows', 'music', ...
}

/// Combines the Host and Port fields into a server URL.
/// An empty port means "no port", for reverse-proxy setups like https://jellyfin.example.com.
String composeServerUrl(String host, String port) {
  var h = host.trim().replaceAll(RegExp(r'/+$'), '');
  if (!h.startsWith('http://') && !h.startsWith('https://')) h = 'http://$h';
  final uri = Uri.parse(h);
  final p = int.tryParse(port.trim());
  final url = (p == null ? uri : uri.replace(port: p)).toString();
  return url.replaceAll(RegExp(r'/+$'), '');
}

/// Splits a saved server URL back into Host and Port for pre-filling the form.
(String host, String port) splitServerUrl(String url) {
  final uri = Uri.parse(url);
  final scheme = uri.scheme == 'https'
      ? 'https://'
      : ''; // http is the default, so hide it
  final path = uri.path == '/' ? '' : uri.path;
  return ('$scheme${uri.host}$path', uri.hasPort ? '${uri.port}' : '');
}

/// Turns "192.168.1.20" into "http://192.168.1.20:8096" and strips trailing slashes.
String normalizeServerUrl(String input) {
  var url = input.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'http://$url';
    if (!Uri.parse(url).hasPort) url = '$url:8096'; // Jellyfin's default port
  }
  return url.replaceAll(RegExp(r'/+$'), '');
}

/// A friendly message for any error the package throws.
String describeJellyfinError(Object error) {
  if (error is! JellyfinException) return 'Something went wrong: $error';
  return switch (error.type) {
    JellyfinErrorType.connection =>
    "Couldn't reach the server. Check the address and your network.",
    JellyfinErrorType.timeout => 'The server took too long to respond.',
    JellyfinErrorType.auth => 'Wrong username or password.',
    JellyfinErrorType.notFound =>
    "That address doesn't look like a Jellyfin server.",
    _ => error.message,
  };
}

/// An account signed in on this device. Each keeps its own token, so switching is instant.
class SavedAccount {
  const SavedAccount({
    required this.server,
    required this.userId,
    required this.token,
    required this.deviceId,
    required this.name,
    this.imageTag,
  });

  final String server;
  final String userId;
  final String token;
  final String deviceId; // the id this account signed in with; the server ties the token to it
  final String name;
  final String? imageTag;

  String? get imageUrl => imageTag == null ? null : '$server/UserImage?userId=$userId&tag=$imageTag';

  bool isSame(String server, String userId) => this.server == server && this.userId == userId;

  AccountsCompanion toRow() => AccountsCompanion.insert(
    server: server,
    userId: userId,
    token: token,
    deviceId: deviceId,
    name: name,
    imageTag: Value(imageTag),
    position: 0, // set from the list's order when saved
  );

  factory SavedAccount.fromRow(Account row) => SavedAccount(
    server: row.server,
    userId: row.userId,
    token: row.token,
    deviceId: row.deviceId,
    name: row.name,
    imageTag: row.imageTag,
  );
}

/// A user the server lists on its login screen (not hidden by an admin).
class PublicUser {
  const PublicUser({
    required this.server,
    required this.id,
    required this.name,
    required this.hasPassword,
    this.imageTag,
  });

  final String server;
  final String id;
  final String name;
  final bool hasPassword;
  final String? imageTag;

  String? get imageUrl => imageTag == null ? null : '$server/UserImage?userId=$id&tag=$imageTag';
}

/// A saved account whose token no longer works (signed out elsewhere, or revoked by an admin).
/// It's removed from this device; the user needs to sign in again.
class AccountExpiredException implements Exception {
  const AccountExpiredException();

  @override
  String toString() => 'You were signed out. Sign in again to continue.';
}

/// A Quick Connect problem, with a message that can be shown as-is.
class QuickConnectException implements Exception {
  const QuickConnectException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A Quick Connect sign-in in progress: [code] is shown on screen, [secret] stays private.
class QuickConnectRequest {
  const QuickConnectRequest({required this.url, required this.code, required this.secret});

  final String url; // the server, already normalized
  final String code; // e.g. "123456", typed into another signed-in device
  final String secret; // proves this device started the request
}

class JellyfinController extends ChangeNotifier {
  static const _clientName = 'Chameleon';
  static const _clientVersion = '0.1.0';
  static const _kServer = 'jf_server';
  static const _kToken = 'jf_token';
  static const _kUserId = 'jf_user_id';
  static const _kDeviceId = 'jf_device_id';

  JellyfinClient? client;
  String? serverName;
  String? userName;
  ImageProvider? userImage;
  List<JellyfinLibrary> libraries = const [];
  List<String> genres = const [];

  /// The last server used, to pre-fill the login screen.
  String? lastServer;

  /// Every account signed in on this device, in the order they were added.
  List<SavedAccount> accounts = const [];

  /// True for the moment between two users while switching. The router shows the
  /// "Who's watching?" screen meanwhile, so no page is left showing the old user's things.
  bool switching = false;

  bool get isConnected => client?.token != null && client?.userId != null;

  /// The account that's signed in now, if any.
  SavedAccount? get currentAccount {
    final c = client;
    final server = c?.baseUrl;
    final userId = c?.userId;
    if (server == null || userId == null) return null;
    return accounts.where((a) => a.isSame(server, userId)).firstOrNull;
  }

  String get initials => initialsOf(userName ?? '');

  /// The direct-play address for an item: the original file, sent untouched.
  /// mpv decodes it on the device, so the server never has to transcode.
  String streamUrl(String itemId) =>
      '${client!.baseUrl}/Videos/$itemId/stream?static=true';

  /// Authenticates media requests with a header, keeping the token out of the URL.
  Map<String, String> get authHeaders => {
    'Authorization': 'MediaBrowser Token="${client!.token}"',
  };

  /// GETs [path] (and any [query] parameters) against the server and decodes the JSON
  /// response. Throws if there's no server to ask, or it doesn't answer with 200.
  /// [auth] can be turned off for endpoints that work before signing in.
  Future<dynamic> getJson(
      String path, {
        Map<String, String>? query,
        bool auth = true,
        Duration timeout = const Duration(seconds: 10),
      }) async {
    final base = client?.baseUrl;
    if (base == null) throw StateError('Not connected to a server.');
    var uri = Uri.parse('$base$path');
    if (query != null) uri = uri.replace(queryParameters: query);
    final res = await http.get(uri, headers: auth ? authHeaders : null).timeout(timeout);
    if (res.statusCode != 200) throw Exception('GET $path → ${res.statusCode}');
    return jsonDecode(res.body);
  }

  /// A random id for this install. Jellyfin tracks sessions by it, so it must stay stable.
  Future<String> _deviceId() async {
    var id = storage.getString(_kDeviceId);
    if (id == null) {
      id = randomHexId();
      await storage.setString(_kDeviceId, id);
    }
    return id;
  }

  /// This install's id, made unique per user. Jellyfin keeps one session per device id
  /// and user, so without this, signing in a second user could sign out the first.
  Future<String> _deviceIdFor(String username) async {
    final hash = username.trim().toLowerCase().codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x7fffffff);
    return '${await _deviceId()}-${hash.toRadixString(16)}';
  }

  Future<JellyfinClient> _createClient(
      String url, {
        String? deviceId, // defaults to this install's plain id
      }) async => JellyfinClient(
    baseUrl: url,
    credentials: JellyfinCredentials(
      client: _clientName,
      device: defaultTargetPlatform.name,
      deviceId: deviceId == null || deviceId.isEmpty ? await _deviceId() : deviceId,
      version: _clientVersion,
    ),
  );

  // ─── Saved accounts ────────────────────────────────────────────────────────

  Future<List<SavedAccount>> _readAccounts() async =>
      [for (final a in await storage.accounts()) SavedAccount.fromRow(a)];

  Future<void> _writeAccounts() => storage.saveAccounts([for (final a in accounts) a.toRow()]);

  /// Adds or updates [account], keeping its place in the list.
  Future<void> _rememberAccount(SavedAccount account) async {
    final i = accounts.indexWhere((a) => a.isSame(account.server, account.userId));
    accounts = [...accounts];
    if (i == -1) {
      accounts.add(account);
    } else {
      accounts[i] = account;
    }
    await _writeAccounts();
  }

  /// Removes an account from this device, with everything cached for it.
  Future<void> _forgetAccount(String server, String userId) async {
    accounts = [for (final a in accounts) if (!a.isSame(server, userId)) a];
    await _writeAccounts();
    await appCache.forget(cacheScope(server, userId));
  }

  /// The users [server] shows on its login screen. Needs no sign-in.
  /// Returns an empty list if the server can't be reached.
  Future<List<PublicUser>> publicUsers(String server) async {
    final url = normalizeServerUrl(server);
    try {
      final res = await http.get(Uri.parse('$url/Users/Public')).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      return [
        for (final u in jsonDecode(res.body) as List)
          if (u is Map && u['Id'] is String)
            PublicUser(
              server: url,
              id: u['Id'] as String,
              name: u['Name'] as String? ?? 'User',
              hasPassword: u['HasPassword'] as bool? ?? true,
              imageTag: u['PrimaryImageTag'] as String?,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Switches to an account saved on this device, without a password.
  /// Throws [AccountExpiredException] if its token has stopped working.
  Future<void> switchTo(SavedAccount account) async {
    if (currentAccount?.isSame(account.server, account.userId) ?? false) return;
    final newClient = await _createClient(account.server, deviceId: account.deviceId)
      ..setSession(token: account.token, userId: account.userId);

    // Check the token before leaving the current user, so a dead one doesn't strand you.
    try {
      await newClient.user.currentUser();
    } on JellyfinException catch (e) {
      if (e.isAuthError) {
        await _forgetAccount(account.server, account.userId);
        notifyListeners();
        throw const AccountExpiredException();
      }
      rethrow; // offline: let the caller say so
    }
    await _switchSession(newClient, account.server, account.token, account.userId, account.deviceId);
  }

  /// Restores a saved session at startup. With more than one account on this device,
  /// it stays signed out so the app opens on "Who's watching?".
  Future<void> load() async {
    lastServer = storage.getString(_kServer);
    accounts = await _readAccounts();
    if (accounts.length > 1) return;

    final token = storage.getString(_kToken);
    final userId = storage.getString(_kUserId);
    if (lastServer == null || token == null || userId == null) return;

    final saved = accounts.where((a) => a.isSame(lastServer!, userId)).firstOrNull;
    client = await _createClient(lastServer!, deviceId: saved?.deviceId)
      ..setSession(token: token, userId: userId);
    await appCache.open(cacheScope(lastServer!, userId)); // pages from last time, while this loads

    try {
      await _refresh(); // also saves this account, for installs from before accounts existed
    } on JellyfinException catch (e) {
      if (e.isAuthError) {
        await _forgetAccount(lastServer!, userId);
        await _clearSession(); // token revoked or expired: back to login
      }
      // Connection errors (server offline) keep the session, so you stay signed in.
    }
  }

  Future<void> signIn({
    required String server,
    required String username,
    required String password,
  }) async {
    final url = normalizeServerUrl(server);
    final deviceId = await _deviceIdFor(username);
    final newClient = await _createClient(url, deviceId: deviceId);

    // Confirms the address is a Jellyfin server before sending credentials.
    final name = (await newClient.system.publicInfo()).serverName;

    final auth = await newClient.user.authenticateByName(
      username: username,
      password: password,
    );
    serverName = name;
    await _switchSession(newClient, url, auth.accessToken, auth.user.id, deviceId);
  }

  /// Starts [token]'s session. If someone else is signed in, passes through [switching]
  /// first so every page from the old user is closed before the new one loads.
  Future<void> _switchSession(
      JellyfinClient newClient,
      String url,
      String token,
      String userId,
      String deviceId
      ) async {
    final changingUser = isConnected && !(client!.baseUrl == url && client!.userId == userId);
    if (changingUser) {
      switching = true;
      notifyListeners();
      _clearCaches();
    }
    try {
      await _startSession(newClient, url, token, userId, deviceId);
    } finally {
      if (switching) {
        switching = false;
        notifyListeners();
      }
    }
  }

  /// Saves a new session and loads the user's libraries. Shared by every way of signing in.
  Future<void> _startSession(
      JellyfinClient newClient,
      String url,
      String token,
      String userId,
      String deviceId
      ) async {
    newClient.setSession(token: token, userId: userId);

    client = newClient;
    lastServer = url;
    await appCache.open(cacheScope(url, userId)); // this account's pages from last time
    await storage.setString(_kServer, url);
    await storage.setString(_kToken, token);
    await storage.setString(_kUserId, userId);
    storage.useUser(url, userId); // this person's own theme, fonts and settings
    // Save (or refresh) this account. A new account gets a placeholder name until
    // _refresh below fills in the real name and picture.
    final existing = currentAccount;
    await _rememberAccount(
      SavedAccount(
        server: url,
        userId: userId,
        token: token,
        deviceId: deviceId,
        name: existing?.name ?? 'User',
        imageTag: existing?.imageTag,
      ),
    );

    await _refresh();
  }

  // ─── Quick Connect ─────────────────────────────────────────────────────────
  // Sign in without typing a password: this device shows a code, and the user
  // approves it from any device that's already signed in (the web app, a phone,
  // or this app's Account tab). The package doesn't wrap these yet, so they use http.

  /// Identifies this app and device to the server, before anyone is signed in.
  Future<Map<String, String>> _clientHeaders() async => {
    'Authorization':
    'MediaBrowser Client="$_clientName", Device="${defaultTargetPlatform.name}", '
        'DeviceId="${await _deviceId()}", Version="$_clientVersion"',
  };

  /// Step 1: asks the server for a code to show on screen.
  /// Throws a [QuickConnectException] with a readable message if it can't.
  Future<QuickConnectRequest> startQuickConnect(String server) async {
    final url = normalizeServerUrl(server);
    final headers = await _clientHeaders();

    final http.Response enabled;
    try {
      enabled = await http
          .get(Uri.parse('$url/QuickConnect/Enabled'), headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw QuickConnectException("Couldn't reach the server. Check the address and your network.");
    }
    if (enabled.statusCode != 200 || enabled.body.trim() != 'true') {
      throw QuickConnectException('Quick Connect is turned off on this server. An admin can turn it on in the Jellyfin dashboard.');
    }

    final res = await http.post(Uri.parse('$url/QuickConnect/Initiate'), headers: headers);
    if (res.statusCode != 200) {
      throw QuickConnectException('The server refused to start Quick Connect (${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return QuickConnectRequest(url: url, code: json['Code'] as String, secret: json['Secret'] as String);
  }

  /// Step 2: whether the code has been approved yet. Call every few seconds.
  /// Throws once the code has expired (the server forgets it after a few minutes).
  Future<bool> isQuickConnectApproved(QuickConnectRequest request) async {
    final res = await http.get(
      Uri.parse('${request.url}/QuickConnect/Connect?secret=${Uri.encodeQueryComponent(request.secret)}'),
      headers: await _clientHeaders(),
    );
    if (res.statusCode == 404) throw QuickConnectException('This code has expired. Get a new one.');
    if (res.statusCode != 200) return false; // a blip; try again next time
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['Authenticated'] == true;
  }

  /// Step 3: signs in with an approved code.
  Future<void> finishQuickConnect(QuickConnectRequest request) async {
    final res = await http.post(
      Uri.parse('${request.url}/Users/AuthenticateWithQuickConnect'),
      headers: {...await _clientHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'Secret': request.secret}),
    );
    if (res.statusCode != 200) {
      throw QuickConnectException('Signing in failed (${res.statusCode}). Try again with a new code.');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final token = json['AccessToken'] as String;
    final userId = (json['User'] as Map<String, dynamic>)['Id'] as String;

    final deviceId = await _deviceId(); // the id Quick Connect was started with
    final newClient = await _createClient(request.url, deviceId: deviceId);
    serverName = (await newClient.system.publicInfo()).serverName;
    await _switchSession(newClient, request.url, token, userId, deviceId);
  }

  Future<void> _refresh() async {
    final c = client!;
    final (me, views, genreResult) = await (
    c.user.currentUser(),
    c.library.userViews(),
    c.genres.list(
      includeItemTypes: const ['Movie', 'Series'],
    ), // drop to include music genres
    ).wait;

    userName = me.name;
    final tag = me.primaryImageTag;
    userImage = tag == null
        ? null
        : NetworkImage('${c.baseUrl}/UserImage?userId=${me.id}&tag=$tag');

    // Keep the saved account's name and picture current for the "Who's watching?" screen.
    final saved = currentAccount;
    if (saved != null && (saved.name != me.name || saved.imageTag != tag)) {
      await _rememberAccount(
        SavedAccount(
          server: saved.server,
          userId: saved.userId,
          token: saved.token,
          deviceId: saved.deviceId,
          name: me.name,
          imageTag: tag,
        ),
      );
    } else if (saved == null && c.token != null && c.baseUrl != null) {
      // An install from before saved accounts: remember the restored session.
      await _rememberAccount(
        SavedAccount(
          server: c.baseUrl!,
          userId: me.id,
          token: c.token!,
          deviceId: '', // signed in with this install's plain id
          name: me.name,
          imageTag: tag,
        ),
      );
    }

    libraries = [
      for (final v in views)
        JellyfinLibrary(
          id: v.id,
          name: v.name,
          collectionType: v.collectionType,
        ),
    ];
    genres = [for (final g in genreResult.items) g.name];
    notifyListeners();
  }

  /// Signs out the current user and removes them from this device.
  /// Other saved accounts stay, and the app goes to "Who's watching?" (or login if none are left).
  Future<void> signOut() async {
    final c = client;
    final server = c?.baseUrl;
    final userId = c?.userId;

    try {
      // Not wrapped by the package yet, so use its escape hatch.
      await c?.request<void>('/Sessions/Logout', method: 'POST');
    } catch (_) {
      // Signing out locally still works if the server is unreachable.
    }
    if (server != null && userId != null) {
      await _forgetAccount(server, userId, );
    }
    await _clearSession();
  }

  Future<void> _clearSession() async {
    await storage.remove(_kToken);
    await storage.remove(
      _kUserId,
    ); // the server address is kept to pre-fill login
    storage.useUser(null, null);
    client?.clearSession();
    client = null;
    userName = null;
    userImage = null;
    libraries = const [];
    genres = const [];
    notifyListeners();
    _clearCaches();
  }

  void _clearCaches() {
    clearHomeCache(); // another account sees different recommendations and progress
    appCache.clear();
  }
}

late final JellyfinController jellyfin;