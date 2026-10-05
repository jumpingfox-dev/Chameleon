import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import 'jellyfin_controller.dart';

/// A language from the server's list, e.g. (code: 'eng', name: 'English').
/// An empty code means "no preference".
typedef Language = ({String code, String name});

const anyLanguage = (code: '', name: 'Any language');

/// How subtitles are chosen when a video starts. [value] is what Jellyfin stores.
enum SubtitleMode {
  defaultMode('Default', 'Default'),
  smart('Smart', 'Smart'),
  onlyForced('OnlyForced', 'Only Forced'),
  always('Always', 'Always'),
  none('None', 'Off');

  const SubtitleMode(this.value, this.label);
  final String value;
  final String label;

  static SubtitleMode fromValue(String? value) =>
      values.firstWhere((m) => m.value == value, orElse: () => defaultMode);
}

/// The signed-in user's playback preferences, stored on the Jellyfin server
/// (so they match the web app and every other client), plus Quick Connect.
///
/// Call [load] when the Account tab opens. Every setter saves straight to the server.
class AccountSettings extends ChangeNotifier {
  bool loading = false;
  String? error; // set when the server couldn't be reached

  String? _userId;
  Map<String, dynamic> _config = {}; // the user's full configuration, sent back whole on save
  Map<String, dynamic> _policy = {}; // what an admin allows this user (read-only here)

  List<Language> languages = const [anyLanguage];
  List<({String name, int value})> _ratings = const [];
  bool quickConnectEnabled = false;

  // ── Reading ──

  Language get audioLanguage => _language(_config['AudioLanguagePreference']);
  Language get subtitleLanguage => _language(_config['SubtitleLanguagePreference']);
  SubtitleMode get subtitleMode => SubtitleMode.fromValue(_config['SubtitleMode'] as String?);

  /// The highest age rating this user may watch, e.g. 'PG-13', or null for no limit.
  String? get maxRating {
    final max = _policy['MaxParentalRating'];
    if (max is! num) return null;
    // Several ratings can share a value (PG-13, 12A …); show the first one.
    for (final r in _ratings) {
      if (r.value == max) return r.name;
    }
    return 'Level $max';
  }

  bool get isAdmin => _policy['IsAdministrator'] as bool? ?? false;

  Language _language(Object? code) {
    if (code is! String || code.isEmpty) return anyLanguage;
    return languages.firstWhere((l) => l.code == code, orElse: () => (code: code, name: code));
  }

  // ── Loading ──

  String? get _baseUrl => jellyfin.client?.baseUrl;

  // TODO(cleanup): use a shared getJson on JellyfinController
  Future<dynamic> _get(String path) async {
    final res = await http
        .get(Uri.parse('$_baseUrl$path'), headers: jellyfin.authHeaders)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('GET $path → ${res.statusCode}');
    return jsonDecode(res.body);
  }

  Future<void> load() async {
    if (_baseUrl == null) {
      error = 'Not connected to a server.';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _get('/Users/Me'),
        _get('/Localization/Cultures'),
        _get('/Localization/ParentalRatings'),
        _get('/QuickConnect/Enabled').catchError((_) => false), // older servers may not have it
      ]);

      final me = results[0] as Map<String, dynamic>;
      _userId = me['Id'] as String?;
      _config = Map<String, dynamic>.from(me['Configuration'] as Map? ?? {});
      _policy = Map<String, dynamic>.from(me['Policy'] as Map? ?? {});

      languages = [
        anyLanguage,
        ...[
          for (final c in results[1] as List)
            if ((c['ThreeLetterISOLanguageName'] as String?)?.isNotEmpty ?? false)
              (code: c['ThreeLetterISOLanguageName'] as String, name: c['DisplayName'] as String),
        ]..sort((a, b) => a.name.compareTo(b.name)),
      ];

      _ratings = [
        for (final r in results[2] as List)
          if (r['Value'] is num) (name: r['Name'] as String, value: (r['Value'] as num).toInt()),
      ];

      quickConnectEnabled = results[3] == true;
    } catch (e) {
      error = 'Couldn\'t load your account settings.';
      debugPrint('AccountSettings.load: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Saving ──

  Future<void> setAudioLanguage(Language l) => _save('AudioLanguagePreference', l.code);
  Future<void> setSubtitleLanguage(Language l) => _save('SubtitleLanguagePreference', l.code);
  Future<void> setSubtitleMode(SubtitleMode m) => _save('SubtitleMode', m.value);

  /// Changes one setting, shows it straight away, and saves the whole configuration.
  /// If saving fails, the old value comes back.
  Future<void> _save(String key, Object value) async {
    final old = _config[key];
    _config[key] = value;
    notifyListeners();

    try {
      final body = jsonEncode(_config);
      final headers = {...jellyfin.authHeaders, 'Content-Type': 'application/json'};

      // Jellyfin 10.9+; older servers only have the second form.
      var res = await http.post(
        Uri.parse('$_baseUrl/Users/Configuration?userId=$_userId'),
        headers: headers,
        body: body,
      );
      if (res.statusCode == 404 || res.statusCode == 405) {
        res = await http.post(
          Uri.parse('$_baseUrl/Users/$_userId/Configuration'),
          headers: headers,
          body: body,
        );
      }
      if (res.statusCode >= 300) throw Exception('save → ${res.statusCode}');
    } catch (e) {
      debugPrint('AccountSettings._save($key): $e');
      _config[key] = old;
      error = 'Couldn\'t save that change. Check your connection.';
      notifyListeners();
    }
  }

  // ── Quick Connect ──

  /// Signs in the device showing [code] as this user. Returns true if it worked.
  Future<bool> authorizeQuickConnect(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || _baseUrl == null) return false;
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/QuickConnect/Authorize?code=${Uri.encodeQueryComponent(trimmed)}'
            '${_userId == null ? '' : '&userId=$_userId'}'),
        headers: jellyfin.authHeaders,
      );
      return res.statusCode == 200 && res.body.trim() == 'true';
    } catch (e) {
      debugPrint('AccountSettings.authorizeQuickConnect: $e');
      return false;
    }
  }
}