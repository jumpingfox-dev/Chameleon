import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'custom_colors.dart';
import 'theme_presets.dart';

const customThemeId = 'custom';
const defaultSeed = ThemeSeed(270, 280, 8, 1);

class ThemeController extends ValueNotifier<ThemePreset> {
  ThemeController._(
    super.value,
    this._custom,
    this._seed,
    this._customIni,
    this._advanced,
  );

  static const _key = 'selected_theme';
  static const _seedKey = 'custom_seed';
  static const _iniKey = 'custom_ini';
  static const _advancedKey = 'custom_advanced';

  ThemePreset _custom;
  ThemeSeed _seed;
  String? _customIni;
  bool _advanced;

  ThemePreset get customPreset => _custom;
  ThemeSeed get seed => _seed;
  bool get advanced => _advanced;
  List<ThemePreset> get allPresets => [...themePresets, _custom];

  /// The saved INI, or the current seed written out as INI if none has been saved yet.
  String get customIni => _customIni ?? colorsToIni(generateColors(_seed));

  static FColors _resolve(ThemeSeed seed, String? ini, bool advanced) {
    final seedColors = generateColors(seed);
    if (!advanced || ini == null) return seedColors;
    return parseColorIni(ini, seedColors).colors ?? seedColors;
  }

  static ThemePreset _preset(FColors colors) =>
      ThemePreset(id: customThemeId, label: 'Custom', colors: colors);

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();

    final seed =
        ThemeSeed.parse(prefs.getString(_seedKey) ?? '') ?? defaultSeed;
    final ini = prefs.getString(_iniKey);
    final advanced = prefs.getBool(_advancedKey) ?? false;
    final custom = _preset(_resolve(seed, ini, advanced));

    final savedId = prefs.getString(_key);
    final selected = [
      ...themePresets,
      custom,
    ].firstWhere((p) => p.id == savedId, orElse: () => themePresets.first);
    return ThemeController._(selected, custom, seed, ini, advanced);
  }

  Future<void> select(ThemePreset preset) async {
    value = preset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, preset.id);
  }

  /// Simple mode: build the whole theme from a seed.
  Future<void> applySeed(ThemeSeed seed) async {
    _seed = seed;
    _activate();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seedKey, seed.code);
    await prefs.setString(_key, customThemeId);
  }

  /// Switches between the seed steppers and the INI editor.
  Future<void> setAdvanced(bool on) async {
    _advanced = on;
    _activate();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_advancedKey, on);
    await prefs.setString(_key, customThemeId);
  }

  /// Advanced mode: applies INI text on top of the current seed. Returns errors, or an empty list.
  Future<List<String>> applyCustomIni(String text) async {
    final result = parseColorIni(text, generateColors(_seed));
    if (result.errors.isNotEmpty) return result.errors;

    _customIni = text;
    _advanced = true;
    _activate();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_iniKey, text);
    await prefs.setBool(_advancedKey, true);
    await prefs.setString(_key, customThemeId);
    return const [];
  }

  void _activate() {
    _custom = _preset(_resolve(_seed, _customIni, _advanced));
    value = _custom; // new instance, so listeners always fire
  }
}

late final ThemeController themeController;
