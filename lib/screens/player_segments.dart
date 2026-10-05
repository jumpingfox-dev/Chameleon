part of 'player.dart';

// ─── Trickplay ───────────────────────────────────────────────────────────────

/// Jellyfin's scrubbing thumbnails: sheets of small frames, one every [interval] ms.
class _Trickplay {
  const _Trickplay({
    required this.itemId,
    required this.mediaSourceId,
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.count,
    required this.interval,
  });

  final String itemId;
  final String mediaSourceId;
  final int width; // one thumbnail's size, in pixels
  final int height;
  final int tileWidth; // thumbnails per row / per column on a sheet
  final int tileHeight;
  final int count; // thumbnails in total
  final int interval; // milliseconds between thumbnails

  /// Reads the item's trickplay info, preferring a resolution around 320px wide.
  static _Trickplay? of(JellyfinItem item) {
    final all = item.raw['Trickplay'];
    if (all is! Map || all.isEmpty) return null;
    final source =
        all.entries.first; // keyed by media source, then by thumbnail width
    final sizes = source.value;
    if (sizes is! Map || sizes.isEmpty) return null;

    final infos = sizes.values.whereType<Map>().toList()
      ..sort((a, b) => (a['Width'] as int).compareTo(b['Width'] as int));
    final info = infos.lastWhere(
          (i) => (i['Width'] as int) <= 480,
      orElse: () => infos.first,
    );

    return _Trickplay(
      itemId: item.id,
      mediaSourceId: source.key as String,
      width: info['Width'] as int,
      height: info['Height'] as int,
      tileWidth: info['TileWidth'] as int,
      tileHeight: info['TileHeight'] as int,
      count: info['ThumbnailCount'] as int,
      interval: info['Interval'] as int,
    );
  }

  /// Which sheet shows [position], where on it, and how many columns and rows that sheet has
  /// (the last sheet is usually smaller).
  ({String url, int col, int row, int cols, int rows})? frameAt(
      Duration position,
      ) {
    if (interval <= 0 || count <= 0) return null;
    final perSheet = tileWidth * tileHeight;
    final index = (position.inMilliseconds ~/ interval).clamp(0, count - 1);
    final sheet = index ~/ perSheet;
    final inSheet = index % perSheet;
    final onThisSheet = math.min(perSheet, count - sheet * perSheet);

    return (
    url:
    '${jellyfin.client!.baseUrl}/Videos/$itemId/Trickplay/$width/$sheet.jpg?MediaSourceId=$mediaSourceId',
    col: inSheet % tileWidth,
    row: inSheet ~/ tileWidth,
    cols: math.min(tileWidth, onThisSheet),
    rows: (onThisSheet / tileWidth).ceil(),
    );
  }
}

/// The thumbnail above the seek bar while scrubbing, with the time on it.
/// Only shown when the server has trickplay images; otherwise the time row shows the time.
class _ScrubPreview extends StatelessWidget {
  const _ScrubPreview({
    required this.trickplay,
    required this.frame,
    required this.position,
    this.chapter,
  });

  static const width = 240.0;

  final _Trickplay trickplay;
  final ({String url, int col, int row, int cols, int rows}) frame;
  final Duration position;
  final String? chapter;

  @override
  Widget build(BuildContext context) {
    final height = width * trickplay.height / trickplay.width;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _white, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              // Show just one frame of the sheet. The sheet is drawn at its real size, scaled so one
              // thumbnail fills the preview, then slid into place. No assumptions about how big
              // the sheet is, so partial sheets near the end look right too.
              OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                minHeight: 0,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(-frame.col * width, -frame.row * height),
                  child: Transform.scale(
                    scale: width / trickplay.width, // one thumbnail's pixels → the preview's width
                    alignment: Alignment.topLeft,
                    child: Image.network(
                      frame.url,
                      headers: jellyfin.authHeaders,
                      fit: BoxFit
                          .none, // the sheet at its natural size: no stretching
                      alignment: Alignment.topLeft,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true, // keep the old frame on screen while the next sheet loads
                      errorBuilder: (_, _, _) => SizedBox(
                        width: trickplay.width.toDouble(),
                        height: trickplay.height.toDouble(),
                        child: const ColoredBox(color: Color(0xFF111111)),
                      ),
                    ),
                  ),
                ),
              ),

              // ── The time, on the image ──
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xB3000000),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: width - 16,
                        ), // long names fit inside the thumbnail
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (chapter != null)
                              Text(
                                chapter!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.theme.typography.body.xs
                                    .copyWith(color: _dimWhite),
                              ),
                            Text(
                              formatDuration(position),
                              style: context.theme.typography.body.sm.copyWith(
                                color: _white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Skip segments ───────────────────────────────────────────────────────────

enum _SegmentKind { intro, recap, credits, preview, commercial }

/// A stretch of the video you can skip, such as the intro or the credits.
class _Segment {
  const _Segment(this.kind, this.start, this.end);

  final _SegmentKind kind;
  final Duration start;
  final Duration end;

  /// True while the skip button should show: from the start until a second before the end.
  bool contains(Duration position) =>
      position >= start && position < end - const Duration(seconds: 1);

  String get label => switch (kind) {
    _SegmentKind.intro => 'Skip Intro',
    _SegmentKind.recap => 'Skip Recap',
    _SegmentKind.credits => 'Skip Credits',
    _SegmentKind.preview => 'Skip Preview',
    _SegmentKind.commercial => 'Skip Ad',
  };

  /// For "Skipped intro" and the like.
  String get noun => switch (kind) {
    _SegmentKind.intro => 'intro',
    _SegmentKind.recap => 'recap',
    _SegmentKind.credits => 'credits',
    _SegmentKind.preview => 'preview',
    _SegmentKind.commercial => 'ad',
  };
}

Duration _fromTicks(Object? ticks) =>
    ticks is int ? Duration(microseconds: ticks ~/ 10) : Duration.zero;

/// Jellyfin's segment type names.
_SegmentKind? _kindFromServer(Object? type) => switch (type) {
  'Intro' => _SegmentKind.intro,
  'Recap' => _SegmentKind.recap,
  'Outro' => _SegmentKind.credits,
  'Preview' => _SegmentKind.preview,
  'Commercial' => _SegmentKind.commercial,
  _ => null,
};

/// Recognizes common chapter names, for files without Media Segments.
_SegmentKind? _kindFromChapterName(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'\b(intro|opening|op)\b').hasMatch(n)) return _SegmentKind.intro;
  if (RegExp(r'\b(recap|previously)\b').hasMatch(n)) return _SegmentKind.recap;
  if (RegExp(r'\b(credits|ending|outro|ed)\b').hasMatch(n)) return _SegmentKind.credits;
  if (RegExp(r'\b(preview|next time|next episode)\b').hasMatch(n)) return _SegmentKind.preview;
  return null;
}

/// The item's skippable segments: Jellyfin's Media Segments (from TheIntroDB and similar plugins),
/// or failing that, chapters whose names say what they are.
Future<List<_Segment>> _loadSegments(
    JellyfinClient client,
    JellyfinItem item,
    ) async {
  try {
    final result = await client.mediaSegments.forItem(itemId: item.id);
    final segments = <_Segment>[
      for (final s in result.items)
        if ((_kindFromServer(s.type), s.start, s.end)
        case (final kind?, final start?, final end?) when end > start)
          _Segment(kind, start, end),
    ]..sort((a, b) => a.start.compareTo(b.start));

    debugPrint('Skip segments: ${result.items.length} from the server');
    if (segments.isNotEmpty) return _plausibleSegments(segments, item);
  } on JellyfinException catch (e) {
    debugPrint(
      'Skip segments: server request failed: ${describeJellyfinError(e)}',
    );
  }

  final fromChapters = _plausibleSegments(
    _segmentsFromChapterNames(item),
    item,
  );
  debugPrint('Skip segments: ${fromChapters.length} from chapter names');
  return fromChapters;
}

/// Drops segments that can't be right for this file, so a bad community timestamp
/// can never skip a large part of it.
List<_Segment> _plausibleSegments(List<_Segment> segments, JellyfinItem item) {
  final isMovie = item.type == JellyfinItemKind.movie;
  final runtime = _fromTicks(item.raw['RunTimeTicks']);
  const maxLength = Duration(minutes: 10);

  bool plausible(_Segment s) {
    // Nothing skippable covers most of the file: that's a broken segment, not content to skip.
    if (runtime > Duration.zero && s.end - s.start > runtime * 0.5) return false;

    switch (s.kind) {
      case _SegmentKind.credits:
      // Credits belong near the end: starting in the last 30% of the runtime.
        return runtime == Duration.zero || s.start >= runtime * 0.7;
      case _SegmentKind.preview || _SegmentKind.recap when isMovie:
      return false; // movies don't have previews or recaps
      default:
        return s.end - s.start <= maxLength;
    }
  }

  return segments.where(plausible).toList();
}

List<_Segment> _segmentsFromChapterNames(JellyfinItem item) {
  final chapters = [
    for (final c in (item.raw['Chapters'] as List?) ?? const [])
      if (c is Map && c['StartPositionTicks'] is int)
        (
        name: (c['Name'] as String?) ?? '',
        start: _fromTicks(c['StartPositionTicks']),
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final runtime = _fromTicks(item.raw['RunTimeTicks']);

  return [
    for (var i = 0; i < chapters.length; i++)
      if (_kindFromChapterName(chapters[i].name) case final kind?)
        if ((i + 1 < chapters.length ? chapters[i + 1].start : runtime)
        case final end when end > chapters[i].start)
          _Segment(kind, chapters[i].start, end),
  ];
}

// ─── Rating intro ────────────────────────────────────────────────────────────

/// "RATED / PG-13" with an accent bar, sliding in from the left.
class _RatingIntro extends StatelessWidget {
  const _RatingIntro({required this.rating, required this.visible});

  final String rating;
  final bool visible;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(-0.4, 0),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 450),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x80000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 20, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                Container(
                  width: 4,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _ratingColor(rating) ?? context.theme.colors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RATED',
                      style: context.theme.typography.body.xs.copyWith(
                        color: _dimWhite,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      rating,
                      style: context.theme.typography.display.xl2.copyWith(
                        color: _white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The accent color for an age rating: green for all ages through dark red for adults-only.
/// Null for ratings it doesn't recognize (e.g. "NR"), which use the theme's primary color.
Color? _ratingColor(String rating) {
  const green = Color(0xFF22C55E);
  const yellow = Color(0xFFEAB308);
  const orange = Color(0xFFF97316);
  const red = Color(0xFFEF4444);
  const darkRed = Color(0xFFB91C1C);

  final r = rating.toUpperCase().replaceAll(' ', '');
  switch (r) {
    case 'G' || 'TV-Y' || 'TV-G' || 'U' || 'ALL':
      return green;
    case 'PG' || 'TV-Y7' || 'TV-Y7-FV' || 'TV-PG':
      return yellow;
    case 'PG-13' || 'TV-14' || '12A':
      return orange;
    case 'R' || 'TV-MA':
      return red;
    case 'NC-17' || 'R18' || 'X':
      return darkRed;
  }

  // Age-based ratings from other countries: "15", "FSK-16", "DE-12", "16+", ...
  final age = int.tryParse(RegExp(r'\d+').firstMatch(r)?.group(0) ?? '');
  if (age == null) return null;
  if (age <= 6) return green;
  if (age <= 11) return yellow;
  if (age <= 14) return orange;
  if (age <= 17) return red;
  return darkRed;
}

/// "Skip Intro ››", sliding in while a skippable segment is playing.
class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.segment,
    required this.onPress,
    this.focusNode,
    this.selected = false,
  });

  final _Segment? segment;
  final VoidCallback onPress;
  final FocusNode? focusNode;

  /// Focused by the remote or keyboard: shown solid white.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // Selected (tracked by the player) or hovered: solid white with black text.
    bool isActive(Set<WidgetState> s) =>
        selected || s.contains(WidgetState.hovered);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.2, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: segment == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : FilledButton(
        key: ValueKey(segment!.kind),
        focusNode: focusNode,
        onPressed: onPress,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          elevation: const WidgetStatePropertyAll(0),
          animationDuration: const Duration(milliseconds: 150),
          // At rest: dark and translucent with a thin white outline.
          // Selected or hovered: solid white with black text. The flip itself is the indicator.
          backgroundColor: WidgetStateProperty.resolveWith(
                (s) => isActive(s) ? _white : const Color(0x99141414),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
                (s) => isActive(s) ? _black : _white,
          ),
          side: WidgetStateProperty.resolveWith(
                (s) => BorderSide(
              color: isActive(s) ? _white : const Color(0xB3FFFFFF),
              width: 1.5,
            ),
          ),
          overlayColor: const WidgetStatePropertyAll(
            Color(0x00000000),
          ), // no extra tint: the white fill says it all
        ),
        child: Text(segment!.label),
      ),
    );
  }
}

// ─── Up next ─────────────────────────────────────────────────────────────────

/// The episode after the one playing.
class _NextEpisode {
  const _NextEpisode({required this.id, required this.name, this.season, this.episode, this.imageUrl});

  final String id;
  final String name;
  final int? season;
  final int? episode;
  final String? imageUrl;

  /// "S1:E3 · The Name", or just the name.
  String get title => episodeLabel(season, episode, name);
}

/// What plays after [item]: the next one in [queue] when playing through a list
/// (a collection), otherwise the next episode of its series.
Future<_NextEpisode?> _fetchNextIn(JellyfinItem item, List<String> queue) async {
  if (queue.isEmpty) return _fetchNextEpisode(item);
  final i = queue.indexOf(item.id);
  if (i == -1 || i + 1 >= queue.length) return null; // the end of the list
  final client = jellyfin.client;
  final base = client?.baseUrl;
  if (client == null || base == null) return null;

  try {
    final next = await client.items.byId(queue[i + 1]);
    if (next == null) return null;
    // A wide picture for the card: the backdrop, else the thumbnail, else the poster.
    final imageUrl = wideImageUrl(base, [
      ('Backdrop', next.id, (next.raw['BackdropImageTags'] as List?)?.firstOrNull as String?),
      ('Thumb', next.id, next.imageTags['Thumb']),
      ('Primary', next.id, next.imageTags['Primary']),
    ], quality: 90);
    return _NextEpisode(
      id: next.id,
      name: next.name,
      season: next.raw['ParentIndexNumber'] as int?,
      episode: next.raw['IndexNumber'] as int?,
      imageUrl: imageUrl,
    );
  } on JellyfinException {
    return null;
  }
}

/// The episode after [item] in its series, or null for movies and the last episode.
Future<_NextEpisode?> _fetchNextEpisode(JellyfinItem item) async {
  if (item.type != JellyfinItemKind.episode) return null;
  final client = jellyfin.client;
  final base = client?.baseUrl;
  final seriesId = item.raw['SeriesId'] as String?;
  if (client == null || base == null || seriesId == null) return null;

  try {
    final page = await jellyfin.getJson(
      '/Shows/$seriesId/Episodes',
      query: {
        'userId': ?client.userId,
        'startItemId': item.id, // this episode first, then the ones after it
        'limit': '2',
      },
    );
    final items = ((page as Map)['Items'] as List?) ?? const [];
    if (items.length < 2) return null; // the last episode
    final next = items[1] as Map;
    final id = next['Id'] as String?;
    if (id == null) return null;

    final tag = (next['ImageTags'] as Map?)?['Primary'] as String?;
    return _NextEpisode(
      id: id,
      name: (next['Name'] as String?) ?? 'Next episode',
      season: next['ParentIndexNumber'] as int?,
      episode: next['IndexNumber'] as int?,
      imageUrl: tag == null ? null : '$base/Items/$id/Images/Primary?fillWidth=400&quality=90&tag=$tag',
    );
  } catch (e) {
    debugPrint('Up next: $e');
    return null;
  }
}

/// "Up next" with the episode's picture, a countdown and Play now / Cancel. After several
/// episodes in a row with no button pressed, it asks "Are you still watching?" instead.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({
    required this.next,
    required this.countdown,
    required this.stillWatching,
    required this.compact,
    required this.playNode,
    required this.onPlay,
    required this.onCancel,
  });

  final _NextEpisode next;
  final int countdown;
  final bool stillWatching;
  final bool compact;
  final FocusNode playNode;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final imageWidth = compact ? 104.0 : 140.0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(24 * (1 - t), 0), child: child),
      ),
      child: Container(
        width: compact ? 320 : 420,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xE6141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Row(
              spacing: 12,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: imageWidth,
                    height: imageWidth * 9 / 16,
                    child: next.imageUrl == null
                        ? const ColoredBox(color: Color(0xFF222222))
                        : Image.network(
                      next.imageUrl!,
                      headers: jellyfin.authHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF222222)),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        stillWatching ? 'Are you still watching?' : 'UP NEXT · $countdown',
                        style: stillWatching
                            ? typography.body.md.copyWith(color: _white, fontWeight: FontWeight.w600)
                            : typography.body.xs.copyWith(color: _dimWhite, letterSpacing: 1.5),
                      ),
                      Text(
                        next.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: typography.body.sm.copyWith(color: _white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            FocusRow(
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: FButton(
                      focusNode: playNode,
                      size: .sm,
                      onPress: onPlay,
                      child: Text(stillWatching ? 'Continue watching' : 'Play now'),
                    ),
                  ),
                  Expanded(
                    child: FButton(
                      variant: .outline,
                      size: .sm,
                      onPress: onCancel,
                      child: Text(stillWatching ? 'Stop' : 'Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small message such as "Skipped intro", fading in and out.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: text == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : DecoratedBox(
        key: ValueKey(text),
        decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            text!,
            style: context.theme.typography.body.sm.copyWith(color: _white, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    ),
  );
}
