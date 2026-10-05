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
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;

import '../theme/tappable_states.dart';
import '../utils/app_cache.dart';
import '../utils/cast_controller.dart';
import '../utils/focus_rows.dart';
import '../utils/format.dart';
import '../utils/item_format.dart';
import '../utils/jellyfin_controller.dart';
import '../utils/orientation.dart';
import '../utils/playback_reporter.dart';
import '../utils/playback_settings.dart';
import '../utils/sync_play_controller.dart';
import '../widgets/cast_widgets.dart';
import '../widgets/choice_picker.dart';
import '../widgets/home_modules.dart';

part 'player_controls.dart';
part 'player_segments.dart';
part 'player_tracks.dart';

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);
const _dimWhite = Color(0xCCFFFFFF);

/// Full-screen playback of a movie or episode.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.itemId, this.queue = const [], this.fromGroup = false});

  final String itemId;

  /// Opened by a Watch Together group (someone else started it), rather than from this device.
  final bool fromGroup;

  /// Item ids to play through, in order (a collection, or a shuffle of one). When set,
  /// Up Next plays the next id here instead of the next episode.
  final List<String> queue;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _hideAfter = Duration(seconds: 3);
  static const _scrubCommitAfter = Duration(milliseconds: 1500);

  /// How far left/right, double-tap and (without chapters) previous/next jump. Set in Settings.
  Duration get _step => Duration(seconds: playbackSettings.seekStep);

  /// The item playing. Starts as the one opened, and changes when the next episode plays.
  late String _itemId = widget.itemId;

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
  final _upNextNode = FocusNode(debugLabel: 'Up next: play now');
  final _upNextScope = FocusNode(debugLabel: 'Up next', skipTraversal: true, canRequestFocus: false);

  List<FocusNode> get _optionRow => [_audioNode, _subtitlesNode, _fitNode];
  List<FocusNode> get _transportRow => [_previousNode, _playNode, _nextNode];
  List<FocusNode> get _allButtons => [
    _backNode,
    ..._optionRow,
    ..._transportRow,
  ];

  /// How far the subtitles stretch and when to wrap the text: [_subtitleSides]
  /// of the width in from each side.
  static const _subtitleSides = 0.06;

  /// While the controls show, subtitles move up above the seek bar and buttons. Those are a
  /// fixed size, so this is in pixels: at least this far from the bottom.
  static const _controlsClearance = 150.0;
  static const _controlsClearancePhone = 146.0;

  bool get _isPhone => isPhoneLayout(context);

  EdgeInsets _subtitlePadding({required bool lifted}) {
    lifted = lifted && playbackSettings.liftSubtitles; // "Move up when controls show" in Settings
    final size = MediaQuery.sizeOf(context);
    final raise = size.height * playbackSettings.subtitlePosition.raise;
    final clearance = _isPhone ? _controlsClearancePhone : _controlsClearance;
    final sides = size.width * _subtitleSides;
    return EdgeInsets.fromLTRB(sides, 0, sides, lifted ? math.max(raise, clearance) : raise);
  }

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

  /// Segments already skipped automatically. Seeking back into one shows the button instead,
  /// so you can rewatch an intro without being thrown out of it again.
  final _autoSkipped = <_Segment>{};

  /// "Skipped intro" and the like, shown briefly after an automatic skip.
  String? _notice;
  Timer? _noticeTimer;

  /// Up next: the episode after this one (episodes only), and the countdown card.
  _NextEpisode? _next;
  bool _upNextShown = false; // the card has appeared for this episode
  bool _upNextDismissed = false; // Cancel was pressed: this episode just ends
  bool _stillWatching = false; // the card asks "Are you still watching?" instead of counting down
  int _countdown = 0;
  Timer? _countdownTimer;

  /// Set while the server converts the video (to stay under the quality limit, or because
  /// Settings says to always convert); null while playing the file directly.
  _Transcode? _transcode;

  /// Thumbnail sheets for scrubbing, if the server has generated them.
  _Trickplay? _trickplay;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// Fit shows the whole picture (with bars if the shape differs from the screen);
  /// fill zooms in to cover the screen, trimming the edges.
  BoxFit _fit = playbackSettings.aspect == AspectMode.fill ? BoxFit.cover : BoxFit.contain;

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

  /// Double-tap to seek (phones). Two quick taps on the left or right third jump one step
  /// (10 seconds unless changed in Settings); each further tap on that side adds another step.
  static const _doubleTapWindow = Duration(milliseconds: 300);
  Timer? _singleTapTimer; // a single tap waits this long in case a second one follows
  DateTime? _lastTapAt;
  int _lastTapSide = 0; // -1 left third, 0 middle, 1 right third
  ({int side, int seconds})? _tapSeek; // what the on-screen indicator shows (kept while it fades)
  bool _tapSeekVisible = false; // true during a run of taps
  Duration _tapSeekFrom = Duration.zero; // where the current run of taps started
  Timer? _tapSeekEnd;

  // ── Watch Together (SyncPlay) ──

  /// In a group: play, pause and seek go through the group, so everyone does them together.
  /// (Not while casting: the Chromecast plays on its own.)
  bool get _inGroup => syncPlay.inGroup && !_casting;

  /// The group already knows about what's playing (it started it, or this device told it).
  late bool _groupDriven = widget.fromGroup;

  StreamSubscription<SyncPlayCommand>? _groupCommands;
  Timer? _groupTimer; // a pause or unpause scheduled for the group's moment
  bool? _reportedBuffering; // what the group was last told: loading (true) or ready (false)

  /// True briefly while seeking because the group said to. The short buffer a seek causes
  /// isn't reported, or the group would pause everyone, resume, seek again … forever.
  bool _groupSeeking = false;

  /// Casting: the video plays on a Chromecast and this screen becomes its remote.
  bool _casting = false;
  bool _castLoaded = false; // the Chromecast has been sent the video
  bool _localOpened = false; // the video has been opened on this device

  @override
  void initState() {
    super.initState();
    // Full screen, sideways: most things played are movies and episodes. Other videos
    // (home videos and the like) are let free to turn once the item has loaded.
    _holdTo(AppOrientation.landscape);
    _followTilt();
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
    // Finished (including after skipping end credits): the next episode, or back to where you were.
      ..add(_player.stream.completed.listen(_onCompleted));
    _skipNode.addListener(() {
      final focused = _skipNode.hasFocus;
      if (focused != _skipFocused && mounted) setState(() => _skipFocused = focused);
    });
    castController.addListener(_onCastChanged);
    // Watch Together: the group can switch what's playing, and tells everyone when to
    // pause, play and seek. Loading pauses the group until this device catches up.
    syncPlay.attach(_onGroupSwitch);
    _groupCommands = syncPlay.commands.listen(_onGroupCommand);
    _subscriptions.add(_player.stream.buffering.listen(_reportBuffering));
    _audioReady = _applyAudioSettings();
    _start();
  }

  /// Passthrough, stereo downmix and night mode, from Settings. Set before the first video opens.
  late final Future<void> _audioReady;

  Future<void> _applyAudioSettings() async {
    // mpv's own options, set straight on it (media_kit doesn't wrap these).
    final dynamic mpv = _player.platform;
    if (mpv == null) return;
    final s = playbackSettings;
    try {
      // Passthrough: hand Dolby and DTS to the receiver as they are, undecoded.
      await mpv.setProperty('audio-spdif', s.passthrough ? 'ac3,eac3,dts,dts-hd,truehd' : '');
      await mpv.setProperty('audio-channels', s.passthrough ? 'auto' : (s.downmix ? 'stereo' : 'auto-safe'));
      // Night mode: a gentle compressor that lowers loud peaks and lifts quiet parts.
      await mpv.setProperty(
        'af',
        !s.passthrough && s.nightMode
            ? 'lavfi=[acompressor=threshold=0.1:ratio=4:attack=10:release=250:makeup=2.5]'
            : '',
      );
    } catch (e) {
      debugPrint('Audio settings: $e');
    }
  }

  Future<void> _start() async {
    final client = jellyfin.client;
    if (client == null) return;
    final id = _itemId;
    try {
      final item = await client.items.byId(id);
      if (item == null) throw StateError('Not found');
      if (!mounted || id != _itemId) return;
      setState(() {
        _item = item;
        _chapters = _chaptersOf(item);
        _namedChapters = _namedChaptersOf(item);
        _trickplay = playbackSettings.trickplay ? _Trickplay.of(item) : null;
      });
      // Movies and episodes stay sideways until the phone has been turned sideways once.
      // Anything else follows the phone straight away.
      final isFilmOrShow = item.type == JellyfinItemKind.movie || item.type == JellyfinItemKind.episode;
      if (!isFilmOrShow) _turnedSideways = true;

      // The episode after this one, for Up Next. Loads alongside the video.
      unawaited(
        _fetchNext(item).then((next) {
          if (mounted && id == _itemId) setState(() => _next = next);
        }),
      );

      // Where to start: where the group is, or by the Resuming setting.
      var start = _resumePosition(item);
      // (Not when a Chromecast is connected: casting plays outside the group.)
      if (_inGroup && !castController.isConnected) {
        if (_groupDriven) {
          start = syncPlay.startPosition;
        } else {
          // Started here: make it what the whole group watches (the rest of a collection too).
          final from = widget.queue.indexOf(id);
          final ids = from == -1 ? [id] : widget.queue.sublist(from);
          _groupDriven = true;
          unawaited(syncPlay.play(ids, start: start));
        }
      } else if (start > Duration.zero) {
        switch (playbackSettings.resume) {
          case ResumeMode.resume:
            break;
          case ResumeMode.startOver:
            start = Duration.zero;
          case ResumeMode.ask:
            final resume = await _askResume(item, start);
            if (!mounted || id != _itemId) return;
            if (resume == null) {
              context.pop(); // backed out of the question: leave the player
              return;
            }
            if (!resume) start = Duration.zero;
        }
      }

      // Already connected to a Chromecast: play it there, not here.
      if (castController.isConnected) {
        await _castItem(item, start: start);
      } else {
        await _openLocal(client, item, start);
      }
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = describeJellyfinError(e));
    } on StateError {
      if (mounted) setState(() => _error = "This item couldn't be found.");
    }
  }

  /// In a group, the group's own queue decides what's next, so there's no Up Next card.
  Future<_NextEpisode?> _fetchNext(JellyfinItem item) =>
      _inGroup ? Future.value(null) : _fetchNextIn(item, widget.queue);

  /// "Resume from 12:34" or "Start from the beginning". Null if dismissed with Back.
  Future<bool?> _askResume(JellyfinItem item, Duration at) => showFDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 10,
          children: [
            Text('Pick up where you left off?', style: context.theme.typography.display.lg),
            Text(
              item.name,
              style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground),
            ),
            const SizedBox(height: 4),
            FButton(
              autofocus: true,
              onPress: () => Navigator.of(context).pop(true),
              child: Text('Resume from ${formatDuration(at)}'),
            ),
            FButton(
              variant: .outline,
              onPress: () => Navigator.of(context).pop(false),
              child: const Text('Start from the beginning'),
            ),
          ],
        ),
      ),
    ),
  );

  /// Plays [item] on this device from [start]: the file as it is, or converted by the server
  /// when it's over the quality limit (or Settings says to always convert).
  Future<void> _openLocal(JellyfinClient client, JellyfinItem item, Duration start) async {
    _localOpened = true;
    // Start loading the skip segments now, so they're ready by the time the video is.
    final segments = _loadSegments(client, item);
    await _audioReady;

    final transcode = await _planTranscode(item);
    if (!mounted) return;
    _transcode = transcode;

    // Open directly at the start position, so there's no seek afterwards.
    // In a group, it waits paused until everyone has loaded; the group then starts it.
    final inGroup = _inGroup;
    await _player.open(
      Media(
        transcode?.url ?? jellyfin.streamUrl(item.id),
        httpHeaders: jellyfin.authHeaders,
        start: start > Duration.zero ? start : null,
      ),
      play: !inGroup,
    );
    if (inGroup) {
      _reportBuffering(true, force: true);
      unawaited(_waitForTracks().then((_) => _reportBuffering(false, force: true)));
    }

    unawaited(transcode == null ? _applyDefaultTracks(item) : _applyTranscodeSubtitles(item, transcode));

    final loaded = await segments;
    if (mounted) setState(() => _segments = loaded);

    _startReporter(client, item);
  }

  // ── Converting (transcoding) ──

  /// How to convert [item], or null to play the file directly. A converted stream carries one
  /// audio track and no subtitles, so the audio (and any picture subtitles, which are burned
  /// into the picture) are chosen here, from the account's language settings.
  Future<_Transcode?> _planTranscode(JellyfinItem item) async {
    final s = playbackSettings;
    if (s.streamMode == StreamMode.direct) return null;
    final limit = await s.currentMaxBitrate();
    final sourceBitrate = _sourceOf(item)?['Bitrate'];
    final overLimit = limit != null && sourceBitrate is int && sourceBitrate > limit;
    if (s.streamMode == StreamMode.auto && !overLimit) return null;

    final audioStreams = _streamsOf(item, 'Audio', external: false);
    final prefs = await _fetchTrackPrefs();
    final a = prefs == null ? null : _pickAudio(audioStreams, prefs);
    final audio = a != null
        ? audioStreams[a]
        : (audioStreams.where((x) => x['IsDefault'] == true).firstOrNull ?? audioStreams.firstOrNull);

    int? burnIn;
    if (prefs != null) {
      final subtitle = _pickSubtitle(_allSubtitles(item), prefs, audio?['Language'] as String?);
      if (subtitle != null && subtitle['IsTextSubtitleStream'] == false) burnIn = subtitle['Index'] as int?;
    }
    return _Transcode.build(item, audioIndex: audio?['Index'] as int?, burnIn: burnIn, maxBitrate: limit);
  }

  /// While converting: text subtitles come from the server as separate files.
  Future<void> _applyTranscodeSubtitles(JellyfinItem item, _Transcode transcode) async {
    if (transcode.burnIn != null) return; // picture subtitles are already in the picture
    final prefs = await _fetchTrackPrefs();
    if (prefs == null || !mounted) return;
    final audio = _streamsOf(item, 'Audio', external: false)
        .where((s) => s['Index'] == transcode.audioIndex)
        .firstOrNull;
    final pick = _pickSubtitle(_allSubtitles(item), prefs, audio?['Language'] as String?);
    if (pick == null) return;
    final url = _externalSubtitleUrl(item, pick);
    if (url == null) return;
    await _waitForTracks();
    if (!mounted) return;
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(url, title: pick['DisplayTitle'] as String?, language: pick['Language'] as String?),
    );
  }

  /// Reopens the converted stream with another audio track or burned-in subtitles,
  /// carrying on from the same spot. Text subtitles that were showing stay on.
  Future<void> _reopenTranscode({required int? audioIndex, required int? burnIn}) async {
    final item = _item;
    final old = _transcode;
    if (item == null || old == null) return;
    final at = _player.state.position;
    final subtitle = _player.state.track.subtitle;
    final next = _Transcode.build(item, audioIndex: audioIndex, burnIn: burnIn, maxBitrate: old.maxBitrate);
    setState(() => _transcode = next);
    _reporter
      ?..playSessionId = next.session
      ..audioStreamIndex = next.audioIndex;

    _switching = true; // the stop and reopen aren't the episode ending
    try {
      await _player.stop();
      if (!mounted) return;
      await _player.open(
        Media(next.url, httpHeaders: jellyfin.authHeaders, start: at > Duration.zero ? at : null),
      );
    } finally {
      _switching = false;
      unawaited(_stopTranscode(old));
    }
    if (burnIn == null && subtitle.id.startsWith('http')) {
      await _waitForTracks();
      if (mounted) await _player.setSubtitleTrack(subtitle);
    }
  }

  /// Tells the server to stop converting (it otherwise keeps going for a while).
  Future<void> _stopTranscode(_Transcode transcode) async {
    final base = jellyfin.client?.baseUrl;
    if (base == null) return;
    try {
      await http
          .delete(
        Uri.parse('$base/Videos/ActiveEncodings').replace(
          queryParameters: {'deviceId': _Transcode.deviceId, 'playSessionId': transcode.session},
        ),
        headers: jellyfin.authHeaders,
      )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // The server ends abandoned conversions by itself after a while.
    }
  }

  // ── Watch Together ──

  /// Tells the group this device is loading (it waits) or ready (it can go).
  void _reportBuffering(bool buffering, {bool force = false}) {
    if (!_inGroup || !_localOpened || _switching) return;
    if (!force && (_groupSeeking || _reportedBuffering == buffering)) return;
    _reportedBuffering = buffering;
    final position = _player.state.position;
    final playing = _player.state.playing;
    if (buffering) {
      syncPlay.buffering(position, playing: playing);
    } else {
      syncPlay.ready(position, playing: playing);
    }
  }

  /// The group moved to another item (or confirmed this one): switch to it here.
  void _onGroupSwitch(String itemId, Duration start) {
    if (!mounted) return;
    if (itemId == _itemId) {
      // Already playing it (this device started it): now the group knows, say where we are.
      // Not loaded yet counts as loading.
      _reportBuffering(_player.state.duration == Duration.zero || _player.state.buffering, force: true);
      return;
    }
    _groupDriven = true;
    _switchTo(itemId);
  }

  /// Seeks for the group, only if this device is noticeably off (a needless seek would
  /// rebuffer). The buffering it causes isn't reported back (see [_groupSeeking]).
  Future<void> _groupSeek(Duration target) async {
    if ((_player.state.position - target).abs() < const Duration(milliseconds: 500)) return;
    _groupSeeking = true;
    try {
      await _player.seek(target);
    } finally {
      Timer(const Duration(milliseconds: 800), () => _groupSeeking = false);
    }
  }

  /// Carries out the group's pause, play, seek or stop, at the moment it names, so
  /// everyone does it at the same time.
  void _onGroupCommand(SyncPlayCommand command) {
    if (!_inGroup || !_localOpened || !mounted) return;
    final current = syncPlay.current;
    if (command.playlistItemId != null &&
        current != null &&
        command.playlistItemId != current.playlistItemId) {
      return; // meant for a different item
    }
    _groupTimer?.cancel();
    final delay = command.when.difference(DateTime.now());

    switch (command.command) {
      case 'Unpause':
        if (delay > Duration.zero) {
          _groupSeek(command.position);
          _groupTimer = Timer(delay, _player.play);
        } else {
          // Everyone else started a moment ago: jump ahead by that much to catch up.
          _groupSeek(command.position - delay);
          _player.play();
        }
      case 'Pause':
        void pause() {
          _player.pause();
          _groupSeek(command.position);
        }
        if (delay > Duration.zero) {
          _groupTimer = Timer(delay, pause);
        } else {
          pause();
        }
      case 'Seek':
      // Pause, jump, then tell the group we're ready; it starts everyone again together.
        _player.pause();
        _groupSeek(command.position).then((_) => _reportBuffering(false, force: true));
      case 'Stop':
        context.pop();
        return;
    }
    _showControls();
  }

  // ── Up next ──

  /// When the episode ends: the next one (via the countdown card), or back to where you were.
  void _onCompleted(bool completed) {
    if (!completed || !mounted || _switching) return;
    if (_inGroup) {
      // The group moves on together (asking twice is harmless: the server ignores repeats).
      if (syncPlay.hasNext) {
        syncPlay.requestNext();
      } else {
        context.pop();
      }
      return;
    }
    final autoplay = _next != null && playbackSettings.autoplayNext && !_upNextDismissed;
    if (!autoplay) {
      context.pop();
      return;
    }
    if (!_upNextShown) _showUpNext(); // ended before the card appeared (e.g. no credits)
  }

  /// Shows the card during the credits (or near the end, without credits), and hides it again
  /// if you seek back before that point.
  void _checkUpNext(Duration position) {
    if (_next == null || _upNextDismissed || _casting || _inGroup || !playbackSettings.autoplayNext) return;
    final duration = _player.state.duration;
    if (duration <= Duration.zero) return;
    final credits = _segments.where((s) => s.kind == _SegmentKind.credits).firstOrNull;
    final showAt = credits?.start ?? duration - Duration(seconds: playbackSettings.countdownSeconds + 2);

    if (!_upNextShown && position >= showAt) {
      _showUpNext();
    } else if (_upNextShown && !_stillWatching && position < showAt - const Duration(seconds: 1)) {
      _hideUpNext(); // went back into the episode
    }
  }

  void _showUpNext() {
    final limit = playbackSettings.stillWatchingAfter;
    setState(() {
      _upNextShown = true;
      _stillWatching = limit > 0 && playbackSettings.autoplayStreak >= limit;
      _countdown = playbackSettings.countdownSeconds;
    });
    _countdownTimer?.cancel();
    if (!_stillWatching) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return timer.cancel();
        // Paused: the countdown waits too. It keeps going once the video has ended.
        if (!_player.state.playing && !_player.state.completed) return;
        if (_countdown <= 1) {
          timer.cancel();
          _playNext(automatic: true);
        } else {
          setState(() => _countdown--);
        }
      });
    }
    // Select "Play now" (or "Continue watching"), so pressing Select goes straight on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _upNextShown) _upNextNode.requestFocus();
    });
  }

  /// Puts the card away. [dismissed]: Cancel was pressed, so this episode just ends.
  void _hideUpNext({bool dismissed = false}) {
    _countdownTimer?.cancel();
    final hadFocus = _upNextNode.hasFocus;
    setState(() {
      _upNextShown = false;
      _stillWatching = false;
      if (dismissed) _upNextDismissed = true;
    });
    if (hadFocus) _focus.requestFocus();
    if (dismissed && _player.state.completed) context.pop(); // already over: leave now
  }

  /// [automatic]: the countdown ran out, rather than a button being pressed.
  Future<void> _playNext({required bool automatic}) async {
    final next = _next;
    if (next == null) return;
    playbackSettings.autoplayStreak = automatic ? playbackSettings.autoplayStreak + 1 : 0;
    await _switchTo(next.id);
  }

  /// True while changing to the next episode, so the old one stopping isn't taken as it ending.
  bool _switching = false;

  /// Plays another item in this same player (the next episode), without leaving the screen.
  Future<void> _switchTo(String id) async {
    _switching = true;
    _groupTimer?.cancel();
    _reportedBuffering = null;
    _countdownTimer?.cancel();
    _ratingTimer?.cancel();
    _noticeTimer?.cancel();
    _scrubCommit?.cancel();
    try {
      await _finishItem();
      await _player.stop();
    } catch (e) {
      debugPrint('Switching episodes: $e');
    } finally {
      _switching = false;
    }
    if (!mounted) return;
    setState(() {
      _itemId = id;
      _item = null;
      _error = null;
      _chapters = const [];
      _namedChapters = const [];
      _segments = const [];
      _activeSegment = null;
      _autoSkipped.clear();
      _notice = null;
      _trickplay = null;
      _ratingShown = false;
      _ratingVisible = false;
      _next = null;
      _upNextShown = false;
      _upNextDismissed = false;
      _stillWatching = false;
      _scrub = null;
      _dragPreview = null;
    });
    _focus.requestFocus();
    await _start();
  }

  /// Done with the current item: report where it stopped, refresh Home and detail pages,
  /// and end any conversion on the server.
  Future<void> _finishItem() async {
    final reporter = _reporter;
    final item = _item;
    final transcode = _transcode;
    _reporter = null;
    _transcode = null;
    if (transcode != null) unawaited(_stopTranscode(transcode));
    if (reporter == null) return;

    final ids = {_itemId, item?.raw['SeriesId'], item?.raw['SeasonId']}.whereType<String>();
    await reporter.stop();
    clearHomeCache();
    appCache.invalidateWhere((key) => ids.any((id) => key.endsWith(':$id')));
  }

  /// Tells Jellyfin what's playing here. Not while casting: the Chromecast reports instead.
  void _startReporter(JellyfinClient client, JellyfinItem item) {
    if (_reporter != null) return;
    final transcode = _transcode;
    _reporter = PlaybackReporter(
      client: client,
      itemId: item.id,
      player: _player,
      mediaSourceId: _sourceOf(item)?['Id'] as String?,
      transcoding: transcode != null,
      playSessionId: transcode?.session,
      audioStreamIndex: transcode?.audioIndex,
    )..start();
  }

  // ── Casting ──

  /// Connecting to a Chromecast moves the video there; disconnecting brings it back.
  void _onCastChanged() {
    if (!mounted) return;
    final item = _item;
    if (item != null && castController.isConnected && !_casting) {
      _castItem(item, start: _localOpened ? _player.state.position : _resumePosition(item));
    } else if (_casting && !castController.isConnected) {
      _returnFromCast();
    } else if (_casting && _castLoaded && castController.nowPlaying == null) {
      // Finished on the TV (or stopped from its remote): leave the player, as at the end here.
      _casting = false;
      context.pop();
    } else {
      setState(() {}); // play/pause and the like, for the remote's buttons
    }
  }

  /// Sends [item] to the Chromecast with the audio and subtitles playing now
  /// (or, if nothing's playing here yet, the ones from the user's preferences).
  Future<void> _castItem(JellyfinItem item, {required Duration start}) async {
    setState(() {
      _casting = true;
      _castLoaded = false;
    });
    _setControlsVisible(false); // the remote takes over the screen
    // This device stops reporting, so the two don't overwrite each other's position.
    final reporter = _reporter;
    _reporter = null;
    unawaited(reporter?.stop());

    int? audio;
    int? subtitle;
    if (_localOpened) {
      (audio, subtitle) = _currentStreamIndexes(item);
      await _player.pause();
    } else {
      final prefs = await _fetchTrackPrefs();
      if (prefs != null) {
        final audioStreams = _streamsOf(item, 'Audio', external: false);
        final a = _pickAudio(audioStreams, prefs);
        audio = a == null ? null : audioStreams[a]['Index'] as int?;
        final language = a == null ? null : audioStreams[a]['Language'] as String?;
        final picked = _pickSubtitle(
          [..._streamsOf(item, 'Subtitle', external: false), ..._streamsOf(item, 'Subtitle', external: true)],
          prefs,
          language,
        );
        subtitle = picked?['Index'] as int?;
      }
    }

    try {
      await castController.load(item, start: start, audioStreamIndex: audio, subtitleStreamIndex: subtitle);
      if (mounted) setState(() => _castLoaded = true);
    } catch (e) {
      debugPrint('Casting failed: $e');
      if (mounted) _returnFromCast();
    }
  }

  /// Back from the Chromecast: carry on here from where it got to.
  Future<void> _returnFromCast() async {
    final item = _item;
    final at = castController.lastPosition;
    setState(() {
      _casting = false;
      _castLoaded = false;
    });
    if (item == null) return;
    if (_localOpened) {
      if (at > Duration.zero) await _player.seek(at);
      await _player.play();
      if (jellyfin.client case final client?) _startReporter(client, item);
    } else if (jellyfin.client case final client?) {
      await _openLocal(client, item, at > Duration.zero ? at : _resumePosition(item));
    }
    if (mounted) _showControls();
  }

  /// The Jellyfin stream indexes of the audio and subtitles playing here now.
  (int?, int?) _currentStreamIndexes(JellyfinItem item) {
    // Converting: the audio is the one asked for; subtitles are burned in or loaded by address.
    if (_transcode case final t?) {
      final id = _player.state.track.subtitle.id;
      var subtitle = t.burnIn;
      if (subtitle == null && id.startsWith('http')) {
        final match = _allSubtitles(item).where((s) => _externalSubtitleUrl(item, s) == id).firstOrNull;
        subtitle = match?['Index'] as int?;
      }
      return (t.audioIndex, subtitle);
    }

    final tracks = _player.state.tracks;

    final audioStreams = _streamsOf(item, 'Audio', external: false);
    final audioTracks = tracks.audio.where((t) => _isRealTrack(t.id)).toList();
    final a = audioTracks.indexWhere((t) => t.id == _player.state.track.audio.id);
    final audio = a != -1 && a < audioStreams.length ? audioStreams[a]['Index'] as int? : null;

    final id = _player.state.track.subtitle.id;
    int? subtitle;
    if (_isRealTrack(id)) {
      if (id.startsWith('http')) {
        subtitle = _streamsOf(item, 'Subtitle', external: true)
            .where((s) => _externalSubtitleUrl(item, s) == id)
            .firstOrNull?['Index'] as int?;
      } else {
        final embedded = _streamsOf(item, 'Subtitle', external: false);
        final subtitleTracks = tracks.subtitle.where((t) => _isRealTrack(t.id)).toList();
        final i = subtitleTracks.indexWhere((t) => t.id == id);
        if (i != -1 && i < embedded.length) subtitle = embedded[i]['Index'] as int?;
      }
    }
    return (audio, subtitle);
  }

  Future<void> _openCastAudio() async {
    final item = _item;
    if (item == null) return;
    final streams = _streamsOf(item, 'Audio', external: false).where((s) => s['Index'] is int).toList();
    final current = castController.nowPlaying?.audioStreamIndex ??
        (streams.where((s) => s['IsDefault'] == true).firstOrNull ?? streams.firstOrNull)?['Index'];
    await _pickTrack(
      context,
      title: 'Audio',
      choices: [
        for (final s in streams)
          (
          key: 'audio:${s['Index']}',
          label: (s['DisplayTitle'] as String?) ?? 'Track ${s['Index']}',
          select: () => castController.setAudio(item, s['Index'] as int),
          ),
      ],
      current: 'audio:$current',
    );
  }

  Future<void> _openCastSubtitles() async {
    final item = _item;
    if (item == null) return;
    final streams = [
      ..._streamsOf(item, 'Subtitle', external: false),
      ..._streamsOf(item, 'Subtitle', external: true),
    ].where((s) => s['Index'] is int).toList();
    final current = castController.nowPlaying?.subtitleStreamIndex;
    await _pickTrack(
      context,
      title: 'Subtitles',
      choices: [
        (key: 'off', label: 'Off', select: () => castController.setSubtitles(item, null, isText: true)),
        for (final s in streams)
          (
          key: 'sub:${s['Index']}',
          label: (s['DisplayTitle'] as String?) ?? 'Subtitles ${s['Index']}',
          select: () => castController.setSubtitles(
            item,
            s['Index'] as int,
            isText: s['IsTextSubtitleStream'] != false,
          ),
          ),
      ],
      current: current == null ? 'off' : 'sub:$current',
    );
  }

  /// Chooses the starting audio and subtitle tracks the way Jellyfin's own apps do,
  /// from the language and "When to show subtitles" settings in the user's account.
  /// On its own, mpv only follows the file's default flags.
  Future<void> _applyDefaultTracks(JellyfinItem item) async {
    final prefs = await _fetchTrackPrefs();
    if (prefs == null || !mounted) return;
    final tracks = await _waitForTracks();
    if (!mounted) return;

    // ── Audio: the preferred language if the file has it ──
    final audioStreams = _streamsOf(item, 'Audio', external: false);
    final audioTracks = tracks.audio.where((t) => _isRealTrack(t.id)).toList();
    final audioPick = _pickAudio(audioStreams, prefs);
    if (audioPick != null && audioPick < audioTracks.length) {
      await _player.setAudioTrack(audioTracks[audioPick]);
    }
    final playingAudio = audioPick ?? 0;
    final audioLanguage = playingAudio < audioStreams.length
        ? audioStreams[playingAudio]['Language'] as String?
        : null;

    // ── Subtitles: by the chosen mode ──
    final embedded = _streamsOf(item, 'Subtitle', external: false);
    final external = _streamsOf(item, 'Subtitle', external: true);
    final pick = _pickSubtitle([...embedded, ...external], prefs, audioLanguage);
    if (!mounted) return;

    if (pick == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final embeddedIndex = embedded.indexOf(pick);
    if (embeddedIndex != -1) {
      // mpv lists the file's subtitles in the same order as Jellyfin does.
      final subtitleTracks = tracks.subtitle.where((t) => _isRealTrack(t.id)).toList();
      if (embeddedIndex < subtitleTracks.length) {
        await _player.setSubtitleTrack(subtitleTracks[embeddedIndex]);
      }
    } else if (_externalSubtitleUrl(item, pick) case final url?) {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          url,
          title: pick['DisplayTitle'] as String?,
          language: pick['Language'] as String?,
        ),
      );
    }
  }

  /// mpv reports the file's tracks a moment after opening; waits for them (up to 10 s).
  Future<Tracks> _waitForTracks() async {
    bool ready(Tracks t) =>
        t.video.any((v) => _isRealTrack(v.id)) || t.audio.any((a) => _isRealTrack(a.id));
    if (ready(_player.state.tracks)) return _player.state.tracks;
    try {
      return await _player.stream.tracks.firstWhere(ready).timeout(const Duration(seconds: 10));
    } catch (_) {
      return _player.state.tracks;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _countdownTimer?.cancel();
    _noticeTimer?.cancel();
    _scrubCommit?.cancel();
    _ratingTimer?.cancel();
    _singleTapTimer?.cancel();
    _tapSeekEnd?.cancel();
    castController.removeListener(_onCastChanged);
    syncPlay.detach(_onGroupSwitch);
    _groupCommands?.cancel();
    _groupTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }

    // Report where playback stopped (the player is read straight away, before it's disposed).
    unawaited(_finishItem());

    _player.dispose();
    _focus.dispose();
    for (final node in _allButtons) {
      node.dispose();
    }
    _seekNode.dispose();
    _skipNode.dispose();
    _upNextNode.dispose();
    _upNextScope.dispose();
    _stopFollowingTilt();
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

  // ── Taps on the video ──

  /// TV and desktop: a tap or click shows or hides the controls.
  /// Phones: the same, plus double-tap on the left or right third to seek.
  void _onVideoTapUp(TapUpDetails details, {required bool compact}) {
    playbackSettings.autoplayStreak = 0; // someone's there
    if (!compact) return _toggleControls();

    final width = MediaQuery.sizeOf(context).width;
    final x = details.localPosition.dx;
    final side = x < width / 3 ? -1 : (x > width * 2 / 3 ? 1 : 0);
    final now = DateTime.now();

    final doubleTap = side != 0 &&
        side == _lastTapSide &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < _doubleTapWindow;
    final continuingRun = side != 0 && _tapSeekVisible && _tapSeek?.side == side; // still within a run of taps
    _lastTapAt = now;
    _lastTapSide = side;

    if (doubleTap || continuingRun) {
      _singleTapTimer?.cancel(); // the first tap wasn't a "show controls" tap after all
      _seekByTap(side);
      return;
    }

    _singleTapTimer?.cancel();
    if (side == 0) return _toggleControls(); // the middle has no double tap, so no need to wait
    _singleTapTimer = Timer(_doubleTapWindow, () {
      if (mounted) _toggleControls();
    });
  }

  /// Jumps one step back (side -1) or forward (side 1), adding up across a run of taps.
  void _seekByTap(int side) {
    final run = _tapSeekVisible ? _tapSeek : null;
    final step = playbackSettings.seekStep;
    final seconds = run != null && run.side == side ? run.seconds + step : step;
    // Count from where the run started: the player's position lags right after a seek.
    if (run == null || run.side != side) _tapSeekFrom = _player.state.position;

    var target = _tapSeekFrom + Duration(seconds: seconds * side);
    final duration = _player.state.duration;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    _seekNow(target);

    setState(() {
      _tapSeek = (side: side, seconds: seconds);
      _tapSeekVisible = true;
    });
    _tapSeekEnd?.cancel();
    _tapSeekEnd = Timer(const Duration(milliseconds: 800), () {
      // Only fade out: the side and count stay, so it doesn't jump to the other side as it fades.
      if (mounted) setState(() => _tapSeekVisible = false);
    });
  }

  // ── Rating intro ──

  /// Slides the age rating in once, shortly after playback first starts, then away again.
  void _introduceRating() {
    final rating = _item?.raw['OfficialRating'] as String?;
    if (!playbackSettings.showRating || _casting) return;
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

  // ── Turning the phone ──

  /// Phones: the player starts sideways and stays that way, even while the phone is still held
  /// upright. Once the phone has actually been turned sideways, the picture follows it: held
  /// upright for a moment, it turns upright; sideways again, it turns back.
  ///
  /// Flutter can't tell how the phone is held, so this reads the motion sensor (which way
  /// gravity pulls). On TVs and other devices without one, the stream just ends.
  StreamSubscription<AccelerometerEvent>? _tilt;
  bool _turnedSideways = false; // the phone has been held sideways since the player opened
  DateTime? _uprightSince; // when the phone was last tipped upright, while it stays upright
  List<DeviceOrientation>? _heldTo;

  void _followTilt() {
    _tilt = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
          (e) {
        // Gravity is about 9.8 along whichever edge points down. Lying flat, it's on z
        // instead, and neither of these is true, so nothing changes.
        final sideways = e.x.abs() > 6 && e.x.abs() > e.y.abs() * 1.5;
        final upright = e.y > 6 && e.y > e.x.abs() * 1.5; // the right way up, not upside down
        if (sideways) {
          _turnedSideways = true;
          _uprightSince = null;
          _holdTo(AppOrientation.landscape);
        } else if (upright && _turnedSideways) {
          // Wait a moment, so a wobble while getting comfortable doesn't flip the picture.
          final since = _uprightSince ??= DateTime.now();
          if (DateTime.now().difference(since) > const Duration(milliseconds: 600)) {
            _holdTo(AppOrientation.portrait);
          }
        } else {
          _uprightSince = null;
        }
      },
      onError: (_) {}, // no motion sensor: stays as it started
      cancelOnError: true,
    );
  }

  void _holdTo(List<DeviceOrientation> orientations) {
    if (identical(_heldTo, orientations)) return;
    _heldTo = orientations;
    AppOrientation.player(only: orientations);
  }

  void _stopFollowingTilt() {
    _tilt?.cancel();
    _tilt = null;
  }

  void _playOrPause() {
    if (_inGroup) {
      // Ask the group; the pause or play happens when the server says, for everyone.
      _player.state.playing ? syncPlay.requestPause() : syncPlay.requestUnpause();
    } else {
      _player.playOrPause();
    }
    _showControls();
  }

  /// Seeks here, or asks the group to seek everyone there.
  void _seekNow(Duration target) {
    if (_inGroup) {
      syncPlay.requestSeek(target);
    } else {
      _player.seek(target);
    }
  }

  void _seekTo(Duration target) {
    final duration = _player.state.duration;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    _seekNow(target);
    _showControls();
  }

  /// Jumps to the next chapter, or one step ahead when there are no chapters.
  void _nextChapter() {
    final position = _player.state.position;
    if (_chapters.isEmpty) return _seekTo(position + _step);
    final next = _chapters
        .where((c) => c > position + const Duration(seconds: 1))
        .firstOrNull;
    if (next != null) _seekTo(next);
  }

  void _updateActiveSegment(Duration position) {
    if (_switching) return;
    _checkUpNext(position);

    var active = _segments.where((s) => s.contains(position)).firstOrNull;
    if (active != null) {
      switch (_skipModeFor(active.kind)) {
        case SkipMode.ignore:
          active = null; // no button
        case SkipMode.auto when !_autoSkipped.contains(active):
        // Skip it once. Seeking back into it later shows the button instead.
          _autoSkipped.add(active);
          _seekNow(active.end);
          _showNotice('Skipped ${active.noun}');
          active = null;
        case SkipMode.auto || SkipMode.ask:
          break;
      }
    }
    if (identical(active, _activeSegment)) return;

    final appeared = _activeSegment == null && active != null;
    final hadFocus = _skipNode.hasFocus;
    setState(() => _activeSegment = active);

    if (appeared && !_upNextShown) {
      // A skip button just appeared: select it, so Select presses it right away.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _activeSegment != null) _skipNode.requestFocus();
      });
    } else if (active == null && hadFocus) {
      _focus.requestFocus(); // the button has gone: back to the video
    }
  }

  /// What Settings says to do for a kind of segment. Commercials work like intros.
  SkipMode _skipModeFor(_SegmentKind kind) => playbackSettings.skip[switch (kind) {
    _SegmentKind.intro || _SegmentKind.commercial => SkipKind.intro,
    _SegmentKind.recap => SkipKind.recap,
    _SegmentKind.credits => SkipKind.credits,
    _SegmentKind.preview => SkipKind.preview,
  }] ?? SkipMode.ask;

  /// A short message in the corner, such as "Skipped intro".
  void _showNotice(String text) {
    _noticeTimer?.cancel();
    setState(() => _notice = text);
    _noticeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  void _skipSegment() {
    final segment = _activeSegment;
    if (segment == null) return;
    setState(() => _activeSegment = null);
    _seekNow(segment.end);
    _focus.requestFocus(); // back to the video
  }

  /// Jumps to the start of this chapter, or to the previous one when you're already near
  /// the start (like a music player). One step back when there are no chapters.
  void _previousChapter() {
    final position = _player.state.position;
    if (_chapters.isEmpty) return _seekTo(position - _step);
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
    final t = _transcode;
    await _pickTrack(
      context,
      title: 'Audio',
      choices: t == null ? _audioChoices(_player, _item) : _transcodeAudioChoices(t),
      current: t == null ? _currentAudioKey(_player) : 'audio:${t.audioIndex}',
    );
    if (mounted) _showControls();
  }

  Future<void> _openSubtitles() async {
    _showControls(autoHide: false);
    final t = _transcode;
    await _pickTrack(
      context,
      title: 'Subtitles',
      choices: t == null ? _subtitleChoices(_player, _item) : _transcodeSubtitleChoices(t),
      current: t?.burnIn != null ? 'burn:${t!.burnIn}' : _currentSubtitleKey(_player),
    );
    if (mounted) _showControls();
  }

  /// While converting, the stream has one audio track: another one means reopening it.
  List<_TrackChoice> _transcodeAudioChoices(_Transcode t) => [
    for (final s in _streamsOf(_item, 'Audio', external: false))
      if (s['Index'] case final int index)
        (
        key: 'audio:$index',
        label: (s['DisplayTitle'] as String?) ?? 'Track $index',
        select: () => _reopenTranscode(audioIndex: index, burnIn: t.burnIn),
        ),
  ];

  /// While converting: text subtitles load from the server as files; picture subtitles
  /// are burned into the picture, which means reopening the stream.
  List<_TrackChoice> _transcodeSubtitleChoices(_Transcode t) {
    final item = _item;
    String label(Map<String, dynamic> s, int index) => (s['DisplayTitle'] as String?) ?? 'Subtitles $index';
    return [
      (
      key: 'off',
      label: 'Off',
      select: () async {
        await _player.setSubtitleTrack(SubtitleTrack.no());
        if (t.burnIn != null) await _reopenTranscode(audioIndex: t.audioIndex, burnIn: null);
      },
      ),
      for (final s in _allSubtitles(item))
        if (s['Index'] case final int index)
          if (s['IsTextSubtitleStream'] == false)
            (
            key: 'burn:$index',
            label: label(s, index),
            select: () async {
              await _player.setSubtitleTrack(SubtitleTrack.no());
              await _reopenTranscode(audioIndex: t.audioIndex, burnIn: index);
            },
            )
          else if (_externalSubtitleUrl(item, s) case final url?)
            (
            key: url,
            label: label(s, index),
            select: () async {
              if (t.burnIn != null) await _reopenTranscode(audioIndex: t.audioIndex, burnIn: null);
              await _player.setSubtitleTrack(
                SubtitleTrack.uri(url, title: s['DisplayTitle'] as String?, language: s['Language'] as String?),
              );
            },
            ),
    ];
  }

  /// Back while the controls are up: put them away (dropping any unfinished scrub).
  void _hideControlsNow() {
    _hideTimer?.cancel();
    _scrubCommit?.cancel();
    if (_scrub != null) setState(() => _scrub = null);
    _setControlsVisible(false);
  }

  // ── D-pad scrubbing ──

  /// Moves the preview position by the step from Settings. With "Speed up when held" on,
  /// steps grow the longer the button is held (to at least 30 seconds, then a minute).
  void _scrubBy(int direction, {required bool repeat}) {
    _scrubRepeats = repeat ? _scrubRepeats + 1 : 0;
    final base = _step;
    final speedUp = playbackSettings.seekAccelerates;
    Duration atLeast(Duration d) => base > d ? base : d;
    final step = !speedUp
        ? base
        : _scrubRepeats > 20
        ? atLeast(const Duration(seconds: 60))
        : _scrubRepeats > 8
        ? atLeast(const Duration(seconds: 30))
        : base;

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
    // (The subtitles slide up or down with it: see the subtitles in build.)
    if (visible != _controlsVisible) setState(() => _controlsVisible = visible);
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
    playbackSettings.autoplayStreak = 0; // someone's there: no "Are you still watching?" yet

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
    final onUpNext = _upNextScope.hasFocus; // the Up Next card's buttons

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
      if (onUpNext) {
        moveFocus(left ? TraversalDirection.left : TraversalDirection.right); // between its buttons
      } else if (onButton) {
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
      if (onButton || onSkip || onUpNext) return KeyEventResult.ignored; // a focused button presses itself
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
    final compact = isPhoneLayout(context);

    return PopScope(
      // Phones: Back (or the back swipe) leaves straight away. TV remotes: the first Back
      // hides the controls, the next one leaves.
      canPop: _isPhone || !_controlsVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return _hideControlsNow();
        // Leaving: turn the phone back upright now, while the page slides away,
        // rather than after, so the page underneath never shows sideways.
        _stopFollowingTilt();
        AppOrientation.menus();
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
                  onTapUp: (details) => _onVideoTapUp(details, compact: compact),
                  child: Video(
                    key: _videoKey,
                    controller: _video,
                    controls: NoVideoControls,
                    fit: _fit,
                    fill: _black,
                    subtitleViewConfiguration: SubtitleViewConfiguration(
                      visible: false, // drawn below instead, in the style from Settings
                    ),
                  ),
                ),

                // ── Subtitles: size, color, font and style from Settings. Sliding up above the
                //    controls while they show. The base size is the same share of the screen's
                //    height on a phone as on a TV. ──
                IgnorePointer(
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 200), // the same speed as the controls' fade
                    curve: Curves.easeOut,
                    padding: _subtitlePadding(lifted: _controlsVisible),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: StreamBuilder<List<String>>(
                        stream: _player.stream.subtitle,
                        initialData: _player.state.subtitle,
                        builder: (context, snapshot) {
                          final text = (snapshot.data ?? const <String>[])
                              .where((line) => line.trim().isNotEmpty)
                              .join('\n');
                          if (text.isEmpty || _casting) return const SizedBox.shrink();
                          return SubtitleText(text, baseSize: compact ? 20 : 36, height: compact ? 1.2 : 1.3);
                        },
                      ),
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

                // ── Shade behind the controls. Outside the safe area, so it reaches every edge
                //    (including behind the camera cutout) instead of stopping short of it.
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: _ControlsShade(compact: compact),
                  ),
                ),

                // ── Double-tap seek: "« 10 seconds" (or the step from Settings) on the side that was tapped ──
                IgnorePointer(child: _TapSeekIndicator(seek: _tapSeek, visible: _tapSeekVisible)),

                // ── Everything drawn over the video, kept clear of the screen's edges.
                //    Both sides get the camera cutout's inset (not just the cutout side), so the
                //    controls stay centred. Phones also keep clear of the rounded bottom corners.
                Positioned.fill(
                  child: Padding(
                    padding: _overlayInsets(context, compact: compact),
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
                              onCast: () => showCastPicker(context),
                            ),
                          ),
                        ),

                        // ── Skip intro / credits / ... ──
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          right: compact ? 16 : 32,
                          // Above the controls when they're showing; near the corner otherwise.
                          bottom: _controlsVisible ? (compact ? 146 : 170) : (compact ? 12 : 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            spacing: 12,
                            children: [
                              _Notice(text: _notice),
                              // Up Next takes the skip button's place (it covers "Skip Credits").
                              if (_upNextShown && _next != null)
                                Focus(
                                  focusNode: _upNextScope,
                                  skipTraversal: true,
                                  canRequestFocus: false,
                                  child: _UpNextCard(
                                    next: _next!,
                                    countdown: _countdown,
                                    stillWatching: _stillWatching,
                                    compact: compact,
                                    playNode: _upNextNode,
                                    onPlay: () => _playNext(automatic: false),
                                    onCancel: _stillWatching ? () => context.pop() : () => _hideUpNext(dismissed: true),
                                  ),
                                )
                              else
                                _SkipButton(
                                  segment: _activeSegment,
                                  onPress: _skipSegment,
                                  focusNode: _skipNode,
                                  selected: _skipFocused,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Casting: this screen becomes the Chromecast's remote ──
                if (_casting && _item != null)
                  CastRemote(
                    item: _item!,
                    onBack: () => context.pop(), // casting carries on
                    onAudio: _openCastAudio,
                    onSubtitles: _openCastSubtitles,
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
