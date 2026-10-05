part of 'detail_page.dart';

// ─── Backdrop banner (collections, movies) ───────────────────────────────────

/// An item's backdrop, with a parallax effect and its logo in the bottom-left.
class _BackdropBanner extends StatelessWidget {
  const _BackdropBanner({required this.item, required this.topPadding});

  final JellyfinItem item;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final client = jellyfin.client!;
    final colors = context.theme.colors;
    final isPhone = isPhoneLayout(context);

    final backdrops = item.raw['BackdropImageTags'] as List?;
    final backdropTag = backdrops != null && backdrops.isNotEmpty
        ? backdrops.first as String
        : null;
    final logoTag = item.imageTags['Logo'];

    return _TapShield(
      child: Container(
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: isPhone ? 16 / 9 : 21 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (backdropTag != null)
                  _ParallaxBackdrop(
                    topPadding: topPadding,
                    child: Image.network(
                      client.images.url(
                        itemId: item.id,
                        type: JellyfinImagesApi.typeBackdrop,
                        tag: backdropTag,
                        fillWidth: 1600,
                        quality: 90,
                      ),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter, // crop from the bottom, keep the top of the image
                      errorBuilder: (_, _, _) =>
                          ColoredBox(color: colors.muted),
                    ),
                  )
                else
                  ColoredBox(color: colors.muted),

                // Darkens the bottom so the logo stands out on any backdrop.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.4, 1.0],
                      colors: [Color(0x00000000), Color(0xB3000000)],
                    ),
                  ),
                ),

                Positioned(
                  left: 16,
                  bottom: 16,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isPhone ? 200 : 360,
                      maxHeight: isPhone ? 56 : 96,
                    ),
                    child: logoTag != null
                        ? Image.network(
                      client.images.url(
                        itemId: item.id,
                        type: JellyfinImagesApi.typeLogo,
                        tag: logoTag,
                        fillWidth: 720,
                      ),
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomLeft,
                    )
                        : Text(
                      // No logo: the name, in large white text.
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.typography.display.xl2
                          .copyWith(
                        color: const Color(0xFFFFFFFF),
                        shadows: const [
                          Shadow(
                            blurRadius: 8,
                            color: Color(0x99000000),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // ── Close (popouts only) ──
                if (_PopoutScope.of(context))
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Focus(
                      // Doesn't take focus itself: notices when the button gets it from the keyboard or remote,
                      // and scrolls the popout back to the top so the whole banner is in view.
                      canRequestFocus: false,
                      skipTraversal: true,
                      onFocusChange: (hasFocus) {
                        if (!hasFocus || FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
                        Scrollable.maybeOf(context)?.position.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      child: _FloatingIconButton(
                        icon: appIcons.close,
                        label: 'Close',
                        filled: true,
                        autofocus:
                        FocusManager.instance.highlightMode ==
                            FocusHighlightMode.traditional,
                        onPress: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Moves its child down at a fraction of the scroll speed once the banner reaches the top
/// of the view, so the image appears to scroll more slowly than the page.
class _ParallaxBackdrop extends StatelessWidget {
  const _ParallaxBackdrop({required this.topPadding, required this.child});

  final double topPadding;
  final Widget child;

  static const _speed = 0.7; // 0 = no parallax, 1 = the image stays fixed

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.of(context).position;
    final start = topPadding + _PopoutScope.gapOf(context); // where the banner sits before scrolling
    return AnimatedBuilder(
      animation: position,
      builder: (context, child) {
        // Start only once the banner's top edge has scrolled out of view,
        // so no gap ever opens above the image.
        final scrolledPastTop = math.max(0.0, position.pixels - start);
        return Transform.translate(
          offset: Offset(0, scrolledPastTop * _speed),
          child: child,
        );
      },
      child:
      child, // the image itself isn't rebuilt while scrolling, only moved
    );
  }
}

// ─── Collection pieces ───────────────────────────────────────────────────────

/// Count, year span and age rating, then the description, genres and movies.
class _CollectionInfoCard extends StatelessWidget {
  const _CollectionInfoCard({required this.collection, required this.items});

  final JellyfinItem collection;
  final List<JellyfinItem> items;

  /// US film and TV ratings, mildest to strictest, used to find the collection's range.
  static const _ratingOrder = [
    'G',
    'TV-Y',
    'TV-Y7',
    'TV-G',
    'PG',
    'TV-PG',
    'PG-13',
    'TV-14',
    'R',
    'TV-MA',
    'NC-17',
  ];

  /// "2009–2022", or a single year if every movie shares it.
  String? get _years {
    final years = [
      for (final item in items)
        if (item.raw['ProductionYear'] case final int year) year,
    ]..sort();
    if (years.isEmpty) return null;
    return years.first == years.last
        ? '${years.first}'
        : '${years.first}–${years.last}';
  }

  /// "PG-13" if every movie shares it, otherwise the mildest–strictest range, e.g. "PG–R".
  String? get _rating {
    final ratings = {
      for (final item in items)
        if (item.raw['OfficialRating'] case final String r when r.isNotEmpty) r,
    };
    if (ratings.isEmpty) return null;

    final known = ratings.where(_ratingOrder.contains).toList()
      ..sort(
            (a, b) => _ratingOrder.indexOf(a).compareTo(_ratingOrder.indexOf(b)),
      );
    if (known.isEmpty) return ratings.first; // a rating system outside the US list: show it as-is
    return known.first == known.last
        ? known.first
        : '${known.first} – ${known.last}';
  }

  /// The collection's own genres, or else every genre its movies use, most common first.
  List<String> get _genres {
    final own =
        (collection.raw['Genres'] as List?)?.cast<String>() ?? const <String>[];
    if (own.isNotEmpty) return own;

    final counts = <String, int>{};
    for (final item in items) {
      for (final genre
      in (item.raw['Genres'] as List?)?.cast<String>() ??
          const <String>[]) {
        counts[genre] = (counts[genre] ?? 0) + 1;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isPhone = isPhoneLayout(context);
    final muted = context.theme.typography.body.sm.copyWith(
      color: colors.mutedForeground,
    );
    final description = (collection.raw['Overview'] as String?)?.trim();
    final years = _years;
    final rating = _rating;
    final genres = _genres;

    return _DetailCard(
      showClose: false,
      edgeToEdge: true,
      child: _CardColumn(
        children: [
          // ── Count, years, age rating ──
          _FactsRow(
            children: [
              Text(
                '${items.length} ${items.length == 1 ? 'title' : 'titles'}',
                style: muted,
              ),
              if (years != null) Text(years, style: muted),
              if (rating != null) _RatingBadge(rating),
            ],
          ),

          // ── Play, Shuffle, Favorite ──
          ScrollIntoViewOnFocus(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FButton(
                  mainAxisSize: .min,
                  onPress: items.isEmpty
                      ? null
                      : () => playQueue(GoRouter.of(context), collectionQueue(items)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [Icon(appIcons.play, size: 18, fill: 1), const Text('Play')],
                  ),
                ),
                FButton(
                  variant: .outline,
                  mainAxisSize: .min,
                  onPress: items.length < 2
                      ? null
                      : () => playQueue(GoRouter.of(context), collectionQueue(items, shuffle: true)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [Icon(appIcons.shuffle, size: 18, fill: 1), const Text('Shuffle')],
                  ),
                ),
                _FavoriteButton(item: collection),
              ],
            ),
          ),

          // ── Description ──
          if (description != null && description.isNotEmpty)
            ExpandableText(
              description,
              limit: isPhone ? 150 : 400,
              style: context.theme.typography.body.md,
            ),

          // ── Genres ──
          if (genres.isNotEmpty) _GenreButtons(genres),

          // ── Movies ──
          if (items.isNotEmpty) ...[
            const _CardDivider(),
            Text('Movies', style: context.theme.typography.display.lg),
            _InlineItemGrid(items),
          ],
        ],
      ),
    );
  }
}

// ─── Movie pieces ────────────────────────────────────────────────────────────

/// Year, runtime, age rating and score, then Play, the description, genres and the cast.
class _MovieInfoCard extends StatelessWidget {
  const _MovieInfoCard({required this.movie});

  final JellyfinItem movie;


  /// Actors only, in billing order, as Jellyfin lists them.
  List<Map<String, dynamic>> get _cast => [
    for (final p in (movie.raw['People'] as List?) ?? const [])
      if (p is Map<String, dynamic> && p['Type'] == 'Actor') p,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isPhone = isPhoneLayout(context);
    final muted = context.theme.typography.body.sm.copyWith(
      color: colors.mutedForeground,
    );

    final year = movie.raw['ProductionYear'];
    final runtime = formatRuntime(movie.raw['RunTimeTicks']);
    final rating = movie.raw['OfficialRating'] as String?;
    final score = movie.raw['CommunityRating'] as num?;
    final description = (movie.raw['Overview'] as String?)?.trim();
    final genres =
        (movie.raw['Genres'] as List?)?.cast<String>() ?? const <String>[];
    final cast = _cast;

    return _DetailCard(
      showClose: false,
      edgeToEdge: true,
      child: _CardColumn(
        children: [
          // ── Year, runtime, age rating, score ──
          _FactsRow(
            children: [
              if (year != null) Text('$year', style: muted),
              if (runtime != null) Text(runtime, style: muted),
              if (rating != null && rating.isNotEmpty) _RatingBadge(rating),
              if (score != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Icon(appIcons.star, size: 14, color: colors.primary, fill: 1),
                    Text(score.toStringAsFixed(1), style: muted),
                  ],
                ),
            ],
          ),

          // ── Play, Favorite ──
          ScrollIntoViewOnFocus(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FButton(
                  mainAxisSize: .min,
                  onPress: () => context.push('/play/${movie.id}'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      Icon(appIcons.play, size: 18, fill: 1),
                      const Text('Play'),
                    ],
                  ),
                ),
                _FavoriteButton(item: movie),
              ],
            ),
          ),

          // ── Description ──
          if (description != null && description.isNotEmpty)
            ExpandableText(
              description,
              limit: isPhone ? 150 : 400,
              style: context.theme.typography.body.md,
            ),

          // ── Genres ──
          if (genres.isNotEmpty) _GenreButtons(genres),

          // ── Cast ──
          if (cast.isNotEmpty) ...[
            const _CardDivider(),
            Text('Cast', style: context.theme.typography.display.lg),
            _EdgeToEdge(
              // Runs to the card's edges, so the cast scrolls all the way across.
              builder: (padding) => ScrollIntoViewOnFocus(
                child: SizedBox(
                  height: 155,
                  child: FocusRow(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: padding,
                      itemCount: cast.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => _CastTile(person: cast[i]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Series pieces ───────────────────────────────────────────────────────────

/// Years, season count, age rating and score, then the description, genres,
/// a season picker and the chosen season's episodes.
class _SeriesInfoCard extends StatefulWidget {
  const _SeriesInfoCard({required this.series, required this.seasons});

  final JellyfinItem series;
  final List<JellyfinItem> seasons;

  @override
  State<_SeriesInfoCard> createState() => _SeriesInfoCardState();
}

class _SeriesInfoCardState extends State<_SeriesInfoCard> {
  late JellyfinItem? _season = widget.seasons.firstOrNull;
  final _episodes =
  <String, List<JellyfinItem>>{}; // season id → its episodes, once loaded
  String? _loadingSeasonId;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_season != null) _loadEpisodes(_season!);
  }

  Future<void> _loadEpisodes(JellyfinItem season) async {
    if (_episodes.containsKey(season.id)) return; // already loaded: switching back is instant

    final cacheKey = 'episodes:${season.id}';
    if (appCache.isFresh(cacheKey)) {
      setState(
            () =>
        _episodes[season.id] = appCache.peek<List<JellyfinItem>>(cacheKey)!,
      );
      return;
    }

    setState(() {
      _loadingSeasonId = season.id;
      _error = null;
    });
    try {
      final page = await jellyfin.client!.tvShows.episodes(
        seriesId: widget.series.id,
        seasonId: season.id,
        fields: const ['Overview'],
      );
      if (mounted) setState(() => _episodes[season.id] = page.items);
      appCache.put(cacheKey, page.items);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = describeJellyfinError(e));
    } finally {
      if (mounted && _loadingSeasonId == season.id) setState(() => _loadingSeasonId = null);
    }
  }

  /// "2008–2013", "2019–present" for a show still airing, or a single year.
  String? get _years {
    final start = widget.series.raw['ProductionYear'];
    if (start is! int) return null;
    if (widget.series.raw['Status'] == 'Continuing') return '$start–present';
    final end = DateTime.tryParse(
      (widget.series.raw['EndDate'] as String?) ?? '',
    )?.year;
    return end == null || end == start ? '$start' : '$start–$end';
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final colors = context.theme.colors;
    final isPhone = isPhoneLayout(context);
    final muted = context.theme.typography.body.sm.copyWith(
      color: colors.mutedForeground,
    );

    final years = _years;
    final seasonCount = widget.seasons.length;
    final rating = series.raw['OfficialRating'] as String?;
    final score = series.raw['CommunityRating'] as num?;
    final description = (series.raw['Overview'] as String?)?.trim();
    final genres =
        (series.raw['Genres'] as List?)?.cast<String>() ?? const <String>[];
    final season = _season;
    final episodes = season == null ? null : _episodes[season.id];

    return _DetailCard(
      showClose: false,
      edgeToEdge: true,
      child: _CardColumn(
        children: [
          // ── Years, seasons, age rating, score ──
          _FactsRow(
            children: [
              if (years != null) Text(years, style: muted),
              if (seasonCount > 0)
                Text(
                  '$seasonCount ${seasonCount == 1 ? 'season' : 'seasons'}',
                  style: muted,
                ),
              if (rating != null && rating.isNotEmpty) _RatingBadge(rating),
              if (score != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Icon(appIcons.star, size: 14, color: colors.primary, fill: 1),
                    Text(score.toStringAsFixed(1), style: muted),
                  ],
                ),
            ],
          ),

          // ── Play, Favorite ──
          ScrollIntoViewOnFocus(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SeriesPlayButton(series: series, seasons: widget.seasons),
                _FavoriteButton(item: series),
              ],
            ),
          ),

          // ── Description ──
          if (description != null && description.isNotEmpty)
            ExpandableText(
              description,
              limit: isPhone ? 150 : 400,
              style: context.theme.typography.body.md,
            ),

          // ── Genres ──
          if (genres.isNotEmpty) _GenreButtons(genres),

          // ── Seasons and episodes ──
          if (season != null) ...[
            const _CardDivider(),
            // ── Seasons: a compact dropdown on phones (touch only); buttons elsewhere, which work
            // with a remote (a dropdown traps the arrow keys) ──
            if (isPhone)
              SizedBox(
                width: 240,
                child: FSelect<JellyfinItem>(
                  items: {for (final s in widget.seasons) s.name: s},
                  control: FSelectControl.lifted(
                    value: season,
                    onChange: (picked) {
                      if (picked == null || picked.id == season.id) return;
                      setState(() => _season = picked);
                      _loadEpisodes(picked);
                    },
                  ),
                ),
              )
            else
              ScrollIntoViewOnFocus(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8, // many seasons flow onto more lines instead of scrolling sideways
                  children: [
                    for (final s in widget.seasons)
                      FButton(
                        variant: s.id == season.id
                            ? .primary
                            : .outline, // the current season stands out
                        size: .sm,
                        mainAxisSize: .min,
                        onPress: () {
                          if (s.id == season.id) return;
                          setState(() => _season = s);
                          _loadEpisodes(s);
                        },
                        child: Text(s.name),
                      ),
                  ],
                ),
              ),
            if (_loadingSeasonId == season.id && episodes == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: FCircularProgress()),
              )
            else if (_error != null && episodes == null)
              Text(_error!, style: muted)
            else if (episodes != null && episodes.isEmpty)
                Text('No episodes in this season yet.', style: muted)
              else if (episodes != null)
                  Column(
                    spacing: 8,
                    children: [
                      for (final episode in episodes)
                        _EpisodeTile(episode: episode),
                    ],
                  ),
          ],
        ],
      ),
    );
  }
}

/// One episode: thumbnail on the left; number, title, runtime, air date and description beside it.
/// Lifts on hover or remote focus, and plays when selected.
class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode});

  final JellyfinItem episode;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "Jan 20, 2008" from the episode's premiere date.
  String? get _airDate {
    final date = DateTime.tryParse(
      (episode.raw['PremiereDate'] as String?) ?? '',
    );
    return date == null
        ? null
        : '${_months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isPhone = isPhoneLayout(context);
    final number = episode.raw['IndexNumber'];
    final tag = episode.imageTags['Primary']; // an episode's Primary image is its 16:9 thumbnail
    final overview = (episode.raw['Overview'] as String?)?.trim();
    final details = [formatRuntime(episode.raw['RunTimeTicks']), _airDate].whereType<String>().join(' · ');
    final thumbWidth = isPhone ? 140.0 : 240.0;

    return ScrollIntoViewOnFocus(
      alignment: 0.4, // episodes are tall rows: settle a little lower so the previous one stays visible
      child: HoverLift(
        builder: (context, active) => FTappable(
          onPress: () => context.push('/play/${episode.id}'),
          child: AnimatedScale(
            scale: active ? 1.0 : 0.98, // a gentle lift: rows are wide, so a small scale is plenty
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                // ── Thumbnail ──
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(
                      color: active ? colors.primary : const Color(0x00000000),
                      width: 2.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: thumbWidth,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            tag == null
                                ? ColoredBox(
                              color: colors.muted,
                              child: Icon(
                                appIcons.play,
                                color: colors.mutedForeground,
                                fill: 1,
                              ),
                            )
                                : Image.network(
                              jellyfin.client!.images.url(
                                itemId: episode.id,
                                type: JellyfinImagesApi.typePrimary,
                                tag: tag,
                                fillWidth: (thumbWidth * 2).round(),
                                quality: 90,
                              ),
                              fit: BoxFit.cover,
                            ),
                            if (watchProgress(episode) case final progress?)
                              Positioned(
                                left: 6,
                                right: 6,
                                bottom: 6,
                                child: WatchProgressBar(progress),
                              ),
                            if (isWatched(episode))
                              const Positioned(
                                top: 6,
                                right: 6,
                                child: WatchedBadge(size: 20),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Text ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        number != null
                            ? '$number. ${episode.name}'
                            : episode.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.typography.body.md.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details,
                          style: context.theme.typography.body.xs.copyWith(
                            color: colors.mutedForeground,
                          ),
                        ),
                      if (overview != null && overview.isNotEmpty)
                        Text(
                          overview,
                          maxLines: isPhone ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: context.theme.typography.body.sm,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An actor in the cast row: photo, name and character. Lifts on hover or remote focus.
class _CastTile extends StatelessWidget {
  const _CastTile({required this.person});

  final Map<String, dynamic> person;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final id = person['Id'] as String;
    final name = (person['Name'] as String?) ?? '';
    final role = person['Role'] as String?;
    final tag = person['PrimaryImageTag'] as String?;
    final initials = initialsOf(name);

    return HoverLift(
      builder: (context, active) => FTappable(
        onPress: () => openPerson(context, id),
        child: SizedBox(
          width: 110,
          child: Column(
            spacing: 4,
            children: [
              AnimatedScale(
                scale: active ? 1.0 : 0.94,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  // Hovered or focused: a ring drawn over the photo's edge (it takes up no space).
                  foregroundDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active ? colors.primary : const Color(0x00000000),
                      width: 2.5,
                    ),
                  ),
                  child: ClipOval(
                    child: SizedBox.square(
                      dimension: 96,
                      child: tag == null
                          ? ColoredBox(
                        color: colors.muted,
                        child: Center(
                          child: Text(
                            initials,
                            style: TextStyle(color: colors.mutedForeground),
                          ),
                        ),
                      )
                          : Image.network(
                        jellyfin.client!.images.url(
                          itemId: id,
                          type: JellyfinImagesApi.typePrimary,
                          tag: tag,
                          fillWidth: 192,
                          quality: 90,
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.theme.typography.body.xs,
              ),
              if (role != null && role.isNotEmpty)
                Text(
                  role,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.body.xs.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Action buttons ──────────────────────────────────────────────────────────

/// Toggles an item as a favorite in Jellyfin. Updates instantly, and reverts if the server fails.
class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({required this.item});

  final JellyfinItem item;

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  // Jellyfin includes the user's own data (favorite, watched, ...) with each item.
  late bool _favorite =
      ((widget.item.raw['UserData'] as Map?)?['IsFavorite'] as bool?) ?? false;
  bool _saving = false;

  Future<void> _toggle() async {
    if (_saving) return;
    final next = !_favorite;
    setState(() {
      _favorite = next; // show the change right away
      _saving = true;
    });
    try {
      await jellyfin.client!.userData.setFavorite(widget.item.id, next);
      favoritesChanged.value++; // tell the Favorites page to refresh
      // Cached pages for this item, and the Favorites list, now show the wrong heart.
      appCache.invalidateWhere(
            (key) => key.endsWith(':${widget.item.id}') || key == 'favorites',
      );
    } on JellyfinException {
      if (mounted) setState(() => _favorite = !next); // the server refused: undo
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FButton(
    variant: _favorite ? .secondary : .outline,
    mainAxisSize: .min,
    onPress: _toggle,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Icon(
          _favorite ? appIcons.favorite : appIcons.favoriteOutline,
          size: 18,
          color: _favorite ? context.theme.colors.primary : null,
          fill: _favorite ? 1 : 0,
        ),
        Text(_favorite ? 'Favorited' : 'Favorite'),
      ],
    ),
  );
}

/// Plays the series from where you left off: the next unwatched episode,
/// or the very first episode for a show you haven't started.
class _SeriesPlayButton extends StatefulWidget {
  const _SeriesPlayButton({required this.series, required this.seasons});

  final JellyfinItem series;
  final List<JellyfinItem> seasons;

  @override
  State<_SeriesPlayButton> createState() => _SeriesPlayButtonState();
}

class _SeriesPlayButtonState extends State<_SeriesPlayButton> {
  JellyfinItem? _next;

  @override
  void initState() {
    super.initState();
    _findNext();
  }

  Future<void> _findNext() async {
    final client = jellyfin.client!;
    try {
      // Jellyfin's "Next Up": the next episode after the last one you watched.
      final nextUp = await client.tvShows.nextUp(
        seriesId: widget.series.id,
        limit: 1,
        enableResumable: true,
      );
      var next = nextUp.items.firstOrNull;

      // Not started yet: fall back to the first episode of the first season.
      if (next == null && widget.seasons.isNotEmpty) {
        final first = await client.tvShows.episodes(
          seriesId: widget.series.id,
          seasonId: widget.seasons.first.id,
        );
        next = first.items.firstOrNull;
      }
      if (mounted) setState(() => _next = next);
    } on JellyfinException {
      // Leave the button disabled if nothing can be found.
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = _next;
    final se = next == null ? null : seasonEpisode(next.raw['ParentIndexNumber'], next.raw['IndexNumber']);
    final label = se == null ? 'Play' : 'Play $se';

    return FButton(
      mainAxisSize: .min,
      onPress: next == null
          ? null
          : () => context.push('/play/${next.id}'), // disabled until found
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [Icon(appIcons.play, size: 18, fill: 1), Text(label)],
      ),
    );
  }
}
