# Home modules

How a home-screen section works, and how to add a new kind.

## The pieces

A section is a `HomeModule` (`utils/home_layout.dart`): a `HomeModuleType`, an id (unique
within the layout, so two Genre sections can be told apart), and optionally a `param`
(a collection's id, a genre's name), a `label` (display name for that param) and a `view`
override (poster or thumbnail). The home screen's whole layout is just
`List<HomeModule>`, held by `homeLayout` and saved as JSON.

What a section *shows* is separate from the module itself: `homeModuleSpecs` in
`widgets/home_modules.dart` maps each `HomeModuleType` to a `HomeModuleSpec` — its title,
description, icon and a `load` function:

```dart
typedef HomeModuleLoader = Future<HomeModuleContent> Function(JellyfinClient client, HomeModule module);

class HomeModuleSpec {
  const HomeModuleSpec({required this.title, required this.description, required this.icon, required this.load, this.view});
  final LibraryView? view; // a fixed default view, or null for poster-on-phone/thumbnail-elsewhere
}
```

`HomeModuleView` (same file) is the widget that actually renders one section: it loads via
the spec, caches the result for 10 minutes (`_homeCache`, keyed by the module's *id*, not its
type — so two Genre sections cache separately), and shows a `FocusRow` of `PosterCard`s (or
the featured carousel, for `HomeModuleType.carousel`).

## Adding a new kind of section

1. **Add the type** to `HomeModuleType` in `utils/home_layout.dart`:

   ```dart
   enum HomeModuleType {
     carousel, continueWatching, nextUp, favorites, recentlyAdded,
     recentlyAddedMovies, recentlyAddedSeries, suggested, becauseYouWatched,
     collection, genre,
     topRated, // new
   }
   ```

   If more than one of this type can exist at once (like Collection and Genre), add it to
   `allowsMultiple` too.

2. **Write the loader** and add the spec entry in `widgets/home_modules.dart`:

   ```dart
   HomeModuleType.topRated: HomeModuleSpec(
     title: 'Top Rated',
     description: 'Your highest-rated movies and shows',
     icon: (i) => i.star,
     load: (client, _) async => HomeModuleContent(
       (await client.items.list(
         includeItemTypes: _moviesAndShows,
         recursive: true,
         sortBy: const ['CommunityRating'],
         descending: true,
         limit: 30,
       )).items,
     ),
   ),
   ```

   `HomeModuleContent(items, {title})` is the loader's return value — `title` overrides the
   spec's default title (used by Collection, Genre and "Because You Watched…" to show the
   actual collection/genre/title name instead of a generic label).

3. **If it needs a parameter** (like Collection's id or Genre's name), handle it in
   `AddHomeModules._add` in the same file — see the `case HomeModuleType.genre:` branch,
   which opens `_showOptionPicker` before calling `homeLayout.add(type, param: ..., label:
   ...)`. A type with no parameter just calls `homeLayout.add(type)` directly (the `default:`
   branch already covers this — nothing to add there for a simple new type).

That's it — the type now appears in "Add a section" automatically (`homeLayout.available`
filters by `allowsMultiple` and what's already on the screen), and the edit controls (move,
remove, toggle view) work on it the same as every other section without extra code.

## Caching and refresh

Each section's content is cached for `homeCacheDuration` (10 minutes) in `_homeCache`.
`homeVisible` is bumped whenever you navigate back to `/home` (`HomeScreen._onNavigate`),
which every `HomeModuleView` listens for to refresh if its own cache has gone stale —
sections don't all refresh at once, only the ones that need it. `favoritesChanged` similarly
triggers a refresh for any section (`favorites`, or Continue Watching showing a favorited
item's badge) when a favorite toggles anywhere in the app.

## Reordering, removing, resetting

All go through `homeLayout`: `move(id, by)`, `remove(id)`, `reset()` (back to
`HomeLayoutController.defaultTypes`), `setView(id, view)`. Each saves immediately and bumps
`value`, so the Home screen's `ListenableBuilder` picks it up without any extra plumbing.
