# Playback

The player, direct play vs. transcode, the playback reporter, subtitles, and SyncPlay.

All of this lives in `lib/screens/player.dart` and its parts — `player_controls.dart` (the
on-screen controls, seek bar, clock), `player_segments.dart` (trickplay, skip segments, the
rating-badge intro, Up Next) and `player_tracks.dart` (audio/subtitle track choices,
transcoding). They share `player.dart`'s private names — see
[architecture.md](architecture.md)'s note on `part` files.

## Opening the player

`PlayerScreen(itemId, queue, fromGroup)` is pushed at `/play/:id`. `queue` carries the rest of
a collection or shuffle when playing through a list (set by `playQueue` in
`widgets/detail_page.dart`); `fromGroup` is true when SyncPlay opened the player, not you.
`_start()` loads the item, works out where to resume from (`_resumePosition`, governed by the
`ResumeMode` setting), and either opens it directly or hands it to the cast controller if a
Chromecast is already connected.

## Direct play vs. transcode

`_planTranscode(item)` in `player_tracks.dart` decides: always-direct and always-transcode are
explicit `StreamMode` settings; `auto` compares the file's bitrate against
`playbackSettings.currentMaxBitrate()` (which itself checks Wi-Fi vs. mobile data via
`connectivity_plus`) and only transcodes if the file is over the limit. A transcoded stream
carries exactly one audio track and no soft subtitles — Jellyfin's HLS master playlist
(`_Transcode.build`) is asked for one specific audio index and, if needed, one subtitle index
burned into the picture, chosen the same way direct play chooses its default tracks
(`_pickAudio`/`_pickSubtitle`, from the account's language and subtitle-mode preferences —
see [adding-a-setting.md](adding-a-setting.md) for where those are read). Switching tracks
mid-transcode (`_reopenTranscode`) stops and reopens the stream at the same position; a plain
audio-track switch during direct play doesn't need that.

## Reporting progress

`PlaybackReporter` (`utils/playback_reporter.dart`) is the one thing that tells Jellyfin
what's playing, so Continue Watching, Next Up and progress stay correct in every Jellyfin
client, not just this one:

```dart
PlaybackReporter({required this.client, required this.itemId, required this.player, this.mediaSourceId, this.playSessionId, this.transcoding = false, this.audioStreamIndex})
```

`start()` posts `/Sessions/Playing` once, then `/Sessions/Playing/Progress` every 10 seconds
and immediately on every play/pause; `stop()` (called from `_finishItem` when leaving the
player or switching episodes) reads the player's position *before* disposing it and posts
`/Sessions/Playing/Stopped`. Not used while casting — `CastController` reports instead, so
the two don't fight over who's authoritative.

## Subtitles

Rendering is entirely custom — `media_kit`'s own subtitle view is turned off
(`subtitleViewConfiguration: SubtitleViewConfiguration(visible: false)`) and `SubtitleText`
(`utils/playback_settings.dart`) draws the current line itself, styled by
`playbackSettings.subtitleStyle()`: font, size, color and background (shadow, outline or a
dark box) all come from Settings → Playback. The outline style is drawn as two overlaid
`Text`s (a thick stroke underneath, the filled text on top) since a single `TextStyle` can't
have both a fill and a stroke. Subtitles slide up above the controls while they're visible
(`liftSubtitles`), by the same amount regardless of screen size (`_subtitlePadding` in
`player.dart`, as a share of screen height, not a fixed pixel count).

Choosing *which* track to start on follows Jellyfin's own modes (Default/Smart/OnlyForced/
Always/None) — see `_pickSubtitle` in `player_tracks.dart` for exactly how each mode decides,
and `_fetchTrackPrefs` for where the account's saved language and mode come from.

## Skip segments and trickplay

`_loadSegments` (`player_segments.dart`) tries Jellyfin's Media Segments API first (needs a
plugin like the intro-detection one on the server), then falls back to matching chapter names
("Intro", "Previously on", ...) via `_kindFromChapterName`. `_plausibleSegments` throws out
anything that can't be right for the file — nothing skippable should cover more than half the
runtime, and credits specifically should start in the last 30%. `playbackSettings.skip[kind]`
decides whether a matched segment shows a button, skips automatically, or is ignored.

Trickplay (`_Trickplay`, same file) parses the sheet-of-thumbnails info Jellyfin attaches to
an item and works out which sheet and which tile within it corresponds to a given position,
for the scrubbing preview (`_ScrubPreview`, shown from `_SeekBar` in `player_controls.dart`).
Turned off entirely by the "Scrubbing previews" setting.

## Up Next

`_fetchNextIn`/`_fetchNextEpisode` (`player_segments.dart`) find the next item — the next id
in `queue` if one was given, otherwise Jellyfin's own "next episode" logic. The card
(`_UpNextCard`) appears near the end of the episode (at the credits segment if one was found,
or a fixed time before the end otherwise) and counts down unless `stillWatchingAfter` has
been hit, in which case it asks "Are you still watching?" instead of autoplaying.

## SyncPlay (watch together)

`SyncPlayController` (`utils/sync_play_controller.dart`) is the controller — never call it
"Watch Together" in code or comments, only in the UI isn't even used; the class, variable and
everything else is `SyncPlay`. The player hooks into it with `syncPlay.attach(onSwitch)` in
`initState` (so the group can switch what's playing in place rather than opening a second
player) and listens to `syncPlay.commands` for play/pause/seek instructions timed to a
specific moment, not "do it now" — the clock offset between this device and the server is
measured in `_syncClock` (an NTP-style best-of-three round trip) so everyone's "do it at
12:00:03.400" lands at the same instant. While `_inGroup` is true, the transport buttons ask
the group (`syncPlay.requestPause()`, etc.) instead of touching the player directly, and the
player reports buffering/ready so the group waits for slow members (`_reportBuffering`).

Group management (create/join/leave, the groups list with what each is watching) is the
SyncPlay tab in Settings — see `screens/sync_play_settings.dart`.
