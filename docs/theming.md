# Theming

Theme presets, the custom theme editor, fonts, icon styles, and how focus shows on a TV. The
app uses Material 3 widgets throughout.

## How a theme comes together

A theme starts as a `Palette` (`lib/theme/palette.dart`): the app's own set of colors
(background, foreground, primary, secondary, muted, card, border, ...), which is what the
presets define and the custom editor edits. `Palette.toColorScheme()` maps it onto Material's
color roles:

| Palette | ColorScheme |
|---|---|
| `background` / `foreground` | `surface` / `onSurface` |
| `card` → `muted` | `surfaceContainer` → `surfaceContainerHighest` (steps in between are blended) |
| `primary` / `primaryForeground` | `primary` / `onPrimary` |
| `secondary` / `secondaryForeground` | `secondaryContainer` / `onSecondaryContainer` |
| `mutedForeground` | `onSurfaceVariant` |
| `border` | `outlineVariant` |
| `error`, `barrier` | `error`, `scrim` |

`buildTheme()` in `lib/theme/theme.dart` takes the palette and the chosen fonts and returns a
`ThemeData`. Headings and titles (display, headline and title styles) use the heading font;
everything else (body and label styles) uses the body font. `Application.build` in `main.dart`
calls it on every rebuild, listening to `themeController`, `fontController` and
`iconController` together:

```dart
ListenableBuilder(
  listenable: Listenable.merge([themeController, fontController, iconController]),
  builder: (context, _) {
    final theme = buildTheme(themeController.value.colors, displayFont: fontController.display, bodyFont: fontController.body);
    return MaterialApp.router(theme: theme, ...);
  },
)
```

Widgets read the theme through two shortcuts from `theme.dart`: `context.colors` (the
`ColorScheme`) and `context.text` (the `TextTheme`).

## Presets

`lib/theme/theme_presets.dart` defines `themePresets`, a plain list of `ThemePreset(id, label,
colors)`. Each `colors` is a complete `Palette` — add a preset by adding an entry here, with
every field filled in (there's no partial-preset inheritance). `themeController.select(preset)`
saves the chosen id and switches `value`; `ThemeController.load()` looks the saved id up
again at startup, falling back to `themePresets.first` if it's missing (an old custom preset
from before a preset list change, say).

## The custom theme editor

Custom isn't a preset in the list — it's synthesized on the fly by `ThemeController` itself
(`customThemeId = 'custom'`) and always appears as the last option. Two editing modes, both in
`features/settings/custom_theme_editor.dart`:

- **Simple**: four steppers (`_SeedEditor`) over a `ThemeSeed(baseHue, accentHue, vibrance,
  depth)`, each 0–359 or 0–9. `generateColors(seed)` in `theme_presets.dart` turns that into a
  full `Palette` by HSL math — tweak the hue/lightness formulas there if the generated palette
  needs adjusting. The seed also has a shareable 8-digit code (`ThemeSeed.code` /
  `ThemeSeed.parse`), shown and editable as text.
- **Advanced**: a text box of `name = color` lines (`_AdvancedEditor`), parsed by
  `parseColorIni` in `theme/custom_colors.dart` into a `Palette`, starting from the current
  seed's colors as a base. `colorsToIni` does the reverse, for prefilling the box.

`themeController.applySeed(seed)` and `applyCustomIni(text)` both save and immediately call
`_activate()`, which rebuilds `_custom` and reassigns `value` to a **new** `ThemePreset`
instance (not just mutates the old one) — needed so `ListenableBuilder`/`ValueListenableBuilder`
actually notice the change.

## Fonts

Any Google Font, picked separately for headings (`fontController.display`) and body text
(`fontController.body`), plus a third, independent pick for subtitles
(`playbackSettings.subtitleFont`, since that's a playback setting, not an appearance one —
see [adding-a-setting.md](adding-a-setting.md)). `theme/font_controller.dart`'s
`searchFonts(query)` filters `GoogleFonts.asMap().keys` and preloads the first screenful so
the list doesn't flash unstyled text; `pruneFontCache` deletes cached font files for anything
no longer selected, run once at startup in `main.dart`.

## Icon styles

Every icon in the app is a named getter on `AppIconSet` in `theme/app_icons.dart`
(`appIcons.play`, `appIcons.favorite`, ...) — screens never import an icon pack directly, so
switching styles is instant everywhere. Each getter picks one icon per `IconStyle` via `_pick`:

```dart
IconData get play => _pick(
    Symbols.play_circle_rounded,       // Material Symbols
    FPhosphorFillIcons.playCircle,     // Phosphor
    FLucideIcons.circlePlay,           // Lucide
    CupertinoIcons.play_circle_fill,   // Cupertino
    FluentIcons.play_circle_24_filled  // Fluent
);
```

Adding an icon means adding a getter here with all five variants filled in — there's no
fallback for a missing one. `IconController` (bottom of the same file) holds the chosen
`IconStyle` and calls `_redrawEverything()` on change, which forces the whole tree to rebuild
even though icons are read directly rather than through something each widget listens to.

## Focus on a TV

A remote has no pointer, so whatever has focus must be easy to spot from across the room.

- **Material buttons and chips** get a 2px ring while focused, on top of Material's usual
  focus overlay. It's set once in `buildTheme()` (the `side` of each button theme and the
  chip theme), so screens use plain `FilledButton`, `OutlinedButton`, `TextButton`,
  `IconButton` and `ChoiceChip`.
- **The app's own cards and tiles** (posters, the letter bar, the sidebar, player controls)
  use `Tappable` from `lib/widgets/tappable.dart`. It handles taps, clicks and the remote's
  Select key, and hands its `builder` the current `WidgetState`s. `isHighlighted(states)` is
  true while it's focused or hovered, so a remote and a mouse look the same:

  ```dart
  Tappable(
    onPress: onPress,
    builder: (context, states, child) => AnimatedContainer(
      color: isHighlighted(states) ? context.colors.onSurface.withValues(alpha: 0.1) : null,
      ...
    ),
  )
  ```

  `WidgetState.focused` is only set while focus should show (a keyboard or remote is in
  use), not after a tap.
