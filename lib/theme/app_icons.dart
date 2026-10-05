import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:forui_lucide/forui_lucide.dart';
import 'package:forui_phosphor/forui_phosphor.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which family of icons the app uses.
enum IconStyle {
  materialSymbols('Material Symbols'),
  phosphor('Phosphor'),
  lucide('Lucide'),
  cupertino('Cupertino'),
  fluent('Fluent');

  const IconStyle(this.label);
  final String label;
}

/// Every icon in the app, named by what it means. Screens use these names (via [appIcons]),
/// never an icon pack directly, so the whole app can switch styles at once.
///
/// Each icon is one entry, in [IconStyle] order:
/// `_pick(material symbols, phosphor fill, lucide, cupertino, fluent)`.
/// Solid wherever a set has it: Material Symbols with `fill: 1`, Phosphor Fill,
/// Cupertino's `_fill`/`_solid` icons and Fluent's `_filled` icons.
/// Lucide is outline-only, as are simple line glyphs (arrows, chevrons, ✓, ✕, +, −).
class AppIconSet {
  const AppIconSet._(this.style);

  final IconStyle style;

  IconData _pick(
      IconData material,
      IconData phosphor,
      IconData lucide,
      IconData cupertino,
      IconData fluent,
      ) => switch (style) {
    IconStyle.materialSymbols => material,
    IconStyle.phosphor => phosphor,
    IconStyle.lucide => lucide,
    IconStyle.cupertino => cupertino,
    IconStyle.fluent => fluent,
  };

  // ── Navigation ──
  IconData get home => _pick(
      Symbols.home_rounded,
      FPhosphorFillIcons.house,
      FLucideIcons.house,
      CupertinoIcons.house_fill,
      FluentIcons.home_24_filled
  );
  IconData get search => _pick(
      Symbols.search_rounded,
      FPhosphorFillIcons.magnifyingGlass,
      FLucideIcons.search,
      CupertinoIcons.search,
      FluentIcons.search_24_filled
  );
  IconData get settings => _pick(
      Symbols.settings_rounded,
      FPhosphorFillIcons.gear,
      FLucideIcons.settings,
      CupertinoIcons.settings_solid,
      FluentIcons.settings_24_filled
  );
  IconData get profile => _pick(
      Symbols.person_rounded,
      FPhosphorFillIcons.user,
      FLucideIcons.user,
      CupertinoIcons.person_fill,
      FluentIcons.person_24_filled
  );
  IconData get genres => _pick(
      Symbols.label_rounded,
      FPhosphorFillIcons.tag,
      FLucideIcons.tag,
      CupertinoIcons.tag_fill,
      FluentIcons.tag_24_filled
  );
  IconData get back => _pick(
      Symbols.arrow_back_ios_new_rounded,
      FPhosphorFillIcons.caretLeft,
      FLucideIcons.chevronLeft,
      CupertinoIcons.chevron_back,
      FluentIcons.chevron_left_24_filled
  );
  IconData get close => _pick(
      Symbols.close_rounded,
      FPhosphorIcons.x,
      FLucideIcons.x,
      CupertinoIcons.xmark,
      FluentIcons.dismiss_24_filled
  );

  // ── Media ──
  IconData get play => _pick(
      Symbols.play_circle_rounded,
      FPhosphorFillIcons.playCircle,
      FLucideIcons.circlePlay,
      CupertinoIcons.play_circle_fill,
      FluentIcons.play_circle_24_filled
  );
  IconData get shuffle => _pick(
      Symbols.shuffle_rounded,
      FPhosphorFillIcons.shuffle,
      FLucideIcons.shuffle,
      CupertinoIcons.shuffle,
      FluentIcons.arrow_shuffle_24_filled
  );
  IconData get pause => _pick(
      Symbols.pause_rounded,
      FPhosphorFillIcons.pause,
      FLucideIcons.pause,
      CupertinoIcons.pause_fill,
      FluentIcons.pause_24_filled
  );
  IconData get previous => _pick(
      Symbols.skip_previous_rounded,
      FPhosphorFillIcons.skipBack,
      FLucideIcons.skipBack,
      CupertinoIcons.backward_end_fill,
      FluentIcons.previous_24_filled
  );
  IconData get next => _pick(
      Symbols.skip_next_rounded,
      FPhosphorFillIcons.skipForward,
      FLucideIcons.skipForward,
      CupertinoIcons.forward_end_fill,
      FluentIcons.next_24_filled
  );
  IconData get audio => _pick(
      Symbols.graphic_eq_rounded,
      FPhosphorFillIcons.waveform,
      FLucideIcons.audioWaveform,
      CupertinoIcons.waveform_circle_fill,
      FluentIcons.sound_wave_circle_24_filled
  );
  IconData get subtitles => _pick(
      Symbols.subtitles_rounded,
      FPhosphorFillIcons.subtitles,
      FLucideIcons.captions,
      CupertinoIcons.captions_bubble_fill,
      FluentIcons.closed_caption_24_filled
  );
  IconData get fill => _pick(
      Symbols.zoom_out_map_rounded,
      FPhosphorFillIcons.cornersOut,
      FLucideIcons.maximize,
      CupertinoIcons.fullscreen,
      FluentIcons.full_screen_maximize_24_filled
  ); // zoom in to fill the screen
  IconData get fit => _pick(
      Symbols.zoom_in_map_rounded,
      FPhosphorFillIcons.cornersIn,
      FLucideIcons.minimize,
      CupertinoIcons.fullscreen_exit,
      FluentIcons.full_screen_minimize_24_filled
  ); // back to the whole picture

  // ── Items ──
  IconData get favorite => _pick(
      Symbols.favorite_rounded,
      FPhosphorFillIcons.heart,
      FLucideIcons.heart,
      CupertinoIcons.heart_fill,
      FluentIcons.heart_24_filled
  );
  IconData get favoriteOutline => _pick(
      Symbols.favorite_rounded, // same icon, drawn with fill: 0
      FPhosphorIcons.heart,
      FLucideIcons.heart,
      CupertinoIcons.heart,
      FluentIcons.heart_24_regular
  ); // not favorited yet
  IconData get star => _pick(
      Symbols.star_rounded,
      FPhosphorFillIcons.star,
      FLucideIcons.star,
      CupertinoIcons.star_fill,
      FluentIcons.star_24_filled
  );

  // ── Home editing ──
  IconData get edit => _pick(
      Symbols.edit_rounded,
      FPhosphorFillIcons.pencilSimple,
      FLucideIcons.pencil,
      CupertinoIcons.pencil,
      FluentIcons.edit_24_filled
  );
  IconData get moveUp => _pick(
      Symbols.arrow_upward_rounded,
      FPhosphorFillIcons.arrowUp,
      FLucideIcons.arrowUp,
      CupertinoIcons.arrow_up,
      FluentIcons.arrow_up_24_filled
  );
  IconData get moveDown => _pick(
      Symbols.arrow_downward_rounded,
      FPhosphorFillIcons.arrowDown,
      FLucideIcons.arrowDown,
      CupertinoIcons.arrow_down,
      FluentIcons.arrow_down_24_filled
  );
  IconData get remove => _pick(
      Symbols.delete_rounded,
      FPhosphorFillIcons.trash,
      FLucideIcons.trash2,
      CupertinoIcons.trash_fill,
      FluentIcons.delete_24_filled
  );
  IconData get reset => _pick(
      Symbols.restart_alt_rounded,
      FPhosphorFillIcons.arrowCounterClockwise,
      FLucideIcons.rotateCcw,
      CupertinoIcons.arrow_counterclockwise,
      FluentIcons.arrow_counterclockwise_24_filled
  );

  // ── General ──
  IconData get check => _pick(
      Symbols.check_rounded,
      FPhosphorIcons.check,
      FLucideIcons.check,
      CupertinoIcons.checkmark,
      FluentIcons.checkmark_24_filled
  );
  IconData get expand => _pick(
      Symbols.expand_more_rounded,
      FPhosphorFillIcons.caretDown,
      FLucideIcons.chevronDown,
      CupertinoIcons.chevron_down,
      FluentIcons.chevron_down_24_filled
  );
  IconData get collapse => _pick(
      Symbols.expand_less_rounded,
      FPhosphorFillIcons.caretUp,
      FLucideIcons.chevronUp,
      CupertinoIcons.chevron_up,
      FluentIcons.chevron_up_24_filled
  );
  IconData get error => _pick(
      Symbols.error_rounded,
      FPhosphorFillIcons.warningCircle,
      FLucideIcons.circleAlert,
      CupertinoIcons.exclamationmark_circle_fill,
      FluentIcons.error_circle_24_filled
  );
  IconData get stepBack => _pick(
      Symbols.remove_rounded,
      FPhosphorFillIcons.minus,
      FLucideIcons.minus,
      CupertinoIcons.minus,
      FluentIcons.subtract_24_filled
  ); // theme editor steppers
  IconData get stepForward => _pick(
      Symbols.add_rounded,
      FPhosphorFillIcons.plus,
      FLucideIcons.plus,
      CupertinoIcons.plus,
      FluentIcons.add_24_filled
  );

  // ── Home sections ──
  IconData get info => _pick(
      Symbols.info_rounded,
      FPhosphorFillIcons.info,
      FLucideIcons.info,
      CupertinoIcons.info_circle_fill,
      FluentIcons.info_24_filled
  ); // "More info"
  IconData get featured => _pick(
      Symbols.slideshow_rounded,
      FPhosphorFillIcons.slideshow,
      FLucideIcons.galleryHorizontalEnd,
      CupertinoIcons.rectangle_stack_fill,
      FluentIcons.slide_multiple_24_filled
  );
  IconData get continueWatching => _pick(
      Symbols.play_circle_rounded,
      FPhosphorFillIcons.playCircle,
      FLucideIcons.circlePlay,
      CupertinoIcons.play_circle_fill,
      FluentIcons.play_circle_24_filled
  );
  IconData get shows => _pick(
      Symbols.tv_rounded,
      FPhosphorFillIcons.television,
      FLucideIcons.tv,
      CupertinoIcons.tv_fill,
      FluentIcons.tv_24_filled
  ); // Next Up, Recently Added Shows
  IconData get movies => _pick(
      Symbols.movie_rounded,
      FPhosphorFillIcons.filmSlate,
      FLucideIcons.clapperboard,
      CupertinoIcons.film_fill,
      FluentIcons.movies_and_tv_24_filled
  );
  IconData get recentlyAdded => _pick(
      Symbols.auto_awesome_rounded,
      FPhosphorFillIcons.sparkle,
      FLucideIcons.sparkles,
      CupertinoIcons.sparkles,
      FluentIcons.sparkle_24_filled
  );
  IconData get suggested => _pick(
      Symbols.lightbulb_rounded,
      FPhosphorFillIcons.lightbulb,
      FLucideIcons.lightbulb,
      CupertinoIcons.lightbulb_fill,
      FluentIcons.lightbulb_24_filled
  );
  IconData get becauseYouWatched => _pick(
      Symbols.history_rounded,
      FPhosphorFillIcons.clockCounterClockwise,
      FLucideIcons.history,
      CupertinoIcons.clock_fill,
      FluentIcons.history_24_filled
  );
  IconData get collection => _pick(
      Symbols.collections_bookmark_rounded,
      FPhosphorFillIcons.stack,
      FLucideIcons.layers,
      CupertinoIcons.square_stack_3d_up_fill,
      FluentIcons.stack_24_filled
  );

  // ── Library types (movies, shows and collection are above) ──
  IconData get music => _pick(
      Symbols.music_note_rounded,
      FPhosphorFillIcons.musicNotes,
      FLucideIcons.music,
      CupertinoIcons.music_note,
      FluentIcons.music_note_2_24_filled
  );
  IconData get playlists => _pick(
      Symbols.queue_music_rounded,
      FPhosphorFillIcons.queue,
      FLucideIcons.listMusic,
      CupertinoIcons.music_albums_fill,
      FluentIcons.apps_list_detail_24_filled
  );
  IconData get musicVideos => _pick(
      Symbols.music_video_rounded,
      FPhosphorFillIcons.monitorPlay,
      FLucideIcons.monitorPlay,
      CupertinoIcons.play_rectangle_fill,
      FluentIcons.video_clip_24_filled
  );
  IconData get homeVideos => _pick(
      Symbols.video_library_rounded,
      FPhosphorFillIcons.filmStrip,
      FLucideIcons.film,
      CupertinoIcons.videocam_fill,
      FluentIcons.video_clip_multiple_24_filled
  );
  IconData get photos => _pick(
      Symbols.photo_library_rounded,
      FPhosphorFillIcons.images,
      FLucideIcons.images,
      CupertinoIcons.photo_fill_on_rectangle_fill,
      FluentIcons.image_multiple_24_filled
  );
  IconData get books => _pick(
      Symbols.menu_book_rounded,
      FPhosphorFillIcons.books,
      FLucideIcons.bookOpen,
      CupertinoIcons.book_fill,
      FluentIcons.book_open_24_filled
  );
  IconData get liveTv => _pick(
      Symbols.live_tv_rounded,
      FPhosphorFillIcons.broadcast,
      FLucideIcons.radioTower,
      CupertinoIcons.antenna_radiowaves_left_right,
      FluentIcons.live_24_filled
  );
  IconData get folder => _pick(
      Symbols.folder_rounded,
      FPhosphorFillIcons.folder,
      FLucideIcons.folder,
      CupertinoIcons.folder_fill,
      FluentIcons.folder_24_filled
  ); // any other kind of library

  // ── Account ──
  IconData get addUser => _pick(
      Symbols.person_add_rounded,
      FPhosphorFillIcons.userPlus,
      FLucideIcons.userPlus,
      CupertinoIcons.person_badge_plus_fill,
      FluentIcons.person_add_24_filled
  );
  IconData get signOut => _pick(
      Symbols.logout_rounded,
      FPhosphorFillIcons.signOut,
      FLucideIcons.logOut,
      CupertinoIcons.square_arrow_right_fill,
      FluentIcons.sign_out_24_filled
  );
  // TODO(cleanup): syncPlay, appearance and server are unused; ask before deleting
  IconData get syncPlay => _pick(
      Symbols.group_rounded,
      FPhosphorFillIcons.usersThree,
      FLucideIcons.users,
      CupertinoIcons.person_2_fill,
      FluentIcons.people_24_filled
  );
  IconData get appearance => _pick(
      Symbols.palette_rounded,
      FPhosphorFillIcons.palette,
      FLucideIcons.palette,
      CupertinoIcons.paintbrush_fill,
      FluentIcons.color_24_filled)
  ;
  IconData get server => _pick(
      Symbols.dns_rounded,
      FPhosphorFillIcons.hardDrives,
      FLucideIcons.server,
      CupertinoIcons.desktopcomputer,
      FluentIcons.server_24_filled
  );

  // ── Genres ──
  /// Genre keyword → icon, for the current style. First match wins, so keep longer phrases first.
  List<(String, IconData)> get genreIcons => [
    for (final (name, material, phosphor, lucide, cupertino, fluent) in _genres)
      (name, _pick(material, phosphor, lucide, cupertino, fluent)),
  ];
}

/// Fixed sets, e.g. for previews in the icon-style picker.
const materialIconSet = AppIconSet._(IconStyle.materialSymbols);
const phosphorIconSet = AppIconSet._(IconStyle.phosphor);
const lucideIconSet = AppIconSet._(IconStyle.lucide);
const cupertinoIconSet = AppIconSet._(IconStyle.cupertino);
const fluentIconSet = AppIconSet._(IconStyle.fluent);

/// The fixed set for a style, e.g. `style.iconSet` in the icon-style picker.
extension AppIconSetOf on IconStyle {
  AppIconSet get iconSet => switch (this) {
    IconStyle.materialSymbols => materialIconSet,
    IconStyle.phosphor => phosphorIconSet,
    IconStyle.lucide => lucideIconSet,
    IconStyle.cupertino => cupertinoIconSet,
    IconStyle.fluent => fluentIconSet,
  };
}

/// The icons for the current style. Use these everywhere: `Icon(appIcons.play)`.
AppIconSet get appIcons => iconController.value.iconSet;

// ─── Genre icons: (keyword, Material Symbols, Phosphor Fill, Lucide, Cupertino, Fluent) ─────────────────

const _genres = <(String, IconData, IconData, IconData, IconData, IconData)>[
  ('science fiction', Symbols.rocket_launch_rounded, FPhosphorFillIcons.rocket, FLucideIcons.rocket, CupertinoIcons.rocket_fill, FluentIcons.rocket_24_filled),
  ('sci-fi', Symbols.rocket_launch_rounded, FPhosphorFillIcons.rocket, FLucideIcons.rocket, CupertinoIcons.rocket_fill, FluentIcons.rocket_24_filled),
  ('action', Symbols.bolt_rounded, FPhosphorFillIcons.lightning, FLucideIcons.zap, CupertinoIcons.bolt_fill, FluentIcons.flash_24_filled),
  ('adventure', Symbols.explore_rounded, FPhosphorFillIcons.compass, FLucideIcons.compass, CupertinoIcons.compass_fill, FluentIcons.compass_northwest_24_filled),
  ('animation', Symbols.brush_rounded, FPhosphorFillIcons.paintBrush, FLucideIcons.paintbrush, CupertinoIcons.paintbrush_fill, FluentIcons.paint_brush_24_filled),
  ('anime', Symbols.auto_awesome_rounded, FPhosphorFillIcons.sparkle, FLucideIcons.sparkles, CupertinoIcons.sparkles, FluentIcons.sparkle_24_filled),
  ('children', Symbols.child_care_rounded, FPhosphorFillIcons.baby, FLucideIcons.baby, CupertinoIcons.hare_fill, FluentIcons.teddy_24_filled),
  ('comedy', Symbols.sentiment_very_satisfied_rounded, FPhosphorFillIcons.smiley, FLucideIcons.smile, CupertinoIcons.smiley_fill, FluentIcons.emoji_laugh_24_filled),
  ('crime', Symbols.fingerprint_rounded, FPhosphorFillIcons.fingerprint, FLucideIcons.fingerprint, CupertinoIcons.scope, FluentIcons.fingerprint_24_filled),
  ('documentary', Symbols.videocam_rounded, FPhosphorFillIcons.videoCamera, FLucideIcons.video, CupertinoIcons.videocam_fill, FluentIcons.video_24_filled),
  ('drama', Symbols.theater_comedy_rounded, FPhosphorFillIcons.maskSad, FLucideIcons.drama, CupertinoIcons.drop_fill, FluentIcons.emoji_sad_24_filled),
  ('family', Symbols.family_restroom_rounded, FPhosphorFillIcons.users, FLucideIcons.users, CupertinoIcons.person_3_fill, FluentIcons.people_team_24_filled),
  ('kids', Symbols.child_care_rounded, FPhosphorFillIcons.baby, FLucideIcons.baby, CupertinoIcons.hare_fill, FluentIcons.teddy_24_filled),
  ('fantasy', Symbols.auto_fix_high_rounded, FPhosphorFillIcons.magicWand, FLucideIcons.wandSparkles, CupertinoIcons.wand_stars_inverse, FluentIcons.wand_24_filled),
  ('food', Symbols.restaurant_rounded, FPhosphorFillIcons.hamburger, FLucideIcons.utensils, CupertinoIcons.flame_fill, FluentIcons.food_24_filled),
  ('history', Symbols.history_edu_rounded, FPhosphorFillIcons.scroll, FLucideIcons.scroll, CupertinoIcons.book_circle_fill, FluentIcons.book_clock_24_filled),
  ('horror', Symbols.skull_rounded, FPhosphorFillIcons.skull, FLucideIcons.skull, CupertinoIcons.moon_stars_fill, FluentIcons.weather_moon_24_filled),
  ('mini', Symbols.ondemand_video_rounded, FPhosphorFillIcons.monitorPlay, FLucideIcons.monitorPlay, CupertinoIcons.play_rectangle_fill, FluentIcons.video_clip_24_filled),
  ('music', Symbols.music_note_rounded, FPhosphorFillIcons.musicNotes, FLucideIcons.music, CupertinoIcons.music_note, FluentIcons.music_note_2_24_filled),
  ('mystery', Symbols.search_rounded, FPhosphorFillIcons.magnifyingGlass, FLucideIcons.search, CupertinoIcons.search, FluentIcons.search_24_filled),
  ('romance', Symbols.favorite_rounded, FPhosphorFillIcons.heart, FLucideIcons.heart, CupertinoIcons.heart_fill, FluentIcons.heart_24_filled),
  ('suspense', Symbols.hourglass_bottom_rounded, FPhosphorFillIcons.hourglassMedium, FLucideIcons.hourglass, CupertinoIcons.hourglass_bottomhalf_fill, FluentIcons.hourglass_24_filled),
  ('talk', Symbols.mic_rounded, FPhosphorFillIcons.microphone, FLucideIcons.mic, CupertinoIcons.mic_fill, FluentIcons.mic_24_filled),
  ('thriller', Symbols.blood_pressure_rounded, FPhosphorFillIcons.knife, FLucideIcons.siren, CupertinoIcons.eye_fill, FluentIcons.eye_24_filled),
  ('tv', Symbols.tv_rounded, FPhosphorFillIcons.television, FLucideIcons.tv, CupertinoIcons.tv_fill, FluentIcons.tv_24_filled),
  ('war', Symbols.swords_rounded, FPhosphorFillIcons.sword, FLucideIcons.swords, CupertinoIcons.burst_fill, FluentIcons.shield_24_filled),
  ('western', Symbols.terrain_rounded, FPhosphorFillIcons.horse, FLucideIcons.mountain, CupertinoIcons.sun_haze_fill, FluentIcons.mountain_trail_24_filled),
  ('sport', Symbols.sports_football_rounded, FPhosphorFillIcons.football, FLucideIcons.trophy, CupertinoIcons.sportscourt_fill, FluentIcons.sport_american_football_24_filled),
  ('reality', Symbols.live_tv_rounded, FPhosphorFillIcons.television, FLucideIcons.tv, CupertinoIcons.tv_fill, FluentIcons.live_24_filled),
];

// ─── Saving the choice ───────────────────────────────────────────────────────

/// The chosen icon style, saved between launches.
class IconController extends ValueNotifier<IconStyle> {
  IconController._(super.value);

  static const _key = 'icon_style';

  static Future<IconController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = IconStyle.values.asNameMap()[prefs.getString(_key)];
    return IconController._(saved ?? IconStyle.materialSymbols);
  }

  Future<void> select(IconStyle style) async {
    value = style;
    _redrawEverything();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, style.name);
  }
}

/// Asks every widget in the app to rebuild once, keeping all their state
/// (scroll positions, loaded content, where you are). Used when the icon style changes,
/// since icons are read directly rather than through something widgets listen to.
void _redrawEverything() {
  void rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(rebuild);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
}

late final IconController iconController;