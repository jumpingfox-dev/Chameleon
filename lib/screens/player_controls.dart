part of 'player.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// How far the controls stay from the screen's edges. The status and navigation bars are
/// hidden while playing, so this is mostly the camera cutout, mirrored on both sides so
/// everything stays centred. Phones add a little more for their rounded corners.
EdgeInsets _overlayInsets(BuildContext context, {required bool compact}) {
  final system = MediaQuery.viewPaddingOf(context);
  final sides = math.max(system.left, system.right);
  if (!compact) return EdgeInsets.symmetric(horizontal: sides);
  return EdgeInsets.fromLTRB(
    math.max(sides, 12),
    math.max(system.top, 4),
    math.max(sides, 12),
    math.max(system.bottom, 12),
  );
}

/// Where to start: the saved position, unless the item was finished.
Duration _resumePosition(JellyfinItem item) {
  final userData = item.raw['UserData'] as Map?;
  final ticks = userData?['PlaybackPositionTicks'];
  if (ticks is! int || ticks <= 0 || userData?['Played'] == true) return Duration.zero;
  return Duration(microseconds: ticks ~/ 10);
}

/// The item's chapter start times, in order.
List<Duration> _chaptersOf(JellyfinItem item) => [
  for (final c in (item.raw['Chapters'] as List?) ?? const [])
    if (c is Map && c['StartPositionTicks'] is int)
      Duration(microseconds: (c['StartPositionTicks'] as int) ~/ 10),
]..sort();

/// The item's chapters with meaningful names, in order. Generic names like
/// "Chapter 5" are left blank, since they say nothing the time doesn't.
List<({String name, Duration start})> _namedChaptersOf(JellyfinItem item) {
  final generic = RegExp(r'^\s*chapter\s*\d+\s*$', caseSensitive: false);
  return [
    for (final c in (item.raw['Chapters'] as List?) ?? const [])
      if (c is Map && c['StartPositionTicks'] is int)
        (
        name: switch (c['Name']) {
          final String n when n.trim().isNotEmpty && !generic.hasMatch(n) =>
              n.trim(),
          _ => '',
        },
        start: Duration(microseconds: (c['StartPositionTicks'] as int) ~/ 10),
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
}

/// The name of the chapter playing at [position], or null if it has no meaningful name.
String? _chapterAt(
    List<({String name, Duration start})> chapters,
    Duration position,
    ) {
  final current = chapters.lastWhere(
        (c) => c.start <= position,
    orElse: () => (name: '', start: Duration.zero),
  );
  return current.name.isEmpty ? null : current.name;
}

/// "4:52 am".
/// The time of day, kept current. Shown at the top right on TVs and tablets.
class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  /// Ticks right as each minute turns over, rather than checking every second.
  void _scheduleTick() {
    final now = DateTime.now();
    final nextMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8, right: 4),
    child: Text(
      _formatClock(_now),
      style: context.theme.typography.display.lg.copyWith(color: _white, fontWeight: FontWeight.w500),
    ),
  );
}

String _formatClock(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$hour:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

// ─── Controls ────────────────────────────────────────────────────────────────

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({
    required this.player,
    required this.item,
    required this.trickplay,
    required this.preview,
    required this.filled,
    required this.chapters,
    required this.hasChapters,
    required this.backNode,
    required this.audioNode,
    required this.subtitlesNode,
    required this.fitNode,
    required this.previousNode,
    required this.playNode,
    required this.nextNode,
    required this.seekNode,
    required this.onAudio,
    required this.onSubtitles,
    required this.onBack,
    required this.onPlayOrPause,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onToggleFit,
    required this.onInteract,
    required this.onDragPreview,
    required this.onCast,
  });

  final Player player;
  final JellyfinItem? item;
  final _Trickplay? trickplay;
  final Duration? preview; // the D-pad scrub position, if scrubbing
  final bool filled;
  final List<({String name, Duration start})> chapters;
  final bool hasChapters;
  final FocusNode backNode;
  final FocusNode audioNode;
  final FocusNode subtitlesNode;
  final FocusNode fitNode;
  final FocusNode previousNode;
  final FocusNode playNode;
  final FocusNode nextNode;
  final FocusNode seekNode;
  final VoidCallback onAudio;
  final VoidCallback onSubtitles;
  final VoidCallback onBack;
  final VoidCallback onPlayOrPause;
  final VoidCallback onPreviousChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onToggleFit;
  final VoidCallback onInteract;
  final ValueChanged<Duration?> onDragPreview;
  final VoidCallback onCast;

  @override
  Widget build(BuildContext context) {
    final previewChapter = preview == null ? null : _chapterAt(chapters, preview!);
    final compact = isPhoneLayout(context);

    // Previous, play/pause, next. Big and in the middle on phones (easy to reach with a thumb);
    // under the seek bar elsewhere.
    Widget transport({required double skipSize, required double playSize, required double spacing}) =>
        FocusRow(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            spacing: spacing,
            children: [
              _ControlButton(
                focusNode: previousNode,
                icon: Icons.skip_previous_rounded,
                label: hasChapters ? 'Previous chapter' : 'Back ${playbackSettings.seekStep} seconds',
                size: skipSize,
                onPress: onPreviousChapter,
              ),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                initialData: player.state.playing,
                builder: (context, snapshot) => _ControlButton(
                  focusNode: playNode,
                  icon: snapshot.data! ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  label: snapshot.data! ? 'Pause' : 'Play',
                  size: playSize,
                  onPress: onPlayOrPause,
                ),
              ),
              _ControlButton(
                focusNode: nextNode,
                icon: Icons.skip_next_rounded,
                label: hasChapters ? 'Next chapter' : 'Forward ${playbackSettings.seekStep} seconds',
                size: skipSize,
                onPress: onNextChapter,
              ),
            ],
          ),
        );

    return Stack(
      fit: StackFit.expand,
      children: [
        // (The shade behind these lives in the player screen, outside the safe area.)

        // ── Phones: transport in the middle of the screen ──
        if (compact)
          transport(skipSize: 40, playSize: 60, spacing: 48),

        // ── Top: back and logo ──
        Positioned(
          top: compact ? 8 : 12,
          left: 12,
          right: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center, // the back arrow sits level with the middle of the title block
            spacing: 8,
            children: [
              // Phones only: TV remotes and keyboards have their own Back button.
              if (compact)
                _ControlButton(
                  focusNode: backNode,
                  icon: Icons.arrow_back_rounded,
                  label: 'Back',
                  size: 28,
                  onPress: onBack,
                ),
              // The title takes all the free space, so everything after it sits at the far right.
              if (item != null)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _PlayerTitle(item: item!),
                  ),
                )
              else
                const Spacer(),
              // AirPlay (iPhone/iPad) and Chromecast (only when one is on the network).
              if (AirPlayButton.available) AirPlayButton(size: compact ? 48 : 40),
              ListenableBuilder(
                listenable: castController,
                builder: (context, _) => showCastButton
                    ? _ControlButton(
                  icon: castIcon,
                  label: 'Cast',
                  size: compact ? 28 : 22,
                  onPress: onCast,
                )
                    : const SizedBox.shrink(),
              ),
              // TVs and tablets: the time of day, in the corner.
              if (!compact) const _Clock(),
            ],
          ),
        ),

        // ── Bottom: heading, seek bar, times, transport ──
        Positioned(
          left: compact ? 24 : 32,
          right: compact ? 24 : 32,
          bottom: compact ? 8 : 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FocusRow(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _ControlButton(
                      focusNode: audioNode,
                      icon: Icons.graphic_eq_rounded,
                      label: 'Audio',
                      size: compact ? 28 : 22,
                      onPress: onAudio,
                    ),
                    _ControlButton(
                      focusNode: subtitlesNode,
                      icon: Icons.subtitles_rounded,
                      label: 'Subtitles',
                      size: compact ? 28 : 22,
                      onPress: onSubtitles,
                    ),
                    _ControlButton(
                      focusNode: fitNode,
                      icon: filled
                          ? Icons.zoom_in_map_rounded
                          : Icons.zoom_out_map_rounded,
                      label: filled ? 'Fit to screen' : 'Fill screen',
                      size: compact ? 28 : 22,
                      onPress: onToggleFit,
                    ),
                  ],
                ),
              ),
              _SeekBar(
                player: player,
                trickplay: trickplay,
                chapters: chapters,
                preview: preview,
                onInteract: onInteract,
                onDragPreview: onDragPreview,
                focusNode: seekNode,
              ),
              _TimeRow(
                player: player,
                preview: preview,
                chapter: trickplay == null ? previewChapter : null,
              ),
              if (!compact) ...[
                const SizedBox(height: 4),
                transport(skipSize: 28, playSize: 32, spacing: 24),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Darkens the top and bottom so the controls read on any frame. Phones also dim the middle
/// a little, where the play button now sits.
class _ControlsShade extends StatelessWidget {
  const _ControlsShade({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.25, 0.6, 1.0],
        colors: [
          const Color(0xB3000000),
          compact ? const Color(0x40000000) : const Color(0x00000000),
          compact ? const Color(0x40000000) : const Color(0x00000000),
          const Color(0xE6000000),
        ],
      ),
    ),
    child: const SizedBox.expand(),
  );
}

/// The double-tap seek feedback: a soft half-circle on the tapped side with
/// "« 10 seconds" (or "30 seconds" after several taps), fading out shortly after.
class _TapSeekIndicator extends StatelessWidget {
  const _TapSeekIndicator({required this.seek, required this.visible});

  final ({int side, int seconds})? seek; // the last run of taps, still set while fading out
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final seek = this.seek;
    final side = seek?.side ?? 1;
    final forward = side > 0;

    return AnimatedOpacity(
      opacity: visible && seek != null ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: Align(
        alignment: forward ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.38,
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x26FFFFFF),
              // Rounded on the inner side only, like a ripple coming from the edge.
              borderRadius: forward
                  ? const BorderRadius.horizontal(left: Radius.elliptical(400, 600))
                  : const BorderRadius.horizontal(right: Radius.elliptical(400, 600)),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Icon(
                    forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                    size: 36,
                    color: _white,
                  ),
                  Text(
                    '${seek?.seconds ?? 10} seconds',
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
    );
  }
}

/// A round icon button. Focused (remote or keyboard): a solid white circle with a dark icon.
/// Hovered: a soft translucent circle. Otherwise: just the white icon.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPress,
    this.size = 22,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;
  final double size;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: FTappable(
      focusNode: focusNode,
      onPress: onPress,
      builder: (context, states, _) {
        final highlighted = isHighlighted(states);
        final compact = isPhoneLayout(context);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.all(compact ? 10 : 7), // phones: 48 px targets for thumbs
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Focused (remote or keyboard) or hovered: the same soft translucent circle.
            color: highlighted ? const Color(0x33FFFFFF) : const Color(0x00FFFFFF),
          ),
          child: Icon(
            icon,
            size: size,
            color: _white,
          ), // the icon stays white either way
        );
      },
    ),
  );
}

/// Top-left: the logo (the show's logo for an episode), or the name as text without one,
/// with a line underneath: the year for movies, "S1:E2 · Episode name" for episodes.
class _PlayerTitle extends StatelessWidget {
  const _PlayerTitle({required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final isEpisode = item.type == JellyfinItemKind.episode;
    final (logoItemId, logoTag) = isEpisode
        ? (
    item.raw['ParentLogoItemId'] as String?,
    item.raw['ParentLogoImageTag'] as String?,
    )
        : (item.id, item.imageTags['Logo']);
    final name = isEpisode
        ? (item.raw['SeriesName'] as String?) ?? item.name
        : item.name;

    final details = isEpisode
        ? episodeLabel(item.raw['ParentIndexNumber'], item.raw['IndexNumber'], item.name)
        : item.raw['ProductionYear']?.toString();

    final nameText = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.theme.typography.display.xl.copyWith(color: _white),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        if (logoItemId != null && logoTag != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240, maxHeight: 56),
            child: Image.network(
              jellyfin.client!.images.url(
                itemId: logoItemId,
                type: JellyfinImagesApi.typeLogo,
                tag: logoTag,
                fillWidth: 480,
              ),
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (_, _, _) =>
              nameText, // the logo failed to load: fall back to the name
            ),
          )
        else
          nameText,
        if (details != null && details.isNotEmpty)
          Text(
            details,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.theme.typography.body.sm.copyWith(color: _dimWhite),
          ),
      ],
    );
  }
}

/// "1:04:26 ............ -44:56 / 4:52 am".
class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.player, required this.preview, this.chapter});

  final Player player;
  final Duration? preview;
  final String? chapter;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: player.stream.position,
    builder: (context, _) {
      final position = preview ?? player.state.position;
      final duration = player.state.duration;
      final remaining = duration > position
          ? duration - position
          : Duration.zero;
      final rate = player.state.rate > 0 ? player.state.rate : 1.0;
      final endsAt = DateTime.now().add(remaining * (1 / rate));
      final style = context.theme.typography.body.sm.copyWith(color: _dimWhite);

      return Row(
        children: [
          Text(
            chapter == null
                ? formatDuration(position)
                : '${formatDuration(position)}  ·  $chapter',
            // While scrubbing, this is where you'll land: bold, in the theme's color.
            style: preview != null
                ? style.copyWith(
              color: style.color,
              fontWeight: FontWeight.w700,
            )
                : style,
          ),
          const Spacer(),
          Text(
            '-${formatDuration(remaining)}  /  ${_formatClock(endsAt)}',
            style: style,
          ),
        ],
      );
    },
  );
}

/// The seek bar: buffered range, played range and a handle. Tap or drag to seek; while dragging
/// or D-pad scrubbing, a trickplay thumbnail shows above the handle.
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.player,
    required this.trickplay,
    required this.chapters,
    required this.preview,
    required this.onInteract,
    this.onDragPreview,
    this.focusNode,
  });

  final Player player;
  final _Trickplay? trickplay;
  final List<({String name, Duration start})> chapters;
  final Duration? preview;
  final VoidCallback onInteract;
  final ValueChanged<Duration?>? onDragPreview;
  final FocusNode? focusNode;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragFraction; // while dragging, where the handle is (0–1)
  bool _focused = false;

  void _seekToFraction(double fraction) {
    final duration = widget.player.state.duration;
    if (duration == Duration.zero) return;
    final target = duration * fraction.clamp(0.0, 1.0);
    // Watch Together: everyone seeks together, when the group says.
    syncPlay.inGroup ? syncPlay.requestSeek(target) : widget.player.seek(target);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: widget.player.stream.position,
    builder: (context, _) {
      final state = widget.player.state;
      final total = state.duration.inMilliseconds;
      double fractionOf(Duration d) =>
          total == 0 ? 0 : (d.inMilliseconds / total).clamp(0.0, 1.0);

      // A drag or D-pad scrub moves the handle to a preview position without seeking yet.
      final preview = _dragFraction != null
          ? state.duration * _dragFraction!
          : widget.preview;
      final played = fractionOf(preview ?? state.position);
      final buffered = fractionOf(state.buffer);
      final primary = context.theme.colors.primary;
      // Phones: a thicker bar, a bigger handle and a taller touch area, for thumbs.
      final compact = isPhoneLayout(context);
      final thickness = compact ? 6.0 : 4.0;
      final handle = compact
          ? (preview != null ? 26.0 : 20.0)
          : (preview != null || _focused ? 18.0 : 14.0);

      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final x = width * played;
          double fractionAt(double dx) => (dx / width).clamp(0.0, 1.0);

          return Focus(
            focusNode: widget.focusNode,
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                widget.onInteract();
                _seekToFraction(fractionAt(details.localPosition.dx));
              },
              onHorizontalDragStart: (details) {
                widget.onInteract();
                setState(
                      () => _dragFraction = fractionAt(details.localPosition.dx),
                );
                widget.onDragPreview?.call(state.duration * _dragFraction!);
              },
              onHorizontalDragUpdate: (details) {
                widget.onInteract();
                setState(
                      () => _dragFraction = fractionAt(details.localPosition.dx),
                );
                widget.onDragPreview?.call(state.duration * _dragFraction!);
              },
              onHorizontalDragEnd: (_) {
                if (_dragFraction != null) _seekToFraction(_dragFraction!);
                setState(() => _dragFraction = null);
                widget.onDragPreview?.call(null);
              },
              child: SizedBox(
                height: compact ? 44 : 28,
                child: Stack(
                  clipBehavior: Clip.none, // the preview rises above the bar
                  alignment: Alignment.centerLeft,
                  children: [
                    _bar(width, const Color(0x40FFFFFF), thickness),
                    _bar(width * buffered, const Color(0x66FFFFFF), thickness),
                    _bar(x, _white, thickness),
                    Positioned(
                      left: math.max(0, x - handle / 2),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: handle,
                        height: handle,
                        decoration: BoxDecoration(
                          color: preview != null ? primary : _white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    if (preview != null)
                      if (widget.trickplay?.frameAt(preview) case final frame?)
                        Positioned(
                          bottom: compact ? 44 : 36,
                          left: (x - _ScrubPreview.width / 2).clamp(
                            0.0,
                            math.max(0.0, width - _ScrubPreview.width),
                          ),
                          child: _ScrubPreview(
                            trickplay: widget.trickplay!,
                            frame: frame,
                            position: preview,
                            chapter: _chapterAt(widget.chapters, preview),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Widget _bar(double width, Color color, double thickness) => Container(
    width: width,
    height: thickness,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(thickness / 2),
    ),
  );
}
