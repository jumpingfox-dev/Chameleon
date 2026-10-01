// The player always uses Flutter's built-in Material icons (not appIcons):
// solid, evenly weighted and instantly recognizable for media controls,
// whatever icon style is chosen in Settings.

import 'dart:async';
import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../utils/app_cache.dart';
import '../utils/focus_rows.dart';
import '../utils/jellyfin_controller.dart';
import '../utils/orientation.dart';
import '../utils/playback_reporter.dart';
import '../widgets/choice_picker.dart';
import '../widgets/home_modules.dart';

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);
const _dimWhite = Color(0xCCFFFFFF);

/// Full-screen playback of a movie or episode.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.itemId});

  final String itemId;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _hideAfter = Duration(seconds: 3);
  static const _fallbackSkip = Duration(
    seconds: 10,
  ); // for files without chapters
  static const _scrubCommitAfter = Duration(milliseconds: 1500);

  final _player = Player();
  late final _video = VideoController(_player);
  final _videoKey = GlobalKey<VideoState>();
  final _focus = FocusNode();
  final _subscriptions = <StreamSubscription<Object?>>[];

  // One node per control, so the remote can move between rows exactly as planned.
  final _backNode = FocusNode(debugLabel: 'Back');
  final _audioNode = FocusNode(debugLabel: 'Audio');
  final _subtitlesNode = FocusNode(debugLabel: 'Subtitles');
  final _fitNode = FocusNode(debugLabel: 'Fit');
  final _previousNode = FocusNode(debugLabel: 'Previous');
  final _playNode = FocusNode(debugLabel: 'Play/Pause');
  final _nextNode = FocusNode(debugLabel: 'Next');
  final _seekNode = FocusNode(debugLabel: 'Seek bar');
  final _skipNode = FocusNode(debugLabel: 'Skip');
  bool _skipFocused = false; // drives the skip button's "selected" look

  List<FocusNode> get _optionRow => [_audioNode, _subtitlesNode, _fitNode];
  List<FocusNode> get _transportRow => [_previousNode, _playNode, _nextNode];
  List<FocusNode> get _allButtons => [
    _backNode,
    ..._optionRow,
    ..._transportRow,
  ];

  /// Where subtitles sit: just above the bottom edge normally, and lifted above the
  /// seek bar and buttons while the controls are showing.
  static const _subtitlesNormal = EdgeInsets.fromLTRB(48, 0, 48, 48);
  static const _subtitlesLifted = EdgeInsets.fromLTRB(48, 0, 48, 150);

  JellyfinItem? _item;
  String? _error;
  PlaybackReporter? _reporter;

  /// Chapter start times, in order. Empty when the file has none.
  List<Duration> _chapters = const [];

  /// Chapters with their names, for showing while scrubbing.
  List<({String name, Duration start})> _namedChapters = const [];

  /// Skippable stretches (intro, credits, ...), and the one playing right now, if any.
  List<_Segment> _segments = const [];
  _Segment? _activeSegment;

  /// Thumbnail sheets for scrubbing, if the server has generated them.
  _Trickplay? _trickplay;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// Fit shows the whole picture (with bars if the shape differs from the screen);
  /// fill zooms in to cover the screen, trimming the edges.
  BoxFit _fit = BoxFit.contain;

  /// Where a D-pad scrub would jump to, while scrubbing; null otherwise.
  Duration? _scrub;
  Timer? _scrubCommit;
  int _scrubRepeats = 0;

  /// Where a mouse or touch drag on the seek bar is, while dragging; null otherwise.
  Duration? _dragPreview;

  /// The age-rating card shown shortly after playback starts.
  bool _ratingShown = false;
  bool _ratingVisible = false;
  Timer? _ratingTimer;

  @override
  void initState() {
    super.initState();
    AppOrientation.player(); // landscape and immersive on phones
    _subscriptions
      ..add(
        _player.stream.error.listen((message) {
          // Only treat it as fatal if nothing has loaded; mpv also reports minor stream hiccups.
          if (mounted && _player.state.duration == Duration.zero) setState(() => _error = message);
        }),
      )
      ..add(
        _player.stream.playing.listen((playing) {
          // Controls stay up while paused, and fade out again once playing.
          playing ? _scheduleHide() : _showControls(autoHide: false);
          if (playing) _introduceRating();
        }),
      )
      ..add(_player.stream.position.listen(_updateActiveSegment))
      // Finished (including after skipping end credits): go back to where you were.
      ..add(
        _player.stream.completed.listen((completed) {
          if (completed && mounted) context.pop();
        }),
      );
    _skipNode.addListener(() {
      final focused = _skipNode.hasFocus;
      if (focused != _skipFocused && mounted) setState(() => _skipFocused = focused);
    });
    _start();
  }

  Future<void> _start() async {
    final client = jellyfin.client;
    if (client == null) return;
    try {
      final item = await client.items.byId(widget.itemId);
      if (item == null) throw StateError('Not found');
      if (!mounted) return;
      setState(() {
        _item = item;
        _chapters = _chaptersOf(item);
        _namedChapters = _namedChaptersOf(item);
        _trickplay = _Trickplay.of(item);
      });

      // Start loading the skip segments now, so they're ready by the time the video is.
      final segments = _loadSegments(client, item);

      // Open directly at the saved position (or the beginning), so there's no seek afterwards.
      final resume = _resumePosition(item);
      await _player.open(
        Media(
          jellyfin.streamUrl(item.id),
          httpHeaders: jellyfin.authHeaders,
          start: resume > Duration.zero ? resume : null,
        ),
      );

      final loaded = await segments;
      if (mounted) setState(() => _segments = loaded);

      _reporter = PlaybackReporter(
        client: client,
        itemId: item.id,
        player: _player,
      )..start();
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = describeJellyfinError(e));
    } on StateError {
      if (mounted) setState(() => _error = "This item couldn't be found.");
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _scrubCommit?.cancel();
    _ratingTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }

    final item = _item;
    final reporter = _reporter;
    if (reporter != null) {
      // Report where playback stopped, then let Home and detail pages refresh their progress.
      final ids = {
        widget.itemId,
        item?.raw['SeriesId'],
        item?.raw['SeasonId'],
      }.whereType<String>();
      unawaited(
        reporter.stop().then((_) {
          clearHomeCache();
          appCache.invalidateWhere(
            (key) => ids.any((id) => key.endsWith(':$id')),
          );
        }),
      );
    }

    _player.dispose();
    _focus.dispose();
    for (final node in _allButtons) {
      node.dispose();
    }
    _seekNode.dispose();
    _skipNode.dispose();
    AppOrientation.menus();
    super.dispose();
  }

  // ── Controls visibility ──

  void _showControls({bool autoHide = true}) {
    if (!_controlsVisible) _setControlsVisible(true);
    autoHide ? _scheduleHide() : _hideTimer?.cancel();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted && _player.state.playing && _scrub == null) _setControlsVisible(false);
    });
  }

  void _toggleControls() =>
      _controlsVisible ? _setControlsVisible(false) : _showControls();

  // ── Rating intro ──

  /// Slides the age rating in once, shortly after playback first starts, then away again.
  void _introduceRating() {
    final rating = _item?.raw['OfficialRating'] as String?;
    if (_ratingShown || rating == null || rating.isEmpty) return;
    _ratingShown = true;
    _ratingTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() => _ratingVisible = true);
      _ratingTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _ratingVisible = false);
      });
    });
  }

  // ── Actions ──

  void _playOrPause() {
    _player.playOrPause();
    _showControls();
  }

  void _seekTo(Duration target) {
    final duration = _player.state.duration;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    _player.seek(target);
    _showControls();
  }

  /// Jumps to the next chapter, or 10 seconds ahead when there are no chapters.
  void _nextChapter() {
    final position = _player.state.position;
    if (_chapters.isEmpty) return _seekTo(position + _fallbackSkip);
    final next = _chapters
        .where((c) => c > position + const Duration(seconds: 1))
        .firstOrNull;
    if (next != null) _seekTo(next);
  }

  void _updateActiveSegment(Duration position) {
    final active = _segments.where((s) => s.contains(position)).firstOrNull;
    if (identical(active, _activeSegment)) return;

    final appeared = _activeSegment == null && active != null;
    final hadFocus = _skipNode.hasFocus;
    setState(() => _activeSegment = active);

    if (appeared) {
      // A skip button just appeared: select it, so Select presses it right away.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _activeSegment != null) _skipNode.requestFocus();
      });
    } else if (active == null && hadFocus) {
      _focus.requestFocus(); // the button has gone: back to the video
    }
  }

  void _skipSegment() {
    final segment = _activeSegment;
    if (segment == null) return;
    setState(() => _activeSegment = null);
    _player.seek(segment.end);
    _focus.requestFocus(); // back to the video
  }

  /// Jumps to the start of this chapter, or to the previous one when you're already near
  /// the start (like a music player). 10 seconds back when there are no chapters.
  void _previousChapter() {
    final position = _player.state.position;
    if (_chapters.isEmpty) return _seekTo(position - _fallbackSkip);
    final earlier = _chapters
        .where((c) => c < position - const Duration(seconds: 3))
        .toList();
    _seekTo(earlier.isEmpty ? Duration.zero : earlier.last);
  }

  void _toggleFit() {
    setState(
      () => _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain,
    );
    _showControls();
  }

  Future<void> _openAudio() async {
    _showControls(autoHide: false);
    await _pickTrack(
      context,
      title: 'Audio',
      choices: _audioChoices(_player, _item),
      current: _currentAudioKey(_player),
    );
    if (mounted) _showControls();
  }

  Future<void> _openSubtitles() async {
    _showControls(autoHide: false);
    await _pickTrack(
      context,
      title: 'Subtitles',
      choices: _subtitleChoices(_player, _item),
      current: _currentSubtitleKey(_player),
    );
    if (mounted) _showControls();
  }

  /// Back while the controls are up: put them away (dropping any unfinished scrub).
  void _hideControlsNow() {
    _hideTimer?.cancel();
    _scrubCommit?.cancel();
    if (_scrub != null) setState(() => _scrub = null);
    _setControlsVisible(false);
  }

  // ── D-pad scrubbing ──

  /// Moves the preview position; steps grow the longer the button is held.
  void _scrubBy(int direction, {required bool repeat}) {
    _scrubRepeats = repeat ? _scrubRepeats + 1 : 0;
    final step = _scrubRepeats > 20
        ? const Duration(seconds: 60)
        : _scrubRepeats > 8
        ? const Duration(seconds: 30)
        : const Duration(seconds: 10);

    final duration = _player.state.duration;
    var target = (_scrub ?? _player.state.position) + step * direction;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;

    setState(() => _scrub = target);
    _showControls(autoHide: false);
    _scrubCommit?.cancel();
    _scrubCommit = Timer(
      _scrubCommitAfter,
      _commitScrub,
    ); // stop pressing: jump there
  }

  void _commitScrub() {
    _scrubCommit?.cancel();
    final target = _scrub;
    if (target == null) return;
    setState(() => _scrub = null);
    _seekTo(target);
  }

  /// Shows or hides the controls, sliding the subtitles up above them or back down.
  void _setControlsVisible(bool visible) {
    // Hiding: leave the control buttons. Back to the skip button if it's on screen,
    // otherwise to the video (so the next key scrubs, plays or pauses).
    if (!visible &&
        (_seekNode.hasFocus || _allButtons.any((n) => n.hasFocus))) {
      _activeSegment != null ? _skipNode.requestFocus() : _focus.requestFocus();
    }
    if (visible != _controlsVisible) setState(() => _controlsVisible = visible);
    _videoKey.currentState?.setSubtitleViewPadding(
      visible ? _subtitlesLifted : _subtitlesNormal,
      duration: const Duration(
        milliseconds: 200,
      ), // the same speed as the controls' fade
    );
  }

  /// Moves focus through the controls with the app's row navigation. While just watching,
  /// ↑ goes to the controls row and ↓ to Play/Pause.
  void _moveFocus(TraversalDirection direction) {
    _showControls(autoHide: _scrub == null);
    final onControl =
        _seekNode.hasPrimaryFocus ||
        _skipNode.hasPrimaryFocus ||
        _allButtons.any((n) => n.hasPrimaryFocus);
    if (!onControl) {
      if (direction == TraversalDirection.up) _audioNode.requestFocus();
      if (direction == TraversalDirection.down) _playNode.requestFocus();
      return;
    }
    moveFocus(direction);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isRepeat = event is KeyRepeatEvent;

    // ── Anywhere ──
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      // First Back hides the controls; with them hidden, Back leaves the player.
      if (!isRepeat) _controlsVisible ? _hideControlsNow() : context.pop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      if (!isRepeat) _playOrPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      _nextChapter();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      _previousChapter();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaRewind ||
        key == LogicalKeyboardKey.mediaFastForward) {
      _scrubBy(
        key == LogicalKeyboardKey.mediaRewind ? -1 : 1,
        repeat: isRepeat,
      );
      return KeyEventResult.handled;
    }

    final onButton = _allButtons.any((n) => n.hasPrimaryFocus);
    final onSkip = _skipNode.hasPrimaryFocus;

    // ── ↑ / ↓: always row by row ──
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(
        key == LogicalKeyboardKey.arrowUp
            ? TraversalDirection.up
            : TraversalDirection.down,
      );
      return KeyEventResult.handled;
    }

    // ── ← / →: along a row of buttons; otherwise (seek bar, skip button, watching) scrub ──
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final left = key == LogicalKeyboardKey.arrowLeft;
      if (onButton) {
        _moveFocus(left ? TraversalDirection.left : TraversalDirection.right);
      } else {
        _scrubBy(left ? -1 : 1, repeat: isRepeat);
      }
      return KeyEventResult.handled;
    }

    // ── Select / Enter / Space ──
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter) {
      if (onButton || onSkip) return KeyEventResult.ignored; // a focused button presses itself
      if (!isRepeat) {
        if (_scrub != null) {
          _commitScrub(); // confirms a scrub (from the seek bar or while watching)
        } else if (!_seekNode.hasPrimaryFocus && _activeSegment != null) {
          _skipSegment(); // watching, with "Skip Intro" showing
        } else {
          _playOrPause();
        }
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final rating = _item?.raw['OfficialRating'] as String?;
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;

    return PopScope(
      canPop: !_controlsVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hideControlsNow();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: _controlsVisible
              ? MouseCursor.defer
              : SystemMouseCursors.none,
          onHover: (_) => _showControls(),
          child: ColoredBox(
            color: _black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  child: Video(
                    key: _videoKey,
                    controller: _video,
                    controls: NoVideoControls,
                    fit: _fit,
                    fill: _black,
                    subtitleViewConfiguration: const SubtitleViewConfiguration(
                      style: TextStyle(
                        fontSize: 36,
                        height: 1.3,
                        color: _white,
                        shadows: [
                          Shadow(blurRadius: 6, color: Color(0xCC000000)),
                        ],
                      ),
                      padding: _subtitlesNormal,
                    ),
                  ),
                ),

                // ── Buffering ──
                StreamBuilder<bool>(
                  stream: _player.stream.buffering,
                  builder: (context, snapshot) =>
                      (snapshot.data ?? true) && _error == null
                      ? const Center(child: FCircularProgress())
                      : const SizedBox.shrink(),
                ),

// ── Everything drawn over the video: one safe area, sides only (for the camera cutout).
//    The status and navigation bars are hidden while playing, so top and bottom need none.
                Positioned.fill(
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // ── Age rating intro ──
                        if (rating != null && rating.isNotEmpty)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 200), // the same speed as the controls' fade
                            curve: Curves.easeOut,
                            left: compact ? 16 : 32,
                            // Below the logo while the controls show; up in the corner once they're hidden.
                            top: _controlsVisible ? (compact ? 110 : 140) : (compact ? 12 : 24),
                            child: _RatingIntro(rating: rating, visible: _ratingVisible),
                          ),

                        // ── Controls ──
                        AnimatedOpacity(
                          opacity: _controlsVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: IgnorePointer(
                            ignoring: !_controlsVisible,
                            child: _PlayerControls(
                              player: _player,
                              item: _item,
                              trickplay: _trickplay,
                              chapters: _namedChapters,
                              preview: _scrub ?? _dragPreview,
                              filled: _fit == BoxFit.cover,
                              hasChapters: _chapters.isNotEmpty,
                              backNode: _backNode,
                              audioNode: _audioNode,
                              subtitlesNode: _subtitlesNode,
                              fitNode: _fitNode,
                              previousNode: _previousNode,
                              playNode: _playNode,
                              nextNode: _nextNode,
                              seekNode: _seekNode,
                              onDragPreview: (position) => setState(() => _dragPreview = position),
                              onBack: () => context.pop(),
                              onPlayOrPause: _playOrPause,
                              onPreviousChapter: _previousChapter,
                              onNextChapter: _nextChapter,
                              onToggleFit: _toggleFit,
                              onAudio: _openAudio,
                              onSubtitles: _openSubtitles,
                              onInteract: _showControls,
                            ),
                          ),
                        ),

                        // ── Skip intro / credits / ... ──
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          right: compact ? 16 : 32,
                          // Above the controls when they're showing; near the corner otherwise.
                          bottom: _controlsVisible ? (compact ? 150 : 170) : (compact ? 12 : 24),
                          child: _SkipButton(
                            segment: _activeSegment,
                            onPress: _skipSegment,
                            focusNode: _skipNode,
                            selected: _skipFocused,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Errors ──
                if (_error != null)
                  ColoredBox(
                    color: _black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 12,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 40,
                            color: _white,
                          ),
                          Text(
                            "Couldn't play this",
                            style: context.theme.typography.display.lg.copyWith(
                              color: _white,
                            ),
                          ),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: context.theme.typography.body.sm.copyWith(
                              color: const Color(0xB3FFFFFF),
                            ),
                          ),
                          FButton(
                            mainAxisSize: .min,
                            onPress: () => context.pop(),
                            child: const Text('Go back'),
                          ),
                        ],
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

// ─── Helpers ─────────────────────────────────────────────────────────────────

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

/// "1:02:03" or "4:05".
String _formatTime(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// "4:52 am".
String _formatClock(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$hour:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

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
                              _formatTime(position),
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
  if (RegExp(r'\b(preview|next time|next episode)\b').hasMatch(n)) return _SegmentKind.preview; return null;
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
    for (final s in result.items) {
      debugPrint('  ${s.type}: ${s.start} → ${s.end}');
    }
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

  @override
  Widget build(BuildContext context) {
    final previewChapter = preview == null ? null : _chapterAt(chapters, preview!);
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Darkens the top and bottom so the controls read on any frame.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.2, 0.5, 1.0],
              colors: [
                Color(0xB3000000),
                Color(0x00000000),
                Color(0x00000000),
                Color(0xE6000000),
              ],
            ),
          ),
        ),

// ── Top: back and logo ──
        Positioned(
          top: compact ? 8 : 12,
          left: compact ? 8 : 12,
          right: compact ? 8 : 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center, // the back arrow sits level with the middle of the title block
            spacing: 8,
            children: [
              _ControlButton(
                focusNode: backNode,
                icon: Icons.arrow_back_ios_new_rounded,
                label: 'Back',
                onPress: onBack,
              ),
              if (item != null) Flexible(child: _PlayerTitle(item: item!)),
            ],
          ),
        ),

        // ── Bottom: heading, seek bar, times, transport ──
        Positioned(
          left: compact ? 16 : 32,
          right: compact ? 16 : 32,
          bottom: compact ? 4 : 12,
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
                      onPress: onAudio,
                    ),
                    _ControlButton(
                      focusNode: subtitlesNode,
                      icon: Icons.subtitles_rounded,
                      label: 'Subtitles',
                      onPress: onSubtitles,
                    ),
                    _ControlButton(
                      focusNode: fitNode,
                      icon: filled
                          ? Icons.zoom_in_map_rounded
                          : Icons.zoom_out_map_rounded,
                      label: filled ? 'Fit to screen' : 'Fill screen',
                      onPress: onToggleFit,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 4),
              FocusRow(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 24,
                  children: [
                    _ControlButton(
                      focusNode: previousNode,
                      icon: Icons.skip_previous_rounded,
                      label: hasChapters
                          ? 'Previous chapter'
                          : 'Back 10 seconds',
                      size: 28,
                      onPress: onPreviousChapter,
                    ),
                    StreamBuilder<bool>(
                      stream: player.stream.playing,
                      initialData: player.state.playing,
                      builder: (context, snapshot) => _ControlButton(
                        focusNode: playNode,
                        icon: snapshot.data!
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        label: snapshot.data! ? 'Pause' : 'Play',
                        size: 32,
                        onPress: onPlayOrPause,
                      ),
                    ),
                    _ControlButton(
                      focusNode: nextNode,
                      icon: Icons.skip_next_rounded,
                      label: hasChapters
                          ? 'Next chapter'
                          : 'Forward 10 seconds',
                      size: 28,
                      onPress: onNextChapter,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
        final focused = states.contains(FTappableVariant.focused);
        final hovered = states.contains(FTappableVariant.hovered);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Focused (remote or keyboard) or hovered: the same soft translucent circle.
            color: focused || hovered
                ? const Color(0x33FFFFFF)
                : const Color(0x00FFFFFF),
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

    final String? details;
    if (isEpisode) {
      final season = item.raw['ParentIndexNumber'];
      final episode = item.raw['IndexNumber'];
      details = [
        if (season != null && episode != null) 'S$season:E$episode',
        item.name,
      ].join(' · ');
    } else {
      details = item.raw['ProductionYear']?.toString();
    }

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
                ? _formatTime(position)
                : '${_formatTime(position)}  ·  $chapter',
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
            '-${_formatTime(remaining)}  /  ${_formatClock(endsAt)}',
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
    widget.player.seek(duration * fraction.clamp(0.0, 1.0));
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
      final handle = preview != null || _focused ? 18.0 : 14.0;

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
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none, // the preview rises above the bar
                  alignment: Alignment.centerLeft,
                  children: [
                    _bar(width, const Color(0x40FFFFFF)),
                    _bar(width * buffered, const Color(0x66FFFFFF)),
                    _bar(x, _white),
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
                          bottom: 36,
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

  Widget _bar(double width, Color color) => Container(
    width: width,
    height: 4,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

// ─── Audio and subtitle choices ──────────────────────────────────────────────

/// One audio or subtitle option: a stable key, what it's called, and how to switch to it.
typedef _TrackChoice = ({
  String key,
  String label,
  Future<void> Function() select,
});

/// mpv's built-in "auto" and "no" choices aren't real tracks.
bool _isRealTrack(String id) => id != 'auto' && id != 'no';

/// The file's streams of one type, as Jellyfin describes them, in file order.
List<Map<String, dynamic>> _streamsOf(
  JellyfinItem? item,
  String type, {
  required bool external,
}) {
  final raw = item?.raw;
  final source = (raw?['MediaSources'] as List?)?.firstOrNull as Map?;
  final streams =
      (source?['MediaStreams'] as List?) ??
      (raw?['MediaStreams'] as List?) ??
      const [];
  return [
    for (final s in streams)
      if (s is Map<String, dynamic> &&
          s['Type'] == type &&
          (s['IsExternal'] == true) == external)
        s,
  ]..sort(
    (a, b) => ((a['Index'] as int?) ?? 0).compareTo((b['Index'] as int?) ?? 0),
  );
}

/// Jellyfin's description of the n-th track of a kind ("English - AAC - Stereo - Default"),
/// or mpv's own title and language if Jellyfin has none.
String _trackLabel(
  List<Map<String, dynamic>> streams,
  int index,
  String id,
  String? title,
  String? language,
) {
  if (index < streams.length) {
    final display = streams[index]['DisplayTitle'] as String?;
    if (display != null && display.isNotEmpty) return display;
  }
  final parts = [
    title,
    language?.toUpperCase(),
  ].whereType<String>().where((s) => s.isNotEmpty);
  return parts.isEmpty ? 'Track $id' : parts.join(' · ');
}

/// Where to fetch an external subtitle file from the server, or null if it can't be fetched
/// on its own (picture-based subtitles like PGS).
String? _externalSubtitleUrl(JellyfinItem? item, Map<String, dynamic> stream) {
  final client = jellyfin.client;
  if (client == null || item == null || stream['IsTextSubtitleStream'] == false) return null;
  final ext = switch ((stream['Codec'] as String?)?.toLowerCase()) {
    'ass' || 'ssa' => 'ass',
    'webvtt' || 'vtt' => 'vtt',
    _ => 'srt',
  };
  final source = (item.raw['MediaSources'] as List?)?.firstOrNull as Map?;
  final sourceId = (source?['Id'] as String?) ?? item.id;
  return '${client.baseUrl}/Videos/${item.id}/$sourceId/Subtitles/${stream['Index']}/0/Stream.$ext'
      '?api_key=${client.token}';
}

List<_TrackChoice> _audioChoices(Player player, JellyfinItem? item) {
  final streams = _streamsOf(item, 'Audio', external: false);
  final tracks = player.state.tracks.audio
      .where((t) => _isRealTrack(t.id))
      .toList();
  return [
    for (final (i, t) in tracks.indexed)
      (
        key: 'audio:${t.id}',
        label: _trackLabel(streams, i, t.id, t.title, t.language),
        select: () => player.setAudioTrack(t),
      ),
  ];
}

List<_TrackChoice> _subtitleChoices(Player player, JellyfinItem? item) {
  final streams = _streamsOf(item, 'Subtitle', external: false);
  final external = _streamsOf(item, 'Subtitle', external: true);
  final tracks = player.state.tracks.subtitle
      .where((t) => _isRealTrack(t.id))
      .toList();
  // Subtitles mpv found in the file. Any beyond Jellyfin's count were added from the
  // server (below), so they're listed there instead of twice.
  final embedded = streams.isEmpty
      ? tracks
      : tracks.take(streams.length).toList();

  return [
    (
      key: 'off',
      label: 'Off',
      select: () => player.setSubtitleTrack(SubtitleTrack.no()),
    ),
    for (final (i, t) in embedded.indexed)
      (
        key: 'sub:${t.id}',
        label: _trackLabel(streams, i, t.id, t.title, t.language),
        select: () => player.setSubtitleTrack(t),
      ),
    for (final s in external)
      if (_externalSubtitleUrl(item, s) case final url?)
        (
          key: url, // an external track's id is its address
          label: (s['DisplayTitle'] as String?) ?? 'External subtitles',
          select: () => player.setSubtitleTrack(
            SubtitleTrack.uri(
              url,
              title: s['DisplayTitle'] as String?,
              language: s['Language'] as String?,
            ),
          ),
        ),
  ];
}

/// The keys of the current choices, matching the keys above.
String _currentAudioKey(Player player) =>
    'audio:${player.state.track.audio.id}';

String _currentSubtitleKey(Player player) {
  final id = player.state.track.subtitle.id;
  if (!_isRealTrack(id)) return 'off';
  return id.startsWith('http') ? id : 'sub:$id';
}

/// Shows [choices] in the app's standard choice picker and applies the one picked.
Future<void> _pickTrack(
  BuildContext context, {
  required String title,
  required List<_TrackChoice> choices,
  required String current,
}) async {
  if (choices.isEmpty) return;
  final key = await showChoicePicker<String>(
    context: context,
    title: title,
    selected: current,
    search: (_) async => [for (final c in choices) c.key],
    itemBuilder: (context, key) => Text(
      choices.firstWhere((c) => c.key == key).label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
  if (key != null) await choices.firstWhere((c) => c.key == key).select();
}
