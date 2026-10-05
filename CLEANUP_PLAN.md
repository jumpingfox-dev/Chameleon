# Cleanup plan

Survey of `lib/` (56 files, 19,021 lines including the 70 `TODO(cleanup)` markers).
`flutter analyze` at the start: **5 issues, all `info`** — two `depend_on_referenced_packages`
for `cupertino_ui` in the generated styles, two `unintended_html_in_doc_comment` in
`library_cache.dart`, and one `use_build_context_synchronously` in `app_shell.dart`.

Line numbers below are the ones in this branch, i.e. with the TODO markers already in place.

---

## 1. Bugs found

### B1 — Focus lost when entering the sidebar

`lib/widgets/app_shell.dart:251` (`_enterSidebar`), `:276` (`_focusNewPage`), `:147`/`:736`
(`_closings` and the re-keying), `:297` (`_rememberedIn`).

**What goes wrong for the user.** On the TV, ← at the left edge of a page either does nothing
at all, or it opens the sidebar but nothing in it looks selected, or it lands on the logo
instead of the page you're on. Pressing → gets you back into the page, so it looks
intermittent rather than broken.

**Diagnosis.** Three separate causes, all real; the first is the main one.

**(a) A folded section's pages cannot take focus, and `requestFocus()` fails silently.**

`_enterSidebar` focuses the *section* (`Settings`, `Libraries`, `Genres`), waits 250 ms, and
then focuses the *page* inside it (`Settings/Appearance`, `Libraries/<id>`). It never unfolds
the section. Whether the section happens to be unfolded is decided entirely by forui:
`FSidebarItem` reads `initiallyExpanded` **once**, in `initState`
(`forui-0.27.3/lib/src/widgets/sidebar/sidebar_item.dart:129`), and from then on only its own
`_toggle()` (a press) changes it. The shell's only lever is the `ValueKey((label, closings))`
at `app_shell.dart:736`, which rebuilds the item from scratch each time the sidebar *closes* —
so the section is unfolded only if you happened to be on one of its pages at that moment.

When the section is folded, forui renders its children inside
`FCollapsible(value: 0)`, and `FCollapsible` wraps them in
`ExcludeFocus(excluding: value == 0)` (`forui-0.27.3/lib/src/foundation/collapsible.dart:36`).
`ExcludeFocus` sets `descendantsAreFocusable: false`, and Flutter's
`FocusNode.canRequestFocus` ANDs in every ancestor's flag:

```dart
// flutter/lib/src/widgets/focus_manager.dart:544
bool get canRequestFocus => _canRequestFocus && ancestors.every(_allowDescendantsToBeFocused);
```

so every page node in a folded section reports `canRequestFocus == false`, and
`_doRequestFocus` returns without doing anything and without telling anyone:

```dart
// flutter/lib/src/widgets/focus_manager.dart:1177
void _doRequestFocus({required bool findFirstFocus}) {
  if (!canRequestFocus) { return; }   // ← silent
```

`_enterSidebar`'s guards don't catch it: the widget *is* mounted, so `pageContext` is non-null
and the early `return` never fires. Focus simply stays on the section row — and because
`_SidebarSection` passes `selected: active && !open`, nothing in the open sidebar is
highlighted, so it reads as "focus went nowhere".

The same flag explains **landing on the logo**. `_rememberedIn` (`:297`) rejects a node whose
`canRequestFocus` is false, and `FocusScopeNode._doRequestFocus` prunes such nodes from
`_focusedChildren` outright (`focus_manager.dart:1506`). So once the remembered sidebar entry
is inside a folded section, the fallback `firstFocusable(_navScope)` runs, and the first
focusable thing in the sidebar is the logo in `FSidebar`'s header.

Reproduce: Home → sidebar → Libraries → Movies; open a poster, then go back to the library
(the sidebar closed while you were on `/home/movie/<id>`, so the Libraries section was rebuilt
with `initiallyExpanded: false`); press ←. Focus lands on the Libraries row and goes no
further.

**(b) `_navScope.unfocus()` parks focus where ← can't be heard.** `app_shell.dart:289` closes
the sidebar while a page loads. `FocusScopeNode.unfocus()` moves primary focus to the
*enclosing* scope — the shell route's scope, which is an **ancestor** of `_pageScope`, not a
descendant. Flutter dispatches keys from the focused node upwards:

```dart
// flutter/lib/src/widgets/focus_manager.dart:2277
for (final node in <FocusNode>[FocusManager.instance.primaryFocus!,
                               ...FocusManager.instance.primaryFocus!.ancestors]) {
```

`_pageScope` is below that node, so its `onKeyEvent` (`_onPageKey`) is never called and ←
reaches nothing. It normally recovers on the next retry, but if `firstFocusable` finds nothing
within 40 × 100 ms — a library page still loading over a slow connection — focus stays
stranded and the whole D-pad goes dead.

**(c) The 250 ms is a guess.** The sidebar widens over 180 ms (`AnimatedContainer`,
`:508`), the section's pages only exist once it is fully open (`roomy`, `:515`), and forui's
fold-out takes another 200 ms. 250 ms happens to clear the first of those on a desktop and
does not reliably clear all three on a TV.

**Proposed fix.** Move the folded state out of forui and into `_AppShellState`:

- `final _unfolded = <String>{}` in the shell, passed down to `_SidebarSection` as
  `expanded`, with `onPress` toggling the shell's set. Keying `_SidebarSection` on
  `(label, expanded)` makes `initiallyExpanded` honoured every time it changes.
- Clearing `_unfolded` when the sidebar closes gives exactly today's "fold back up on close"
  behaviour, so `_closings`, `_wasOpen` and the `ValueKey((label, closings))` hack all go
  (that also removes the state mutation inside a builder at `:428`).
- `_enterSidebar` unfolds the right section itself, then focuses the page entry by **polling
  `node.canRequestFocus`** (a few frames, ~20 × 50 ms) instead of waiting a fixed 250 ms —
  so it waits for the real condition and gives up honestly if it never holds.
- `_focusNewPage`'s `_navScope.unfocus()` becomes `_pageScope.requestFocus()`: it still takes
  focus out of the sidebar (so the sidebar closes) but leaves primary focus at the page scope,
  where `_onPageKey` still runs.

Fallbacks that become unnecessary and get removed: the `attempt >= 20 ? firstFocusable(...)`
widening at `:282`, and `_enterSidebar`'s "first sidebar item" fallback (it was only ever
reached because of the `canRequestFocus` problem). `_isUsable` is already gone from this
version of the file; `firstFocusable`'s `_isLaidOut` check stays — it guards a real
"RenderBox was not laid out" case.

This also clears the one `use_build_context_synchronously` info at `app_shell.dart:269`.

**Needs a device.** I can't drive the remote, so this is the one item I can't verify myself.
Test list in §6.

### B2 — ← from the Profile tab lands on the logo

`lib/widgets/app_shell.dart:160` (`_here`). `/profile` has no case, so it falls through to
`('Home', null)`. The Profile branch shows `SettingsScreen(initialTab: 'Account')`, so ←
should land on Settings › Account. Only reachable on a wide screen by resizing a window while
on the Profile tab (phones don't use the sidebar), so the impact is small — but it is one line.
**Fix:** add `if (loc == '/profile') return ('Settings', 'Settings/Account');`.

### B3 — "Who's watching?" has a doubled gap under the logo

`lib/widgets/profile_picker.dart:47`. Two consecutive `SizedBox(height: 32)` give a 64 px gap.
Visibly a paste slip. **Fix:** delete one. (This changes layout, so it's listed as a fix
rather than done silently.)

### B4 — `PersonPhoto` can throw on an empty name

`lib/widgets/person_tile.dart:64`:

```dart
person.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join()
```

`trim()` runs before `split`, so leading and trailing spaces are fine. An empty or
all-whitespace name is not: `''.split(RegExp(r'\s+'))` is `['']`, and `''[0]` throws
`RangeError`, taking the person tile down with it. Unlikely from a real Jellyfin server, so
this is a latent crash rather than one you'll have hit. Every other initials routine in the
app guards with `.where((w) => w.isNotEmpty)`; this one doesn't. **Fix:** fold all four into one shared helper
(§3, D8), which has the guard.

### B5 — `search.dart` writes its results twice and loses the people

`lib/screens/search.dart:116`. `_search` sets `_results`, `_people` and `_error`, then repeats
the staleness check and calls `setState` again with only `_results` and `_error`. Harmless
today (the second write sets the same values), but the second block silently omits `_people`,
so any future edit to the first block would be quietly undone. **Fix:** delete the second
check and `setState`.

### B6 — `login.dart`'s inline error can never show

`lib/screens/login.dart:24`. `_error` is only ever set to `null`; sign-in failures go to
`_showSignInError`'s dialog. The field, the reset in `_signIn`, and the
`if (_error != null) Text(...)` branch are all unreachable. **Fix:** delete all three; the
dialog already reports errors.

### Noted, not changing

- `lib/screens/library.dart:193` — `_loadLetterCounts` fires 27 `/Items` count requests at
  once every time a library or genre page opens with no cached letters. On a TV over Wi-Fi
  that burst can time out, and then every letter stays enabled. Changing it (batching, or one
  grouped query) changes behaviour and timing, so I've only marked it.
- `lib/screens/library.dart:88,91` — the commented-out `homevideos` and `livetv` cases mean
  those library kinds list movies and series. Looks deliberate; left alone.
- `lib/widgets/custom_theme_editor.dart:203` — `_Stepper` measures
  `MediaQuery.sizeOf(context).width < 600`, where the rest of the app uses
  `isPhoneLayout` (`shortestSide`). Switching would change a phone held sideways, so it's a
  behaviour change — see §3, D5, and tell me which you want.

---

## 2. Unused code to delete

Each verified with a whole-word search across `lib/` (there is no `test/` directory).
"1 hit" means the declaration itself and nothing else.

| What | Where | Check |
| --- | --- | --- |
| `hidePlayedInLatest` getter | `utils/account_settings.dart:51` | 1 hit |
| `setHidePlayedInLatest` | `utils/account_settings.dart:137` | 1 hit |
| `openCurrent()` | `utils/sync_play_controller.dart:121` | 1 hit |
| `customPreset` getter | `utils/theme_controller.dart:30` | 1 hit; `allPresets` already exposes `_custom` |
| `includeProfileLink` parameter | `widgets/profile_actions.dart:13` | 1 hit; the body never reads it |
| `focusedTextFieldKeepsArrow` | `utils/focus_rows.dart:362` | 1 hit |
| `assets/icon.dart` | repo root | 0 bytes, not in `pubspec.yaml` assets |
| `ScrollConfiguration(scrollbars: false)` | `widgets/detail_page.dart:557` | `main.dart:145` turns scrollbars off app-wide |
| `_error` field + inline error text | `screens/login.dart:24,147` | never assigned non-null (B6) |
| commented-out `final isPhone = …` | `screens/settings.dart:250` | dead line |
| `_closings`, `_wasOpen` | `widgets/app_shell.dart:147,149` | removed by the B1 fix |

`sideInsets` is already gone from `app_shell.dart` — nothing to do.

**Need your call before I delete:**

- `app_icons.dart:406,414,421` — `syncPlay`, `appearance` and `server` all have 0 uses
  outside their own declarations. They look like a deliberate set for the Settings tabs
  (which don't show icons today). Keep them for that, or delete?
- `settings.dart:860` — the Server tab is a single "Coming soon." line. Keep the tab, or
  drop it from `_tabs` until there's something in it? (Dropping it also removes a sidebar
  entry under Settings.)
- `player.dart:2136` — the per-segment `debugPrint` loop logs every skip segment of every
  video. Looks like debugging left in. Drop the loop and keep the one summary line?

False positives I checked and left alone: `GoogleFonts.pendingFonts()`
(`font_controller.dart:88`), `JellyfinErrorType.notFound`
(`jellyfin_controller.dart:65`) and `library.userViews()`
(`jellyfin_controller.dart:520`) are all library calls. `syncPlay.openPlayer` has one hit in
`main.dart` but is read inside the controller, so it stays. `isEnabled`
(`focus_rows.dart:349`) is a `ContextAction` override.

---

## 3. Duplication to merge into shared helpers

Two new files: `lib/utils/item_format.dart` (things read off a `JellyfinItem` or its raw
JSON) and `lib/utils/format.dart` (plain formatting and ids).

### D1 — "wide image URL" → `wideImageUrl(...)` in `item_format.dart`

Backdrop → parent backdrop → thumb → primary, taking the raw map plus a `fillWidth`, so both
the `JellyfinItem` and the raw-JSON callers can use it.

Sites: `screens/settings.dart:1117` (`_SyncPlayNowPlaying._wideImage`),
`utils/sync_play_controller.dart:174` (`_watchingFrom`), `widgets/cast_widgets.dart:147`
(`CastRemote`), `screens/player.dart:3373` (`_fetchNextIn`), `widgets/poster_card.dart:177`
(`_imageUrl` — its thumbnail branch is the same ladder in a different order), and
`widgets/detail_page.dart` (`_BackdropBanner`, backdrop only — it can take the helper's
backdrop case). Note the fallback orders genuinely differ today; the helper takes the order
as a parameter so nothing changes on screen.

### D2 — "S1:E3 · Name" → `episodeLabel(...)`

Sites: `widgets/home_modules.dart:1144` (`_TileCaption`), `screens/player.dart:2759`
(`_PlayerTitle`), `screens/player.dart:3356` (`_NextEpisode.title`),
`screens/settings.dart:1100` (`_SyncPlayNowPlaying`), `utils/sync_play_controller.dart:174`
(`_watchingFrom`), `widgets/detail_page.dart:2153` (`_SeriesPlayButton`, as
`'Play S1:E3'`) — six places.

### D3 — random hex id → `randomHexId([int bytes = 16])` in `format.dart`

Sites: `utils/jellyfin_controller.dart:221` (`_deviceId`),
`utils/cast_controller.dart:283`, `screens/player.dart:3280` (`_randomId`).

### D4 — duration formatter → `formatDuration(Duration)`

`screens/player.dart:1813` (`_formatTime`) and `widgets/cast_widgets.dart:319`
(`_RemoteSeekBarState._format`) are character-for-character identical.

### D5 — `MediaQuery.sizeOf(context).shortestSide < 600` → `isPhoneLayout(context)`

Sites in `screens/player.dart`: `:100` (`_isPhone`), `:1507`, `:2442`, `:2715`, `:2913`.
All five are the exact same expression as `isPhoneLayout`, so this is a pure rename.
`widgets/custom_theme_editor.dart:203` uses `.width` instead of `.shortestSide` — switching
that one *would* change a phone held sideways, so I've left it out unless you say otherwise.

### D6 — `http.get(…, headers: jellyfin.authHeaders)` + `jsonDecode` → `getJson` / `postJson`

New methods on `JellyfinController` (`utils/jellyfin_controller.dart:216`), handling the
base URL, the auth header, a timeout, the status check and the decode in one place.

Sites: `utils/account_settings.dart:76` (`_get`, already this shape),
`utils/account_settings.dart:152` (the configuration POST, with its 10.9 fallback),
`utils/sync_play_controller.dart:155` (`_nowPlayingByUser`), `:312` (`_reportCapabilities`),
`:333` (`_syncClock` — no auth header, so it keeps its own call),
`screens/settings.dart:1242` (`_serverInfo` — public endpoint, no auth),
`screens/player.dart:3185` (`_fetchTrackPrefs`), `:3404` (`_fetchNextEpisode`),
`utils/jellyfin_controller.dart` Quick Connect (`:464`, `:486`, `:499`) and
`publicUsers` (`:294`). The ones without an auth header get a `getJsonAt(url)` variant so the
decode and error handling are still shared.

### D7 — runtime "2h 42m" → `formatRuntime(Object? ticks)`

`widgets/detail_page.dart:1397` (`_MovieInfoCard._runtime`) and `:1742`
(`_EpisodeTile._runtime`) are identical.

### D8 — initials from a name → `initialsOf(String)`

`utils/jellyfin_controller.dart:200` (`initials`), `widgets/profile_picker.dart:281`
(`_initials`), `widgets/detail_page.dart:1897` (`_CastTile`),
`widgets/person_tile.dart:64` (`PersonPhoto`). Four near-copies; two take the first two
words, two take first + last. I'll keep "first + last, falling back to one letter", which is
what the two user-facing ones already do, and note that the cast and person tiles change from
"first two words" to "first and last" for three-word names. Say the word if you'd rather keep
them apart.

### D9 — the focused-or-hovered check → `isHighlighted(Set<FTappableVariant>)`

`states.contains(FTappableVariant.focused) || states.contains(FTappableVariant.hovered)`
appears in ten builders: `app_shell.dart:672` and `:956`, `library.dart:428`,
`settings.dart:1164`, `switch_setting.dart:30`, `choice_picker.dart:41`,
`detail_page.dart:2007`, `player.dart:2712`, `cast_widgets.dart:294`,
`expandable_text.dart:77`. One small extension on `Set<FTappableVariant>` in
`lib/theme/app_icons.dart`'s neighbourhood (or a new `lib/theme/tappable_states.dart`).

### D10 — "the next episode of a series", twice

`widgets/detail_page.dart:113` (`nextEpisodeFor`) and `:2125`
(`_SeriesPlayButtonState._findNext`) both do "Next Up, else the first episode of the first
season". They differ only in which season they fall back to (`nextEpisodeFor` skips Specials;
`_findNext` uses `seasons.first`). Have `_findNext` call `nextEpisodeFor` — it already has
the better fallback. **This is a small behaviour change** for a show whose first listed season
is Specials: Play would start at episode 1 of season 1 instead of the first special. I think
that's the intent, but it's your call.

---

## 4. Files to merge, split or move

| Change | Why |
| --- | --- |
| `screens/player.dart` (3,573) → `player.dart` + `part 'player_controls.dart'` + `part 'player_tracks.dart'` + `part 'player_segments.dart'` | Four clearly separate concerns already sitting under their own `// ───` banners: the screen and its state; the controls, seek bar and clock; the audio/subtitle choices and track preferences; the skip segments, trickplay, rating card and Up Next. `part`/`part of` keeps every private name working, so it's a pure move. |
| `widgets/detail_page.dart` (2,173) → `detail_page.dart` + `part 'detail_cards.dart'` + `part 'detail_blocks.dart'` | Navigation, loaders, layouts and the page stay; the four info cards, episode tile and cast tile go to `detail_cards.dart`; `_DetailCard`, `_CardColumn`, `_CardSides`, `_EdgeToEdge`, `_FactsRow`, `_TapShield`, `_PopoutScope` and the floating button go to `detail_blocks.dart`. Again `part`, for the private names. |
| `screens/settings.dart` (1,358) → move the SyncPlay widgets into `part 'sync_play_settings.dart'` | `_SyncPlayCard`, `_SyncPlayGroupTile`, `_SyncPlayNowPlaying` and `_SyncPlayTile` are ~350 lines of SyncPlay in a file that is otherwise the settings shell. They need `_SettingsCard` and `_SectionTitle`, which are private, so `part` rather than a separate library. |
| `widgets/app_shell.dart` (1,019) → `app_shell.dart` + `part 'app_sidebar.dart'` | The shell (scaffold, focus scopes, key handling) and the sidebar (eight widgets, ~560 lines) are two different jobs, and the B1 fix touches both. Splitting after the fix makes the next focus change much easier to find. |
| `screens/movie.dart`, `series.dart`, `person.dart`, `collection.dart` → one `screens/detail_screens.dart` | Twelve to fifteen lines each, all `DetailPage(load: …, layout: …)`. Four files for 54 lines. |
| New `utils/item_format.dart`, `utils/format.dart` | Homes for §3's helpers. |

I'm **not** proposing to split `home_modules.dart` (1,189) — its specs, loaders, cache and
section view read in order and cross-reference each other — or `jellyfin_controller.dart`
(620), which is one cohesive controller.

---

## 5. The estimate

| # | Item | Files touched | − | + | Net |
| --- | --- | ---:| ---:| ---:| ---:|
| B1 | ← into the sidebar lands on the current page | 1 | 95 | 80 | −15 |
| B2 | `/profile` sidebar entry | 1 | 0 | 1 | +1 |
| B3 | doubled gap in "Who's watching?" | 1 | 1 | 0 | −1 |
| B4 | initials crash (covered by D8) | — | — | — | 0 |
| B5 | duplicate `setState` in search | 1 | 8 | 0 | −8 |
| B6 | dead `_error` on login | 1 | 9 | 1 | −8 |
| U1 | `hidePlayedInLatest` / setter | 1 | 3 | 0 | −3 |
| U2 | `openCurrent` | 1 | 6 | 0 | −6 |
| U3 | `customPreset` | 1 | 2 | 0 | −2 |
| U4 | `includeProfileLink` | 1 | 3 | 1 | −2 |
| U5 | `focusedTextFieldKeepsArrow` | 1 | 7 | 0 | −7 |
| U6 | `assets/icon.dart` | 1 | 0 | 0 | 0 |
| U7 | redundant `ScrollConfiguration` | 1 | 5 | 1 | −4 |
| U8 | dead commented line in settings | 1 | 1 | 0 | −1 |
| D1 | shared `wideImageUrl` | 7 | 78 | 38 | −40 |
| D2 | shared `episodeLabel` | 6 | 44 | 18 | −26 |
| D3 | shared `randomHexId` | 4 | 14 | 6 | −8 |
| D4 | shared `formatDuration` | 3 | 12 | 6 | −6 |
| D5 | `isPhoneLayout` in the player | 1 | 6 | 5 | −1 |
| D6 | `getJson` / `postJson` | 6 | 96 | 52 | −44 |
| D7 | shared `formatRuntime` | 2 | 16 | 7 | −9 |
| D8 | shared `initialsOf` | 5 | 28 | 10 | −18 |
| D9 | shared `isHighlighted` | 11 | 22 | 15 | −7 |
| D10 | one "next episode" routine | 1 | 20 | 3 | −17 |
| S1 | split `player.dart` into parts | 4 | 3,573 | 3,590 | +17 |
| S2 | split `detail_page.dart` into parts | 3 | 2,173 | 2,188 | +15 |
| S3 | SyncPlay widgets out of `settings.dart` | 2 | 350 | 357 | +7 |
| S4 | split `app_shell.dart` into parts | 2 | 1,019 | 1,031 | +12 |
| S5 | merge the four detail screens | 5 | 54 | 42 | −12 |
| — | remove the 70 TODO markers | 25 | 70 | 0 | −70 |
| **Totals** | | | **7,685** | **7,452** | **−233** |

The three splits dominate the raw counts because `part` moves whole files; the real change
there is +51 lines of `part` / `part of` / banner boilerplate.

**Files:** 31 distinct files edited · 10 added (`player_controls.dart`,
`player_tracks.dart`, `player_segments.dart`, `detail_cards.dart`, `detail_blocks.dart`,
`sync_play_settings.dart`, `app_sidebar.dart`, `detail_screens.dart`,
`utils/item_format.dart`, `utils/format.dart`) · 5 removed (`assets/icon.dart`,
`screens/movie.dart`, `series.dart`, `person.dart`, `collection.dart`).

**Net: about 230 fewer lines**, and about 420 fewer once the `part` boilerplate is set
against the duplication removed.

Docs are not in these counts: `docs/` (eight guides) plus a rewritten `README.md`, roughly
1,400 new lines of Markdown.

---

## 6. What you'll need to test on the TV

Nothing in §1 can be checked without the remote. After Phase 2:

1. **← into the sidebar, from every kind of page.** Home, a library, a genre, All genres,
   Favorites, Search, each Settings page, a movie page, a show page, a person page, Edit home.
   Each time, the sidebar should open with the entry for *that* page highlighted — the exact
   page inside Libraries, Genres and Settings; the link for Search and Favorites; the logo for
   Home and anything opened from Home.
2. **The case that used to fail.** Libraries → Movies → open a poster → back → press ←.
   It should land on Movies under Libraries, not on the Libraries row and not on the logo.
3. **Picking a page in the sidebar.** The sidebar closes and focus goes to the page's first
   item — never the A–Z column, never a search box. On a library that's still loading it
   should wait and then land on the first poster.
4. **→ out of the sidebar** returns to the item you were on, if it's still on screen.
5. **Sections fold back up.** Open the sidebar, unfold Settings, press → to leave, press ←
   again: Settings should be folded unless you're on a Settings page.
6. **Nothing else moved.** ←/→ still stay inside a row; ↑/↓ still leave a row and remember
   your place; the A–Z still keeps ↑/↓ to itself; ↑/↓ still get you out of the search box.
7. **Edit home** still opens from the sidebar and doesn't crash on the way in (that was the
   "RenderBox was not laid out" case).
