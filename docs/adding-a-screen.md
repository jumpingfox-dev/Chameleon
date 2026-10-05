# Adding a screen

Three things to wire up: the route, the sidebar entry (wide screens), and the phone nav entry.
Two different kinds of screen, depending on whether it needs its own place in the sidebar:

- A **top-level page** (like Favorites or a library) gets a route under one of the four
  branches, and usually a sidebar entry.
- A **sub-page reached from elsewhere** (a movie, a person) only needs the route — it opens
  as a popout (`showDetailPopout`) or a route pushed on top, and ← from it falls back to
  whatever sidebar entry its *parent* page uses (see `_here` in
  [remote-navigation.md](remote-navigation.md)).

## 1. The route

Branch routes live in `destinations` in `lib/widgets/app_shell.dart`. Add a `GoRoute` to the
right branch's `routes` list:

```dart
final destinations = <AppDestination>[
  (
    label: 'Home',
    icon: (i) => i.home,
    path: '/home',
    screen: (_) => const HomeScreen(),
    routes: [
      // ...existing routes...
      GoRoute(
        path: 'recommendations', // -> /home/recommendations
        builder: (context, state) => const RecommendationsScreen(),
      ),
    ],
  ),
  // ...
];
```

A route that takes a parameter follows the existing `library/:id` pattern:

```dart
GoRoute(
  path: 'collection/:id',
  builder: (context, state) => CollectionScreen(collectionId: state.pathParameters['id']!),
),
```

If the screen is reached from more than one place and shows as a card over the current page
rather than a full navigation, use `showDetailPopout` instead of a route — see how
`openItem` in `lib/widgets/detail_page.dart` opens movies, series and collections.

## 2. The screen itself

Put it in `lib/screens/`. The minimal shape:

```dart
class RecommendationsScreen extends StatelessWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context) => FScaffold(
    header: FHeader(title: Text('Recommendations')),
    child: /* ... */,
  );
}
```

If it needs to load something, follow the pattern in `screens/favorites.dart` or
`screens/library.dart`: a `StatefulWidget`, a cache check in `initState` (see
`utils/app_cache.dart`), and a `_load()` that calls into `jellyfin.client`.

## 3. The sidebar entry (wide screens)

In `lib/widgets/app_sidebar.dart`'s `_Sidebar.build`, add a `_SidebarLink` (a plain link) or
a `_SidebarSection` (a folding list of pages, like Libraries or Settings) alongside the
existing ones:

```dart
_SidebarLink(
  label: 'Recommendations',
  icon: appIcons.suggested, // or add a new one in theme/app_icons.dart
  focusNode: nodeFor('Recommendations'),
  open: open,
  selected: loc == '/home/recommendations',
  onPress: () => goTo('/home/recommendations'),
),
```

`nodeFor(id)` gives the entry a permanent `FocusNode`, keyed by whatever name you pick — this
is what lets ← from the page land directly back on this entry. That name has to match what
`_here` in `app_shell.dart`'s `_AppShellState` returns for this route, so ← actually finds it:

```dart
(String, String?) get _here {
  final loc = widget.location;
  // ...
  if (loc == '/home/recommendations') return ('Recommendations', null);
  // (second value is non-null only for a page *inside* a folding section, e.g. 'Libraries/<id>')
  return ('Home', null);
}
```

Skip this step for a sub-page that doesn't want its own sidebar entry (most detail pages) —
`_here`'s fallback already sends ← back to Home, or whatever section the page is "inside."

## 4. The phone nav entry

Phones don't use the sidebar — a top-level page only shows up there if you add a
`NavButton` somewhere reachable (`widgets/nav_button.dart`), the way `screens/home.dart`'s
horizontal row of library/genre buttons does for phones specifically
(`if (isPhone && ...)`). A page that's only reachable via the sidebar on wide screens still
needs *some* phone-visible way in, or it becomes unreachable on a phone — a button on Home,
a link from Settings, or similar.

The four bottom-nav tabs themselves (Home, Search, Settings, Profile) are fixed — adding a
fifth means also touching `FBottomNavigationBar`'s children in `app_shell.dart` and probably
isn't what you want; a new page almost always belongs *under* one of the four.

## Checklist

- [ ] Route added under the right branch (or opened as a popout from an existing page)
- [ ] Screen built, following the loading/caching pattern of a similar existing screen
- [ ] Sidebar entry added, with a `nodeFor` name that matches `_here`'s mapping (skip for a
      sub-page)
- [ ] Some way to reach it on a phone (skip if it's a sub-page reached the same way on every
      platform)
- [ ] `flutter analyze` clean
