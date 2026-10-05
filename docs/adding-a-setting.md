# Adding a setting

Where a setting lives depends on what it's for, and that decides which store it goes in.

| Kind | Store | Saved | Tab |
| --- | --- | --- | --- |
| Playback (quality, subtitles, skip, ...) | `utils/playback_settings.dart` | This device (SharedPreferences) | Playback |
| Appearance (theme, fonts, icon style) | `utils/theme_controller.dart`, `font_controller.dart`, `theme/app_icons.dart` | This device | Appearance |
| Account (language, subtitle mode, Quick Connect) | `utils/account_settings.dart` | The Jellyfin server, on the account | Account |

Playback and Appearance settings are per-device, so another Jellyfin app (or this app on
another device) never sees them. Account settings are saved to the server through Jellyfin's
own API, so they follow you — the web app and other clients see the same values.

## Playback or Appearance (device-local)

1. **Add the field** to `PlaybackSettings` (or wherever it belongs) with a sensible default:

   ```dart
   // utils/playback_settings.dart
   class PlaybackSettings extends ChangeNotifier {
     // ...
     bool showEpisodeNumbers = true;
   ```

2. **Read and write it** in `_write()`/`_read()` so it survives a restart:

   ```dart
   Map<String, dynamic> _write() => {
     // ...
     'showEpisodeNumbers': showEpisodeNumbers,
   };

   void _read(Map<String, dynamic> j) {
     // ...
     showEpisodeNumbers = flag('showEpisodeNumbers', showEpisodeNumbers);
   }
   ```

3. **Add the control** in `screens/settings.dart`'s matching tab (`_PlaybackCard`, say). An
   on/off setting is `SwitchSetting`:

   ```dart
   SwitchSetting(
     label: 'Show episode numbers',
     description: 'S1:E3 before the episode name, in Up Next and Continue Watching.',
     value: s.showEpisodeNumbers,
     onChange: (v) => update((s) => s.showEpisodeNumbers = v),
   )
   ```

   A setting with a fixed list of choices is `_PickerSetting<T>` (private to `settings.dart`
   — it already picks a dropdown on phones and a remote-friendly full-screen list everywhere
   else):

   ```dart
   _PickerSetting<SubtitleSize>(
     label: 'Size',
     value: s.subtitleSize,
     options: SubtitleSize.values,
     format: (v) => v.label,
     onChange: (v) => update((s) => s.subtitleSize = v),
   )
   ```

   Both call `update()`, a local helper in that tab's `build` that wraps
   `playbackSettings.change(edit)` — `change()` applies your edit, calls `notifyListeners()`
   and saves, in one step. Appearance settings instead call their own controller's setter
   directly (`themeController.select(...)`, `fontController.setDisplay(...)`), since each one
   persists itself immediately rather than going through a shared `change()`.

4. **Use the setting** wherever it matters — read `playbackSettings.showEpisodeNumbers`
   directly; it's a global, no `Provider` lookup needed.

## Account setting (server-saved)

Server-saved settings go through `AccountSettings` (`utils/account_settings.dart`), one
instance per Settings-page visit, created and `load()`ed by `_AccountCardState`. Reading is a
getter over the loaded configuration; writing goes through `_save`, which updates the local
copy immediately, then persists it (and reverts on failure):

```dart
// Reading
bool get hidePlayedInLatest => _config['HidePlayedInLatest'] as bool? ?? false;

// Writing
Future<void> setHidePlayedInLatest(bool hide) => _save('HidePlayedInLatest', hide);
```

The key (`'HidePlayedInLatest'`) is whatever Jellyfin's own `UserConfiguration` calls it —
check the field name in Jellyfin's API docs or an existing client, since this isn't something
Chameleon invents. Wire the control into `_AccountCard` in `screens/settings.dart` the same
way as a device-local one, calling `s.setHidePlayedInLatest(v)` instead of `update(...)`.

## Adding a whole new tab

Add an entry to `_tabs` in `screens/settings.dart`:

```dart
final _tabs = <_SettingsTab>[
  (label: 'Appearance', build: () => const _AppearanceCard()),
  // ...
  (label: 'Notifications', build: () => const _NotificationsCard()),
];
```

`settingsTabLabels` (a getter over `_tabs`) feeds both the phone's pill row and the sidebar's
Settings section automatically — nothing else to wire up. If the new tab's widgets are
sizeable, consider giving them their own `part` file the way `sync_play_settings.dart` holds
the SyncPlay tab's widgets (see [architecture.md](architecture.md)'s note on `part` files).
