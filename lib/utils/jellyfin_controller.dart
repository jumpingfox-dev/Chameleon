import 'dart:math';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_cache.dart';

class JellyfinLibrary {
  const JellyfinLibrary({required this.id, required this.name, this.collectionType});

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
  final scheme = uri.scheme == 'https' ? 'https://' : ''; // http is the default, so hide it
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
    JellyfinErrorType.connection => "Couldn't reach the server. Check the address and your network.",
    JellyfinErrorType.timeout => 'The server took too long to respond.',
    JellyfinErrorType.auth => 'Wrong username or password.',
    JellyfinErrorType.notFound => "That address doesn't look like a Jellyfin server.",
    _ => error.message,
  };
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

  bool get isConnected => client?.token != null && client?.userId != null;

  String get initials {
    final name = userName?.trim() ?? '';
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    return parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// A random id for this install. Jellyfin tracks sessions by it, so it must stay stable.
  Future<String> _deviceId(SharedPreferences prefs) async {
    var id = prefs.getString(_kDeviceId);
    if (id == null) {
      final random = Random.secure();
      id = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  Future<JellyfinClient> _createClient(String url, SharedPreferences prefs) async => JellyfinClient(
    baseUrl: url,
    credentials: JellyfinCredentials(
      client: _clientName,
      device: defaultTargetPlatform.name,
      deviceId: await _deviceId(prefs),
      version: _clientVersion,
    ),
  );

  /// Restores a saved session at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    lastServer = prefs.getString(_kServer);
    final token = prefs.getString(_kToken);
    final userId = prefs.getString(_kUserId);
    if (lastServer == null || token == null || userId == null) return;

    client = await _createClient(lastServer!, prefs)
      ..setSession(token: token, userId: userId);

    try {
      await _refresh();
    } on JellyfinException catch (e) {
      if (e.isAuthError) await _clearSession(); // token revoked or expired: back to login
      // Connection errors (server offline) keep the session, so you stay signed in.
    }
  }

  Future<void> signIn({required String server, required String username, required String password}) async {
    final prefs = await SharedPreferences.getInstance();
    final url = normalizeServerUrl(server);
    final newClient = await _createClient(url, prefs);

    // Confirms the address is a Jellyfin server before sending credentials.
    serverName = (await newClient.system.publicInfo()).serverName;

    final auth = await newClient.user.authenticateByName(username: username, password: password);
    newClient.setSession(token: auth.accessToken, userId: auth.user.id);

    client = newClient;
    lastServer = url;
    await prefs.setString(_kServer, url);
    await prefs.setString(_kToken, auth.accessToken);
    await prefs.setString(_kUserId, auth.user.id);

    await _refresh();
  }

  Future<void> _refresh() async {
    final c = client!;
    final (me, views, genreResult) = await (
    c.user.currentUser(),
    c.library.userViews(),
    c.genres.list(includeItemTypes: const ['Movie', 'Series']), // drop to include music genres
    ).wait;

    userName = me.name;
    final tag = me.primaryImageTag;
    userImage = tag == null ? null : NetworkImage('${c.baseUrl}/UserImage?userId=${me.id}&tag=$tag');

    libraries = [
      for (final v in views) JellyfinLibrary(id: v.id, name: v.name, collectionType: v.collectionType),
    ];
    genres = [for (final g in genreResult.items) g.name];
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      // Not wrapped by the package yet, so use its escape hatch.
      await client?.request<void>('/Sessions/Logout', method: 'POST');
    } catch (_) {
      // Signing out locally still works if the server is unreachable.
    }
    await _clearSession();
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId); // the server address is kept to pre-fill login
    client?.clearSession();
    client = null;
    userName = null;
    userImage = null;
    libraries = const [];
    genres = const [];
    notifyListeners();
    libraryCache.clear(); // another account may see different libraries
  }
}

late final JellyfinController jellyfin;