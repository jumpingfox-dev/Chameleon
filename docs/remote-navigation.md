# Remote navigation

How D-pad focus works, and what to do to make a new screen remote-friendly.

## Why this exists

Flutter's built-in directional focus picks "the nearest focusable widget in that direction,"
which falls apart on a TV: pressing ↓ from a poster can land on a button three rows down just
because it happens to be closer than the row directly below. `lib/utils/focus_rows.dart`
replaces that entirely for everything under `RowFocusNavigation`, installed once near the top
of the app in `main.dart`:

```dart
builder: (context, child) => TextFieldArrowEscape(
  child: RowFocusNavigation(
    child: UiScaler(child: FTheme(data: theme, child: ...)),
  ),
),
```

## The building blocks

**`FocusRow`** marks a set of focusable widgets as one horizontal row — a section's posters,
a row of buttons. ←/→ move along the row and stop at its ends (no wrapping into the next
row); ↑/↓ leave the row for the nearest row above or below, landing on the item you last had
focused there if you go back. Wrap the row's children, not each child individually:

```dart
FocusRow(
  child: ListView.separated(
    scrollDirection: Axis.horizontal,
    itemBuilder: (context, i) => PosterCard(item: items[i], ...),
    ...
  ),
)
```

Used throughout `widgets/home_modules.dart` (each section's row), `widgets/detail_cards.dart`
(the cast row), and the player's transport and option rows (`screens/player_controls.dart`).

**`FocusColumn`** is the opposite: a side column, kept apart from the rest of the page, where
↑/↓ stay inside it and stop at its ends, and ↑/↓ from elsewhere never land in it. ←/→ move in
and out as normal. The only user today is the A–Z rail in `screens/library.dart`:

```dart
SizedBox(
  width: _width,
  child: FocusColumn(child: Column(children: [...letters])),
)
```

**`TextFieldArrowEscape`** lets ↑/↓ leave a one-line text field (a search box, a sign-in
field) for whatever is above or below it, which a text field otherwise keeps for moving the
cursor. Multi-line fields still use ↑/↓ to move between lines, only escaping from the first or
last line. Installed once, next to `RowFocusNavigation`, in `main.dart` — you don't add this
per-screen.

**`moveFocus(TraversalDirection)`** is what both of the above call into, and it's also the
one to call directly when a widget wants to handle its own keys instead of letting Flutter's
focus traversal do it — the player does this for its own D-pad scrubbing
(`screens/player.dart`'s `_onKey`), and the shell does it for ←/→ at a page's edge (below).

**`firstFocusable(scope, {mainOnly})`** finds the item a newly-opened page should focus: the
first one, in the order the page lists them, that's actually laid out. Text fields and a
`FocusColumn`'s items only count if `mainOnly: false` and nothing else qualifies — so opening
a library focuses the first poster, not the search box or the A–Z rail.

**`isOnTopPage(node)`** matters because hidden pages stay in the tree with their old focus
positions (`StatefulShellRoute`'s branches, and popouts underneath another popout). Both
`moveFocus` and `firstFocusable` skip anything not on the page you're actually looking at.

## The shell's two scopes

`widgets/app_shell.dart`'s `_AppShellState` owns two `FocusScopeNode`s: `_navScope` (the
sidebar) and `_pageScope` (the current page). On wide screens, ← at a page's left edge enters
the sidebar and → from the sidebar returns to the page — handled by `_onPageKey` and
`_onNavKey`, attached as `onKeyEvent` on each `FocusScope`:

```dart
FocusScope(
  node: _pageScope,
  onKeyEvent: isPhone ? null : _onPageKey, // ← into the sidebar when nothing's left of you
  child: widget.navigationShell,
)
```

`_onPageKey` only acts on ←, and only once `moveFocus(TraversalDirection.left)` has already
failed (nothing more to the left on the page) — so a row of buttons still absorbs ← itself
before the shell ever sees it. It also leaves ← alone inside a popup route or while a text
field's cursor isn't already at the start, so those keep the key to themselves.

Entering the sidebar (`_enterSidebar`) lands on the entry for wherever you are — see
`_AppShellState._here`, which maps a route to a sidebar entry name like `'Settings/Appearance'`
or `'Libraries/<id>'`. Each sidebar entry keeps its own permanent `FocusNode`
(`_navNodes`, via `_navNode(id)`), so focus can always be requested on it directly without
walking the tree. If the entry's section (Libraries, Genres, Settings) happens to be folded —
forui only reads `FSidebarItem.initiallyExpanded` once, when it's first built — `_enterSidebar`
forces it open by bumping that label's entry in `_forceOpen`, which changes the section's
`ValueKey` and makes forui rebuild it fresh with the right state. See `app_sidebar.dart`'s
`_SidebarSection` for the mechanics, and `architecture.md`'s note on `part` files for why the
sidebar lives in a separate file sharing `app_shell.dart`'s private names.

Picking something in the sidebar always moves focus to the new page's first item
(`_focusNewPage`), polling for a few frames if the page is still loading rather than giving
up immediately — a library or genre page has nothing to focus until its first items have
loaded.

## Making a new screen remote-friendly

1. **Group anything that reads as one row** (a horizontal list of cards, a row of buttons) in
   a `FocusRow`. Don't wrap single buttons — only genuine rows.
2. **If the page has a side column** that should ignore ↑/↓ from the main content (and vice
   versa), wrap it in `FocusColumn`.
3. **Don't fight `firstFocusable`.** If the page's first interactive widget shouldn't be the
   one that gets focus when the page opens (say, a search box at the top), make sure a normal
   button or card comes before it in the widget tree, or accept that it'll get focus when
   nothing else does (text fields are the fallback, not the first choice).
4. **If you add a new sidebar entry**, give it a name in `_here`'s mapping and a focus node
   via `nodeFor(id)` in `app_sidebar.dart` — see [adding-a-screen.md](adding-a-screen.md).
5. **Don't rely on hover state for anything that must also work by remote.** Check
   `states.contains(FTappableVariant.focused)` too (or use the shared `isHighlighted(states)`
   helper in `theme/tappable_states.dart`, which already checks both).

## What you can't check without a TV

Everything above is reasoned from the code and from the desktop build (arrow keys work the
same way on desktop as on a TV remote, since both go through the same `RowFocusNavigation`).
Trickplay thumbnails, the exact feel of D-pad scrubbing, and anything timing-sensitive on a
real remote still want a hands-on check on the device.
