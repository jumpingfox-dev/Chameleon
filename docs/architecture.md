# Architecture

How the app is laid out, how routing and the shell work, and where state lives.

## Folders

```
lib/
  main.dart            entry point: loads the controllers, then the top-level MaterialApp.router
  app/                 the router, the shell around every page (sidebar / bottom bar), UI scaling
  core/                no UI, shared by every feature
    jellyfin/          the session and server calls, library cache, playback reporting
    cast/              Chromecast and SyncPlay
    focus/             D-pad / remote navigation (see remote-navigation.md)
    platform/          TV and phone detection, orientation, insets
    storage/           the database (Drift): settings, accounts, saved pages; appCache
    format/            durations, sizes, item labels
  features/            one folder per part of the app, with its screens, widgets and settings
    auth/              sign-in, "Who's watching?", Quick Connect
    home/              Home and its modules
    library/           a library, a genre, all genres, favorites, poster cards
    detail/            movie / series / season / episode / collection / person pages
    player/            the player and its controls, tracks, segments, playback settings
    settings/          Settings and its pages
    search/            Search
  theme/               forui theme, app icons, theme / font / icon controllers, styles
  widgets/             small pieces used across features (logo, nav button, hover lift)
```

A screen is anything the router routes to directly. Everything else — a poster card, the
detail page's info cards, the sidebar — is a widget, even if it's only used from one screen.
Both live in their feature's folder; only widgets used across features go in `widgets/`.

## Routing

`lib/app/router.dart` builds one `GoRouter`, `appRouter`. `/login`, `/profiles` and `/play/:id` are plain routes
outside the shell (playback and signing in take over the whole screen). Everything else sits
inside a `StatefulShellRoute` with four branches — Home, Search, Settings, Profile — defined
by the `destinations` list in `lib/app/app_shell.dart`:

```dart
final destinations = <AppDestination>[
  (label: 'Home', icon: (i) => i.home, path: '/home', screen: (_) => const HomeScreen(), routes: [...]),
  (label: 'Search', ...),
  (label: 'Settings', ...),
  (label: 'Profile', ...),
];
```

Each branch's `routes` are sub-pages that keep that tab selected — a library, a genre, a
movie page all live under the Home branch's `routes`, for instance. `StatefulShellRoute`
keeps each branch's navigation stack alive in an `IndexedStack` when you switch tabs, so
going back to Home lands where you left it.

`AppShell` (same file) wraps the branches and decides, from `isPhoneLayout`, whether to show
the bottom nav bar (phones) or the sidebar (everything else — see
[remote-navigation.md](remote-navigation.md)). Settings reads its tab from `?tab=`
(`SettingsScreen(initialTab: ...)`); Search reads its query from `?q=`.

`redirect` in `app/router.dart` is the only gate: it sends you to `/login` or `/profiles` when
nothing is signed in, and to `/home` once something is.

## Where state lives

Nothing here uses a state-management package. Long-lived state is a handful of global
singletons (in `core/`, `theme/` and the features that own them), each a `ChangeNotifier` or `ValueNotifier` instantiated once at
the bottom of its own file and read anywhere with `jellyfin.foo`, no `Provider`/`context.watch`
needed. Widgets that need to rebuild on a change wrap themselves in a `ListenableBuilder` (or
`ValueListenableBuilder`) around that global.

| Global | File | What it holds |
| --- | --- | --- |
| `jellyfin` | `core/jellyfin/jellyfin_controller.dart` | The signed-in session, saved accounts, libraries, genres. The one controller nearly everything else needs. |
| `syncPlay` | `core/cast/sync_play_controller.dart` | SyncPlay (watch-together) group state and the server's play/pause/seek commands. |
| `playbackSettings` | `features/player/playback_settings.dart` | Playback preferences saved on this device (skip modes, quality, subtitle style, ...). |
| `homeLayout` | `features/home/home_layout.dart` | The home screen's sections, in order. |
| `themeController` | `theme/theme_controller.dart` | The chosen theme preset, or the custom one. |
| `fontController` | `theme/font_controller.dart` | The chosen display and body fonts. |
| `iconController` | `theme/app_icons.dart` | The chosen icon style (Material Symbols, Phosphor, ...). |
| `castController` | `core/cast/cast_controller.dart` | Chromecast discovery and the active cast session. |

Smaller, page-local state (a library's loaded items, a search's results) lives in that
screen's own `State`, often backed by `appCache` (below) so switching tabs and back doesn't
re-fetch everything.

## Storage

Everything kept on the device is in one SQLite database, through
[Drift](https://pub.dev/packages/drift) (`core/storage/database.dart`, with the generated
`database.g.dart` next to it; regenerate with `dart run build_runner build` after changing a
table). `storage` (`core/storage/storage.dart`) is the only thing that talks to it:

| Table | Holds | Read |
| --- | --- | --- |
| `settings` | Key/value settings: theme, fonts, icon style, home layout, playback settings, the device id. JSON where structured. | Once, at startup, into memory: `storage.getString(...)` needs no `await`. Writes go straight through. |
| `accounts` | Every account signed in on this device, in order, with its token. | When the session starts or changes. |
| `cache_entries` | Pages loaded from the server (Home sections, favorites, detail pages, seasons, libraries), as JSON, per account. | When that account's session starts (`appCache.open`). |

`appCache` (`core/storage/app_cache.dart`) is the in-memory cache pages read and write. An
entry put with a `toJson` is also saved, under the signed-in account, so it shows straight
away next time (counting as stale, so the page refreshes it too); reading it back takes the
matching `fromJson`. Items are saved as the server's own JSON (`itemsToJson` /
`itemsFromJson`). Changing user only empties memory, so switching back is instant; removing
an account deletes its saved pages. Pages unused for 30 days are deleted at startup, and
Settings → About shows the total and can clear it.

The first run after updating from a version that used shared_preferences copies everything
across (`_importSharedPreferences`), once. The old values are left in place, which is the
only reason `shared_preferences` is still a dependency.

## Startup

`main.dart` opens storage, then loads every controller before `runApp`:

```dart
storage = await Storage.open();
themeController = await ThemeController.load();
fontController = await FontController.load();
iconController = await IconController.load();
playbackSettings = await PlaybackSettings.load();
homeLayout = await HomeLayoutController.load();
jellyfin = JellyfinController();
await jellyfin.load();
```

A few one-off `ValueNotifier`s don't need a whole controller: `homeEditing` (home-screen edit
mode), `homeVisible` (bumped when Home becomes visible again, so stale sections refresh),
`favoritesChanged` (bumped when a favorite toggles, so pages listing favorites refresh).

## Theme

`lib/theme/theme.dart` is generated by the forui CLI and stitches together `colors.dart`,
`typography.dart`, `style.dart`, `icons.dart` (all `part of 'theme.dart'`) plus the
hand-edited styles under `theme/styles/`. `buildTheme()` is called once per `Application`
rebuild, combining the current `ThemePreset`'s colors with the chosen fonts. See
[theming.md](theming.md) for how presets, the custom editor and icon styles fit together.

## Splitting a big file with `part`

Three files are split into `part`s because the pieces share private (`_`-prefixed) helpers
that would otherwise need to go public: `app_shell.dart`/`app_sidebar.dart`,
`detail_page.dart`/`detail_blocks.dart`/`detail_cards.dart`, and `player.dart`/
`player_controls.dart`/`player_segments.dart`/`player_tracks.dart`. A `part` file starts with
`part of '<main file>.dart';` and otherwise reads like a normal file — it shares the main
file's imports, so don't re-import things already imported there.
