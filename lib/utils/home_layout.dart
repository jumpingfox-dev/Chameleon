import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every kind of section the home screen can show. Add new ones here.
enum HomeModuleType {
  carousel,
  continueWatching,
  nextUp,
  favorites,
  recentlyAdded,
  recentlyAddedMovies,
  recentlyAddedSeries,
  suggested,
  becauseYouWatched,
  collection,
  genre;

  /// Types you can add more than once, each showing something different.
  bool get allowsMultiple => this == collection || this == genre;
}

/// One section on the home screen: its type, what it shows, and how.
@immutable
class HomeModule {
  const HomeModule({
    required this.id,
    required this.type,
    this.param,
    this.label,
    this.view,
  });

  /// Unique within the layout, so two Genre sections can be told apart.
  final String id;
  final HomeModuleType type;

  /// What the section shows: a collection's id, or a genre's name.
  final String? param;

  /// A display name for [param], e.g. the collection's name.
  final String? label;

  /// 'poster' or 'thumbnail', or null for the type's default.
  final String? view;

  HomeModule withView(String? view) =>
      HomeModule(id: id, type: type, param: param, label: label, view: view);

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'param': param,
    'label': label,
    'view': view,
  };

  static HomeModule? fromJson(Map<String, dynamic> json) {
    final type = HomeModuleType.values.asNameMap()[json['type']];
    if (type == null)
      return null; // a type from a newer or older version: skip it
    return HomeModule(
      id: (json['id'] as String?) ?? type.name,
      type: type,
      param: json['param'] as String?,
      label: json['label'] as String?,
      view: json['view'] as String?,
    );
  }
}

/// The home screen's sections, in order, saved between launches.
class HomeLayoutController extends ValueNotifier<List<HomeModule>> {
  HomeLayoutController._(super.value);

  static const _key = 'home_layout';

  /// What a new user sees.
  static const defaultTypes = [
    HomeModuleType.carousel,
    HomeModuleType.continueWatching,
    HomeModuleType.nextUp,
    HomeModuleType.recentlyAdded,
    HomeModuleType.suggested,
  ];

  static List<HomeModule> get _defaults => [
    for (final t in defaultTypes) HomeModule(id: t.name, type: t),
  ];

  static Future<HomeLayoutController> load() async {
    final prefs = await SharedPreferences.getInstance();

    List<HomeModule>? modules;
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        modules = [
          for (final entry in jsonDecode(raw) as List)
            if (HomeModule.fromJson(entry as Map<String, dynamic>)
                case final module?)
              module,
        ];
      } catch (_) {
        // Unreadable: fall back below.
      }
    }
    modules ??= _migrateOldLayout(prefs) ?? _defaults;
    return HomeLayoutController._(List.unmodifiable(modules));
  }

  /// Carries over a layout saved by the earlier version: a list of type names, plus "type=view" entries.
  static List<HomeModule>? _migrateOldLayout(SharedPreferences prefs) {
    final names = prefs.getStringList('home_modules');
    if (names == null) return null;
    final byName = HomeModuleType.values.asNameMap();
    final views = <String, String>{
      for (final entry
          in prefs.getStringList('home_module_views') ?? const <String>[])
        if (entry.split('=') case [final name, final view]) name: view,
    };
    return [
      for (final name in names)
        if (byName[name] case final type?)
          HomeModule(id: type.name, type: type, view: views[name]),
    ];
  }

  /// Section types you can still add: any not on the screen yet, plus the ones allowed more than once.
  List<HomeModuleType> get available => HomeModuleType.values
      .where((t) => t.allowsMultiple || !value.any((m) => m.type == t))
      .toList();

  Future<void> add(HomeModuleType type, {String? param, String? label}) =>
      _save([
        ...value,
        HomeModule(
          id: '${type.name}-${DateTime.now().microsecondsSinceEpoch}',
          type: type,
          param: param,
          label: label,
        ),
      ]);

  Future<void> remove(String id) =>
      _save(value.where((m) => m.id != id).toList());

  /// Moves a section up (-1) or down (+1).
  Future<void> move(String id, int by) async {
    final list = [...value];
    final from = list.indexWhere((m) => m.id == id);
    final to = from + by;
    if (from < 0 || to < 0 || to >= list.length) return;
    list.insert(to, list.removeAt(from));
    await _save(list);
  }

  Future<void> setView(String id, String view) =>
      _save([for (final m in value) m.id == id ? m.withView(view) : m]);

  /// Back to the default sections, order and views.
  Future<void> reset() => _save(_defaults);

  Future<void> _save(List<HomeModule> modules) async {
    value = List.unmodifiable(modules);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final m in modules) m.toJson()]),
    );
  }
}

late final HomeLayoutController homeLayout;
