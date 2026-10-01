import 'package:forui_phosphor/forui_phosphor.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which family of icons the app uses.
enum IconStyle {
  materialSymbols('Material Symbols'),
  phosphor('Phosphor');

  const IconStyle(this.label);
  final String label;
}

/// Every icon in the app, named by what it means. Screens use these names (via [appIcons]),
/// never an icon pack directly, so the whole app can switch styles at once.
class AppIconSet {
  const AppIconSet({
    required this.home,
    required this.search,
    required this.settings,
    required this.profile,
    required this.genres,
    required this.back,
    required this.close,
    required this.play,
    required this.pause,
    required this.previous,
    required this.next,
    required this.audio,
    required this.subtitles,
    required this.fill,
    required this.fit,
    required this.favorite,
    required this.star,
    required this.watched,
    required this.edit,
    required this.done,
    required this.moveUp,
    required this.moveDown,
    required this.remove,
    required this.reset,
    required this.check,
    required this.expand,
    required this.collapse,
    required this.chooser,
    required this.error,
    required this.genreIcons,
    required this.info,
    required this.featured,
    required this.continueWatching,
    required this.shows,
    required this.movies,
    required this.recentlyAdded,
    required this.suggested,
    required this.becauseYouWatched,
    required this.collection,
    required this.music,
    required this.playlists,
    required this.musicVideos,
    required this.homeVideos,
    required this.photos,
    required this.books,
    required this.liveTv,
    required this.folder,
    required this.addUser,
    required this.signOut,
  });

  // ── Navigation ──
  final IconData home;
  final IconData search;
  final IconData settings;
  final IconData profile;
  final IconData genres;
  final IconData back;
  final IconData close;

  // ── Media ──
  final IconData play;
  final IconData pause;
  final IconData previous;
  final IconData next;
  final IconData audio;
  final IconData subtitles;
  final IconData fill; // zoom in to fill the screen
  final IconData fit; // back to the whole picture

  // ── Items ──
  final IconData favorite;
  final IconData star;
  final IconData watched;

  // ── Home editing ──
  final IconData edit;
  final IconData done;
  final IconData moveUp;
  final IconData moveDown;
  final IconData remove;
  final IconData reset;

  // ── General ──
  final IconData check;
  final IconData expand;
  final IconData collapse;
  final IconData chooser; // the ⇅ on choice fields
  final IconData error;

  // ── Genres ──
  final List<(String, IconData)> genreIcons;

  // ── Home sections ──
  final IconData info; // "More info"
  final IconData featured;
  final IconData continueWatching;
  final IconData shows; // Next Up, Recently Added Shows
  final IconData movies;
  final IconData recentlyAdded;
  final IconData suggested;
  final IconData becauseYouWatched;
  final IconData collection;

  // ── Library types (movies, shows and collection are above) ──
  final IconData music;
  final IconData playlists;
  final IconData musicVideos;
  final IconData homeVideos;
  final IconData photos;
  final IconData books;
  final IconData liveTv;
  final IconData folder; // any other kind of library

  // ── Account ──
  final IconData addUser;
  final IconData signOut;
}

/// Outlined, slightly technical: Phosphor's regular weight.
const phosphorIconSet = AppIconSet(
  home: FPhosphorIcons.house,
  search: FPhosphorIcons.magnifyingGlass,
  settings: FPhosphorIcons.gear,
  profile: FPhosphorIcons.user,
  genres: FPhosphorIcons.tag,
  back: FPhosphorIcons.caretLeft,
  close: FPhosphorIcons.x,
  play: FPhosphorIcons.playCircle,
  pause: FPhosphorIcons.pause,
  previous: FPhosphorIcons.skipBack,
  next: FPhosphorIcons.skipForward,
  audio: FPhosphorIcons.waveform,
  subtitles: FPhosphorIcons.subtitles,
  fill: FPhosphorIcons.cornersOut,
  fit: FPhosphorIcons.cornersIn,
  favorite: FPhosphorIcons.heart,
  star: FPhosphorIcons.star,
  watched: FPhosphorIcons.check,
  edit: FPhosphorIcons.pencilSimple,
  done: FPhosphorIcons.check,
  moveUp: FPhosphorIcons.arrowUp,
  moveDown: FPhosphorIcons.arrowDown,
  remove: FPhosphorIcons.trash,
  reset: FPhosphorIcons.arrowCounterClockwise,
  check: FPhosphorIcons.check,
  expand: FPhosphorIcons.caretDown,
  collapse: FPhosphorIcons.caretUp,
  chooser: FPhosphorIcons.caretUpDown,
  error: FPhosphorIcons.warningCircle,
  genreIcons: _phosphorGenres,
  info: FPhosphorIcons.info,
  featured: FPhosphorIcons.slideshow,
  continueWatching: FPhosphorIcons.playCircle,
  shows: FPhosphorIcons.television,
  movies: FPhosphorIcons.filmSlate,
  recentlyAdded: FPhosphorIcons.sparkle,
  suggested: FPhosphorIcons.lightbulb,
  becauseYouWatched: FPhosphorIcons.clockCounterClockwise,
  collection: FPhosphorIcons.stack,
  music: FPhosphorIcons.musicNotes,
  playlists: FPhosphorIcons.queue,
  musicVideos: FPhosphorIcons.monitorPlay,
  homeVideos: FPhosphorIcons.filmStrip,
  photos: FPhosphorIcons.images,
  books: FPhosphorIcons.books,
  liveTv: FPhosphorIcons.broadcast,
  folder: FPhosphorIcons.folder,
  addUser: FPhosphorIcons.userPlus,
  signOut: FPhosphorIcons.signOut,
);

/// Solid and familiar: Material Symbols, rounded. Drawn filled app-wide (see main.dart);
/// add `fill: 0` to an Icon to show one as an outline.
const materialIconSet = AppIconSet(
  home: Symbols.home_rounded,
  search: Symbols.search_rounded,
  settings: Symbols.settings_rounded,
  profile: Symbols.person_rounded,
  genres: Symbols.label_rounded,
  back: Symbols.arrow_back_ios_new_rounded,
  close: Symbols.close_rounded,
  play: Symbols.play_circle_rounded,
  pause: Symbols.pause_rounded,
  previous: Symbols.skip_previous_rounded,
  next: Symbols.skip_next_rounded,
  audio: Symbols.graphic_eq_rounded,
  subtitles: Symbols.subtitles_rounded,
  fill: Symbols.zoom_out_map_rounded,
  fit: Symbols.zoom_in_map_rounded,
  favorite: Symbols.favorite_rounded,
  star: Symbols.star_rounded,
  watched: Symbols.check_rounded,
  edit: Symbols.edit_rounded,
  done: Symbols.check_rounded,
  moveUp: Symbols.arrow_upward_rounded,
  moveDown: Symbols.arrow_downward_rounded,
  remove: Symbols.delete_rounded,
  reset: Symbols.restart_alt_rounded,
  check: Symbols.check_rounded,
  expand: Symbols.expand_more_rounded,
  collapse: Symbols.expand_less_rounded,
  chooser: Symbols.unfold_more_rounded,
  error: Symbols.error_rounded,
  genreIcons: _materialGenres,
  info: Symbols.info_rounded,
  featured: Symbols.slideshow_rounded,
  continueWatching: Symbols.play_circle_rounded,
  shows: Symbols.tv_rounded,
  movies: Symbols.movie_rounded,
  recentlyAdded: Symbols.auto_awesome_rounded,
  suggested: Symbols.lightbulb_rounded,
  becauseYouWatched: Symbols.history_rounded,
  collection: Symbols.collections_bookmark_rounded,
  music: Symbols.music_note_rounded,
  playlists: Symbols.queue_music_rounded,
  musicVideos: Symbols.music_video_rounded,
  homeVideos: Symbols.video_library_rounded,
  photos: Symbols.photo_library_rounded,
  books: Symbols.menu_book_rounded,
  liveTv: Symbols.live_tv_rounded,
  folder: Symbols.folder_rounded,
  addUser: Symbols.person_add_rounded,
  signOut: Symbols.logout_rounded,
);

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, style.name);
  }
}

late final IconController iconController;

/// The icons for the current style. Use these everywhere: `Icon(appIcons.play)`.
AppIconSet get appIcons => switch (iconController.value) {
  IconStyle.phosphor => phosphorIconSet,
  IconStyle.materialSymbols => materialIconSet,
};

// ─── Genre icons ─────────────────────────────────────────────────────────────

const _phosphorGenres = <(String, IconData)>[
  ('science fiction', FPhosphorIcons.rocket),
  ('sci-fi', FPhosphorIcons.rocket),
  ('action', FPhosphorIcons.lightning),
  ('adventure', FPhosphorIcons.compass),
  ('animation', FPhosphorIcons.paintBrush),
  ('anime', FPhosphorIcons.sparkle),
  ('children', FPhosphorIcons.baby),
  ('comedy', FPhosphorIcons.smiley),
  ('crime', FPhosphorIcons.fingerprint),
  ('documentary', FPhosphorIcons.videoCamera),
  ('drama', FPhosphorIcons.maskSad),
  ('family', FPhosphorIcons.users),
  ('kids', FPhosphorIcons.baby),
  ('fantasy', FPhosphorIcons.magicWand),
  ('food', FPhosphorIcons.hamburger),
  ('history', FPhosphorIcons.scroll),
  ('horror', FPhosphorIcons.skull),
  ('mini', FPhosphorIcons.monitorPlay),
  ('music', FPhosphorIcons.musicNotes),
  ('mystery', FPhosphorIcons.magnifyingGlass),
  ('romance', FPhosphorIcons.heart),
  ('suspense', FPhosphorIcons.hourglassMedium),
  ('talk', FPhosphorIcons.microphone),
  ('thriller', FPhosphorIcons.knife),
  ('tv', FPhosphorIcons.television),
  ('war', FPhosphorIcons.sword),
  ('western', FPhosphorIcons.horse),
  ('sport', FPhosphorIcons.football),
  ('reality', FPhosphorIcons.television),
];

/// Material Symbols (rounded), drawn filled app-wide.
const _materialGenres = <(String, IconData)>[
  ('science fiction', Symbols.rocket_launch_rounded),
  ('sci-fi', Symbols.rocket_launch_rounded),
  ('action', Symbols.bolt_rounded),
  ('adventure', Symbols.explore_rounded),
  ('animation', Symbols.brush_rounded),
  ('anime', Symbols.auto_awesome_rounded),
  ('children', Symbols.child_care_rounded),
  ('comedy', Symbols.sentiment_very_satisfied_rounded),
  ('crime', Symbols.fingerprint_rounded),
  ('documentary', Symbols.videocam_rounded),
  ('drama', Symbols.theater_comedy_rounded),
  ('family', Symbols.family_restroom_rounded),
  ('kids', Symbols.child_care_rounded),
  ('fantasy', Symbols.auto_fix_high_rounded),
  ('food', Symbols.restaurant_rounded),
  ('history', Symbols.history_edu_rounded),
  ('horror', Symbols.skull_rounded),
  ('mini', Symbols.ondemand_video_rounded),
  ('music', Symbols.music_note_rounded),
  ('mystery', Symbols.search_rounded),
  ('romance', Symbols.favorite_rounded),
  ('suspense', Symbols.hourglass_bottom_rounded),
  ('talk', Symbols.mic_rounded),
  ('thriller', Symbols.blood_pressure_rounded),
  ('tv', Symbols.tv_rounded),
  ('war', Symbols.swords_rounded),
  ('western', Symbols.terrain_rounded),
  ('sport', Symbols.sports_football_rounded),
  ('reality', Symbols.live_tv_rounded),
];