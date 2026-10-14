import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../core/storage/storage.dart';

/// Every Google Fonts family, alphabetical.
final allFonts = GoogleFonts.asMap().keys.toList()..sort();

/// Shown when the search box is empty.
const suggestedFonts = [
  'Space Grotesk',
  'Instrument Sans',
  'Inter',
  'DM Sans',
  'Manrope',
  'Outfit',
  'Sora',
  'Poppins',
  'Montserrat',
  'Nunito',
  'Work Sans',
  'IBM Plex Sans',
  'Playfair Display',
  'Lora',
  'JetBrains Mono',
];

/// Deletes cached Google Fonts files except those for [keepFamilies].
Future<void> pruneFontCache(Iterable<String> keepFamilies) async {
  if (kIsWeb) return; // the web has no font file cache to clean

  final dir = await getApplicationSupportDirectory();
  if (!await dir.exists()) return;

  // "Space Grotesk" -> "spacegrotesk_" to match cached names like "SpaceGrotesk_700.ttf".
  String normalize(String s) => s.replaceAll(' ', '').toLowerCase();
  final keep = [for (final f in keepFamilies) '${normalize(f)}_'];

  await for (final entity in dir.list()) {
    if (entity is! File) continue;

    final name = entity.uri.pathSegments.last;
    final lower = name.toLowerCase();
    // Only touch font files. Other data lives in this folder too, such as shared_preferences on Linux.
    if (!lower.endsWith('.ttf') && !lower.endsWith('.otf')) continue;

    if (keep.any((prefix) => normalize(name).startsWith(prefix))) continue;

    try {
      await entity.delete();
    } catch (_) {
      // A file in use or already gone isn't worth crashing over.
    }
  }
}

/// Fonts known to be downloaded and ready this session.
final loadedFonts = <String>{};

const _preloadCount = 8; // about one screen of results

List<String> _matchFonts(String query, int limit) {
  if (query.trim().isEmpty) return suggestedFonts;
  final q = query.trim().toLowerCase();
  final starts = <String>[];
  final contains = <String>[];
  for (final font in allFonts) {
    final name = font.toLowerCase();
    if (name.startsWith(q)) {
      starts.add(font);
    } else if (name.contains(q)) {
      contains.add(font);
    }
  }
  return [...starts, ...contains].take(limit).toList();
}

/// Starts downloading [fonts] and waits until they're ready, or until the timeout.
Future<void> preloadFonts(Iterable<String> fonts) async {
  final toLoad = fonts.where((f) => !loadedFonts.contains(f)).toList();
  if (toLoad.isEmpty) return;
  for (final font in toLoad) {
    GoogleFonts.getFont(font); // starts the download
  }
  try {
    await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 4));
  } catch (_) {
    // Offline or slow: show the list anyway and let rows fall back.
  }
  loadedFonts.addAll(toLoad);
}

/// Search, then wait for the first screenful of fonts before returning.
Future<Iterable<String>> searchFonts(String query, {int limit = 60}) async {
  final results = _matchFonts(query, limit);
  await preloadFonts(results.take(_preloadCount));
  return results;
}

class FontController extends ChangeNotifier {
  FontController._(this._display, this._body);

  static const defaultDisplay = 'Space Grotesk';
  static const defaultBody = 'Instrument Sans';
  static const _displayKey = 'font_display';
  static const _bodyKey = 'font_body';

  String _display;
  String _body;

  String get display => _display;
  String get body => _body;

  static Future<FontController> load() async =>
      FontController._(_saved(_displayKey, defaultDisplay), _saved(_bodyKey, defaultBody));

  static String _saved(String key, String fallback) {
    final saved = storage.getString(key);
    return saved != null && GoogleFonts.asMap().containsKey(saved) ? saved : fallback;
  }

  /// Loads the fonts saved for whoever is signed in now (see Storage.user).
  void reload() {
    _display = _saved(_displayKey, defaultDisplay);
    _body = _saved(_bodyKey, defaultBody);
    notifyListeners();
  }

  Future<void> setDisplay(String font) async {
    _display = font;
    notifyListeners();
    await storage.setString(_displayKey, font);
  }

  Future<void> setBody(String font) async {
    _body = font;
    notifyListeners();
    await storage.setString(_bodyKey, font);
  }
}

late final FontController fontController;
