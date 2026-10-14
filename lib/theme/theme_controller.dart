import 'package:flutter/foundation.dart';

import 'custom_colors.dart';
import 'palette.dart';
import 'theme_presets.dart';
import '../core/storage/storage.dart';

const customThemeId = 'custom';
const defaultSeed = ThemeSeed(270, 280, 8, 1);

class ThemeController extends ValueNotifier<ThemePreset> {
  ThemeController._(super.value, this._custom, this._seed, this._customIni, this._advanced);

  static const _key = 'selected_theme';
  static const _seedKey = 'custom_seed';
  static const _iniKey = 'custom_ini';
  static const _advancedKey = 'custom_advanced';

  ThemePreset _custom;
  ThemeSeed _seed;
  String? _customIni;
  bool _advanced;

  ThemeSeed get seed => _seed;
  bool get advanced => _advanced;
  List<ThemePreset> get allPresets => [...themePresets, _custom];

  /// The saved INI, or the current seed written out as INI if none has been saved yet.
  String get customIni => _customIni ?? colorsToIni(generateColors(_seed));

  static Palette _resolve(ThemeSeed seed, String? ini, bool advanced) {
    final seedColors = generateColors(seed);
    if (!advanced || ini == null) return seedColors;
    return parseColorIni(ini, seedColors).colors ?? seedColors;
  }

  static ThemePreset _preset(Palette colors) => ThemePreset(id: customThemeId, label: 'Custom', colors: colors);

  static Future<ThemeController> load() async {
    final saved = _readSaved();
    return ThemeController._(saved.selected, saved.custom, saved.seed, saved.ini, saved.advanced);
  }

  static ({ThemePreset selected, ThemePreset custom, ThemeSeed seed, String? ini, bool advanced}) _readSaved() {
    final seed = ThemeSeed.parse(storage.getString(_seedKey) ?? '') ?? defaultSeed;
    final ini = storage.getString(_iniKey);
    final advanced = storage.getBool(_advancedKey) ?? false;
    final custom = _preset(_resolve(seed, ini, advanced));

    final savedId = storage.getString(_key);
    final selected = [...themePresets, custom].firstWhere((p) => p.id == savedId, orElse: () => themePresets.first);
    return (selected: selected, custom: custom, seed: seed, ini: ini, advanced: advanced);
  }

  /// Loads the theme saved for whoever is signed in now (see Storage.user).
  void reload() {
    final saved = _readSaved();
    _seed = saved.seed;
    _customIni = saved.ini;
    _advanced = saved.advanced;
    _custom = saved.custom;
    value = saved.selected;
  }

  Future<void> select(ThemePreset preset) async {
    value = preset;
    await storage.setString(_key, preset.id);
  }

  /// Simple mode: build the whole theme from a seed.
  Future<void> applySeed(ThemeSeed seed) async {
    _seed = seed;
    _activate();
    await storage.setString(_seedKey, seed.code);
    await storage.setString(_key, customThemeId);
  }

  /// Switches between the seed steppers and the INI editor.
  Future<void> setAdvanced(bool on) async {
    _advanced = on;
    _activate();
    await storage.setBool(_advancedKey, on);
    await storage.setString(_key, customThemeId);
  }

  /// Advanced mode: applies INI text on top of the current seed. Returns errors, or an empty list.
  Future<List<String>> applyCustomIni(String text) async {
    final result = parseColorIni(text, generateColors(_seed));
    if (result.errors.isNotEmpty) return result.errors;

    _customIni = text;
    _advanced = true;
    _activate();
    await storage.setString(_iniKey, text);
    await storage.setBool(_advancedKey, true);
    await storage.setString(_key, customThemeId);
    return const [];
  }

  void _activate() {
    _custom = _preset(_resolve(_seed, _customIni, _advanced));
    value = _custom; // new instance, so listeners always fire
  }
}

late final ThemeController themeController;
