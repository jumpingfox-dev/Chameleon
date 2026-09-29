import 'dart:async';
import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:forui_phosphor/forui_phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../utils/app_cache.dart';
import '../utils/jellyfin_controller.dart';
import '../utils/orientation.dart';
import '../utils/playback_reporter.dart';
import '../widgets/home_modules.dart';

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);

/// Full-screen playback of a movie or episode.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.itemId});

  final String itemId;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _hideAfter = Duration(seconds: 3);
  static const _seekStep = Duration(seconds: 10);

  final _player = Player();
  late final _video = VideoController(_player);
  final _focus = FocusNode();
  final _subscriptions = <StreamSubscription<Object?>>[];

  JellyfinItem? _item;
  String? _error;
  PlaybackReporter? _reporter;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    AppOrientation.player(); // landscape and immersive on phones
    _subscriptions
      ..add(_player.stream.error.listen((message) {
        // Only treat it as fatal if nothing has loaded; mpv also reports minor stream hiccups.
        if (mounted && _player.state.duration == Duration.zero) setState(() => _error = message);
      }))
    // Controls stay up while paused, and fade out again once playing.
      ..add(_player.stream.playing.listen((playing) => playing ? _scheduleHide() : _showControls(autoHide: false)));
    _start();
  }

  Future<void> _start() async {
    final client = jellyfin.client;
    if (client == null) return;
    try {
      final item = await client.items.byId(widget.itemId);
      if (item == null) throw StateError('Not found');
      if (!mounted) return;
      setState(() => _item = item);

      await _player.open(
        Media(jellyfin.streamUrl(item.id), httpHeaders: jellyfin.authHeaders),
        play: false,
      );

      // Resume where you left off, once the file's length is known.
      final resume = _resumePosition(item);
      if (resume > Duration.zero) {
        await _player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 15), onTimeout: () => Duration.zero);
        await _player.seek(resume);
      }

      await _player.play();
      _reporter = PlaybackReporter(client: client, itemId: item.id, player: _player)..start();
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = describeJellyfinError(e));
    } on StateError {
      if (mounted) setState(() => _error = "This item couldn't be found.");
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }

    final item = _item;
    final reporter = _reporter;
    if (reporter != null) {
      // Report where playback stopped, then let Home and detail pages refresh their progress.
      final ids = {widget.itemId, item?.raw['SeriesId'], item?.raw['SeasonId']}.whereType<String>();
      unawaited(reporter.stop().then((_) {
        clearHomeCache();
        appCache.invalidateWhere((key) => ids.any((id) => key.endsWith(':$id')));
      }));
    }

    _player.dispose();
    _focus.dispose();
    AppOrientation.menus();
    super.dispose();
  }

  // ── Controls visibility ──

  void _showControls({bool autoHide = true}) {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    autoHide ? _scheduleHide() : _hideTimer?.cancel();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted && _player.state.playing) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() => _controlsVisible ? setState(() => _controlsVisible = false) : _showControls();

  // ── Actions ──

  void _playOrPause() {
    _player.playOrPause();
    _showControls();
  }

  void _seekBy(Duration offset) {
    final duration = _player.state.duration;
    var target = _player.state.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    _player.seek(target);
    _showControls();
  }

  Future<void> _openTracks() async {
    _showControls(autoHide: false);
    await _showTrackPicker(context, _player);
    if (mounted) _showControls();
  }

  // ── Keyboard and remote ──

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (event is KeyDownEvent) _playOrPause(); // ignore key-repeat so holding it doesn't flicker
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-_seekStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(_seekStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      context.pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: _onKey,
    child: MouseRegion(
      cursor: _controlsVisible ? MouseCursor.defer : SystemMouseCursors.none, // hide the pointer with the controls
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
                controller: _video,
                controls: NoVideoControls, // our own controls below
                fill: _black,
                subtitleViewConfiguration: const SubtitleViewConfiguration(
                  style: TextStyle(
                    fontSize: 36,
                    height: 1.3,
                    color: _white,
                    shadows: [Shadow(blurRadius: 6, color: Color(0xCC000000))],
                  ),
                  padding: EdgeInsets.fromLTRB(48, 0, 48, 48),
                ),
              ),
            ),

            // ── Buffering ──
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
              builder: (context, snapshot) => (snapshot.data ?? true) && _error == null
                  ? const Center(child: FCircularProgress())
                  : const SizedBox.shrink(),
            ),

            // ── Controls ──
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: _PlayerControls(
                  player: _player,
                  title: _item == null ? '' : _titleFor(_item!),
                  onBack: () => context.pop(),
                  onPlayOrPause: _playOrPause,
                  onSeekBy: _seekBy,
                  onTracks: _openTracks,
                  onInteract: _showControls,
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
                      const Icon(FPhosphorIcons.warningCircle, size: 40, color: _white),
                      Text("Couldn't play this", style: context.theme.typography.display.lg.copyWith(color: _white)),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: context.theme.typography.body.sm.copyWith(color: const Color(0xB3FFFFFF)),
                      ),
                      FButton(mainAxisSize: .min, onPress: () => context.pop(), child: const Text('Go back')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Where to start: the saved position, unless the item was finished.
Duration _resumePosition(JellyfinItem item) {
  final userData = item.raw['UserData'] as Map?;
  final ticks = userData?['PlaybackPositionTicks'];
  if (ticks is! int || ticks <= 0 || userData?['Played'] == true) return Duration.zero;
  return Duration(microseconds: ticks ~/ 10);
}

/// "Breaking Bad — S1:E2 · Cat's in the Bag..." for episodes, the name for everything else.
String _titleFor(JellyfinItem item) {
  if (item.type != JellyfinItemKind.episode) return item.name;
  final series = item.raw['SeriesName'] as String?;
  final season = item.raw['ParentIndexNumber'];
  final episode = item.raw['IndexNumber'];
  final code = season != null && episode != null ? 'S$season:E$episode · ' : '';
  return series == null ? '$code${item.name}' : '$series — $code${item.name}';
}

/// "1:02:03" or "4:05".
String _formatTime(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

// ─── Controls ────────────────────────────────────────────────────────────────

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({
    required this.player,
    required this.title,
    required this.onBack,
    required this.onPlayOrPause,
    required this.onSeekBy,
    required this.onTracks,
    required this.onInteract,
  });

  final Player player;
  final String title;
  final VoidCallback onBack;
  final VoidCallback onPlayOrPause;
  final void Function(Duration) onSeekBy;
  final VoidCallback onTracks;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // Darkens the top and bottom so the controls read on any frame.
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.25, 0.65, 1.0],
            colors: [Color(0xB3000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
          ),
        ),
      ),

      // ── Top: back and title ──
      Positioned(
        top: 16,
        left: 16,
        right: 16,
        child: SafeArea(
          child: Row(
            spacing: 12,
            children: [
              _RoundButton(icon: FPhosphorIcons.arrowLeft, label: 'Back', onPress: onBack),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.display.lg.copyWith(color: _white),
                ),
              ),
            ],
          ),
        ),
      ),

      // ── Middle: back 10s, play/pause, forward 10s ──
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 32,
          children: [
            _RoundButton(
              icon: FPhosphorIcons.clockCounterClockwise,
              label: 'Back 10 seconds',
              onPress: () => onSeekBy(const Duration(seconds: -10)),
            ),
            StreamBuilder<bool>(
              stream: player.stream.playing,
              initialData: player.state.playing,
              builder: (context, snapshot) => _RoundButton(
                icon: snapshot.data! ? FPhosphorIcons.pause : FPhosphorIcons.play,
                label: snapshot.data! ? 'Pause' : 'Play',
                size: 72,
                onPress: onPlayOrPause,
              ),
            ),
            _RoundButton(
              icon: FPhosphorIcons.clockClockwise,
              label: 'Forward 10 seconds',
              onPress: () => onSeekBy(const Duration(seconds: 10)),
            ),
          ],
        ),
      ),

      // ── Bottom: seek bar, times, tracks ──
      Positioned(
        left: 24,
        right: 24,
        bottom: 16,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              _SeekBar(player: player, onInteract: onInteract),
              Row(
                children: [
                  StreamBuilder<Duration>(
                    stream: player.stream.position,
                    builder: (context, _) {
                      final position = player.state.position;
                      final duration = player.state.duration;
                      final style = context.theme.typography.body.sm.copyWith(color: const Color(0xE6FFFFFF));
                      return Text('${_formatTime(position)} / ${_formatTime(duration)}', style: style);
                    },
                  ),
                  const Spacer(),
                  _RoundButton(icon: FPhosphorIcons.subtitles, label: 'Audio and subtitles', size: 44, onPress: onTracks),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// A white icon on a translucent dark circle.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onPress, this.size = 52});

  final IconData icon;
  final String label;
  final VoidCallback onPress;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: FTappable(
      onPress: onPress,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x59000000)),
        child: Icon(icon, size: size * 0.45, color: _white),
      ),
    ),
  );
}

/// The seek bar: buffered range, played range and a handle. Tap or drag to seek.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player, required this.onInteract});

  final Player player;
  final VoidCallback onInteract;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragFraction; // while dragging, where the handle is (0–1)

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
      double fractionOf(Duration d) => total == 0 ? 0 : (d.inMilliseconds / total).clamp(0.0, 1.0);

      final played = _dragFraction ?? fractionOf(state.position);
      final buffered = fractionOf(state.buffer);
      final primary = context.theme.colors.primary;

      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          double fractionAt(double dx) => (dx / width).clamp(0.0, 1.0);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              widget.onInteract();
              _seekToFraction(fractionAt(details.localPosition.dx));
            },
            onHorizontalDragStart: (details) {
              widget.onInteract();
              setState(() => _dragFraction = fractionAt(details.localPosition.dx));
            },
            onHorizontalDragUpdate: (details) {
              widget.onInteract();
              setState(() => _dragFraction = fractionAt(details.localPosition.dx));
            },
            onHorizontalDragEnd: (_) {
              if (_dragFraction != null) _seekToFraction(_dragFraction!);
              setState(() => _dragFraction = null);
            },
            child: SizedBox(
              height: 28, // a comfortable touch target around the 4px line
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  _bar(width, const Color(0x40FFFFFF)),
                  _bar(width * buffered, const Color(0x66FFFFFF)),
                  _bar(width * played, primary),
                  Positioned(
                    left: math.max(0, width * played - 7),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                    ),
                  ),
                ],
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
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
  );
}

// ─── Audio and subtitle picker ───────────────────────────────────────────────

Future<void> _showTrackPicker(BuildContext context, Player player) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: const Color(0x99000000),
  transitionDuration: const Duration(milliseconds: 150),
  pageBuilder: (context, _, _) => Center(child: _TrackPicker(player: player)),
  transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
);

class _TrackPicker extends StatelessWidget {
  const _TrackPicker({required this.player});

  final Player player;

  /// "English · ENG", or "Track 2" when a track has no name or language.
  static String _label(String id, String? title, String? language) {
    final parts = [title, language?.toUpperCase()].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? 'Track $id' : parts.join(' · ');
  }

  /// Leaves out mpv's built-in "auto" and "no" choices, which aren't real tracks.
  static bool _isReal(String id) => id != 'auto' && id != 'no';

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return SizedBox(
      width: math.min(420, size.width - 32),
      height: math.min(520, size.height * 0.85),
      child: FCard(
        builder: (context, style, _) => Padding(
          padding: style.padding,
          child: StreamBuilder<Track>(
            stream: player.stream.track,
            initialData: player.state.track,
            builder: (context, snapshot) {
              final current = snapshot.data!;
              final tracks = player.state.tracks;
              final audio = tracks.audio.where((t) => _isReal(t.id)).toList();
              final subtitles = tracks.subtitle.where((t) => _isReal(t.id)).toList();

              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  Text('Audio', style: context.theme.typography.display.lg),
                  const SizedBox(height: 8),
                  if (audio.isEmpty) const _TrackOption(label: 'Default', selected: true),
                  for (final t in audio)
                    _TrackOption(
                      label: _label(t.id, t.title, t.language),
                      selected: t.id == current.audio.id,
                      onPress: () => player.setAudioTrack(t),
                    ),
                  const SizedBox(height: 16),
                  Text('Subtitles', style: context.theme.typography.display.lg),
                  const SizedBox(height: 8),
                  _TrackOption(
                    label: 'Off',
                    selected: current.subtitle.id == 'no',
                    onPress: () => player.setSubtitleTrack(SubtitleTrack.no()),
                  ),
                  for (final t in subtitles)
                    _TrackOption(
                      label: _label(t.id, t.title, t.language),
                      selected: t.id == current.subtitle.id,
                      onPress: () => player.setSubtitleTrack(t),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One choice in the track picker, with a check next to the selected one.
class _TrackOption extends StatelessWidget {
  const _TrackOption({required this.label, required this.selected, this.onPress});

  final String label;
  final bool selected;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) => FButton(
    variant: .ghost,
    mainAxisAlignment: .start,
    onPress: onPress ?? () {},
    child: Row(
      spacing: 12,
      children: [
        SizedBox(
          width: 18,
          child: selected ? Icon(FPhosphorIcons.check, size: 18, color: context.theme.colors.primary) : null,
        ),
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}