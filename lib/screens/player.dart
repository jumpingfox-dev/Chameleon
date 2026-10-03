// The player always uses Flutter's built-in Material icons (not appIcons):
// solid, evenly weighted and instantly recognizable for media controls,
// whatever icon style is chosen in Settings.

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:http/http.dart' as http;

import '../utils/app_cache.dart';
import '../utils/cast_controller.dart';
import '../utils/focus_rows.dart';
import '../utils/jellyfin_controller.dart';
import '../utils/orientation.dart';
import '../utils/playback_reporter.dart';
import '../utils/playback_settings.dart';
import '../widgets/cast_widgets.dart';
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

  /// Where subtitles sit: just above the bottom edge normally, and lifted above the
  /// seek bar and buttons while the controls are showing.
  static const _subtitlesNormal = EdgeInsets.fromLTRB(48, 0, 48, 48);
  static const _subtitlesLifted = EdgeInsets.fromLTRB(48, 0, 48, 150);

  /// Phones: the same idea, scaled down. Lifted, they sit just above the bottom controls
  /// and below the play button (which sits a little above centre to leave them room).
  static const _subtitlesNormalPhone = EdgeInsets.fromLTRB(32, 0, 32, 20);
  static const _subtitlesLiftedPhone = EdgeInsets.fromLTRB(32, 0, 32, 146);

  bool get _isPhone => MediaQuery.sizeOf(context).shortestSide < 600;

  EdgeInsets _subtitlePadding({required bool lifted}) {
    lifted = lifted && playbackSettings.liftSubtitles; // "Move up when controls show" in Settings
    return _isPhone
        ? (lifted ? _subtitlesLiftedPhone : _subtitlesNormalPhone)
        : (lifted ? _subtitlesLifted : _subtitlesNormal);
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

  /// Casting: the video plays on a Chromecast and this screen becomes its remote.
  bool _casting = false;
  bool _castLoaded = false; // the Chromecast has been sent the video
  bool _localOpened = false; // the video has been opened on this device

  @override
  void initState() {
    super.initState();
    AppOrientation.player(); // full screen, and free to turn either way
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

      // The episode after this one, for Up Next. Loads alongside the video.
      unawaited(
        _fetchNextEpisode(item).then((next) {
          if (mounted && id == _itemId) setState(() => _next = next);
        }),
      );

      // Where to start, by the Resuming setting.
      var start = _resumePosition(item);
      if (start > Duration.zero) {
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
              child: Text('Resume from ${_formatTime(at)}'),
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
    await _player.open(
      Media(
        transcode?.url ?? jellyfin.streamUrl(item.id),
        httpHeaders: jellyfin.authHeaders,
        start: start > Duration.zero ? start : null,
      ),
    );

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

  // ── Up next ──

  /// When the episode ends: the next one (via the countdown card), or back to where you were.
  void _onCompleted(bool completed) {
    if (!completed || !mounted || _switching) return;
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
    if (_next == null || _upNextDismissed || _casting || !playbackSettings.autoplayNext) return;
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
    _player.seek(target);

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
          _player.seek(active.end);
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
    _player.seek(segment.end);
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
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;

    return PopScope(
      canPop: !_controlsVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return _hideControlsNow();
        // Leaving: turn the phone back upright now, while the page slides away,
        // rather than after, so the page underneath never shows sideways.
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
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;

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
              _ControlButton(
                focusNode: backNode,
                icon: Icons.arrow_back_rounded,
                label: 'Back',
                size: compact ? 28 : 22,
                onPress: onBack,
              ),
              if (item != null) Flexible(child: _PlayerTitle(item: item!)),
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
        final focused = states.contains(FTappableVariant.focused);
        final hovered = states.contains(FTappableVariant.hovered);
        final compact = MediaQuery.sizeOf(context).shortestSide < 600;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.all(compact ? 10 : 7), // phones: 48 px targets for thumbs
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
      // Phones: a thicker bar, a bigger handle and a taller touch area, for thumbs.
      final compact = MediaQuery.sizeOf(context).shortestSide < 600;
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

/// All subtitle streams: the file's own, then external files.
List<Map<String, dynamic>> _allSubtitles(JellyfinItem? item) => [
  ..._streamsOf(item, 'Subtitle', external: false),
  ..._streamsOf(item, 'Subtitle', external: true),
];

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

/// The user's playback preferences from their Jellyfin account.
typedef _TrackPrefs = ({
String? audioLanguage, // e.g. 'eng', or null for no preference
String? subtitleLanguage,
String subtitleMode, // Default, Smart, OnlyForced, Always or None
bool playDefaultAudio, // prefer the file's default audio over the preferred language
});

/// Fetched fresh each time, so a change in Settings applies to the very next video.
Future<_TrackPrefs?> _fetchTrackPrefs() async {
  final baseUrl = jellyfin.client?.baseUrl;
  if (baseUrl == null) return null;
  try {
    final res = await http
        .get(Uri.parse('$baseUrl/Users/Me'), headers: jellyfin.authHeaders)
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return null;
    final config = (jsonDecode(res.body) as Map<String, dynamic>)['Configuration'] as Map? ?? {};
    String? lang(Object? v) => v is String && v.isNotEmpty ? v : null;
    return (
    audioLanguage: lang(config['AudioLanguagePreference']),
    subtitleLanguage: lang(config['SubtitleLanguagePreference']),
    subtitleMode: config['SubtitleMode'] as String? ?? 'Default',
    playDefaultAudio: config['PlayDefaultAudioTrack'] as bool? ?? true,
    );
  } catch (_) {
    return null; // offline or old server: leave mpv's choice alone
  }
}

/// Some languages have two three-letter codes (German is both "ger" and "deu").
const _languageAliases = {
  'ger': 'deu', 'fre': 'fra', 'chi': 'zho', 'dut': 'nld', 'cze': 'ces', 'gre': 'ell',
  'per': 'fas', 'rum': 'ron', 'slo': 'slk', 'alb': 'sqi', 'arm': 'hye', 'baq': 'eus',
  'bur': 'mya', 'geo': 'kat', 'ice': 'isl', 'mac': 'mkd', 'mao': 'mri', 'may': 'msa',
  'tib': 'bod', 'wel': 'cym',
};

bool _sameLanguage(Object? a, String? b) {
  if (a is! String || b == null) return false;
  String norm(String s) => _languageAliases[s.toLowerCase()] ?? s.toLowerCase();
  return norm(a) == norm(b);
}

/// Position of the audio stream to start with, or null to keep mpv's choice.
int? _pickAudio(List<Map<String, dynamic>> streams, _TrackPrefs prefs) {
  if (streams.isEmpty) return null;
  final preferred = streams.indexWhere((s) => _sameLanguage(s['Language'], prefs.audioLanguage));
  final flagged = streams.indexWhere((s) => s['IsDefault'] == true);
  if (prefs.playDefaultAudio && flagged != -1) return flagged;
  if (preferred != -1) return preferred;
  return null;
}

/// The subtitle stream to start with, or null for off. Follows Jellyfin's modes:
/// * Default: whatever the file flags as default or forced (preferred language first).
/// * Smart: the preferred language when the audio is in another one; otherwise only forced.
/// * OnlyForced: only forced subtitles (signs and foreign dialogue).
/// * Always: the preferred language, or else the default or first subtitles.
/// * None: off.
Map<String, dynamic>? _pickSubtitle(
    List<Map<String, dynamic>> streams,
    _TrackPrefs prefs,
    String? audioLanguage,
    ) {
  if (streams.isEmpty) return null;
  bool inLanguage(Map<String, dynamic> s) => _sameLanguage(s['Language'], prefs.subtitleLanguage);
  bool forced(Map<String, dynamic> s) => s['IsForced'] == true;
  bool flagged(Map<String, dynamic> s) => s['IsDefault'] == true;

  /// The first stream passing [test], preferring the user's language.
  Map<String, dynamic>? first(bool Function(Map<String, dynamic>) test) =>
      streams.where((s) => test(s) && inLanguage(s)).firstOrNull ?? streams.where(test).firstOrNull;

  final forcedOnly = first(forced);
  switch (prefs.subtitleMode) {
    case 'None':
      return null;
    case 'OnlyForced':
      return forcedOnly;
    case 'Always':
      return streams.where((s) => inLanguage(s) && !forced(s)).firstOrNull ??
          streams.where(inLanguage).firstOrNull ??
          first(flagged) ??
          streams.first;
    case 'Smart':
      final foreignAudio =
          prefs.subtitleLanguage != null && !_sameLanguage(audioLanguage, prefs.subtitleLanguage);
      if (foreignAudio) {
        return streams.where((s) => inLanguage(s) && !forced(s)).firstOrNull ??
            streams.where(inLanguage).firstOrNull ??
            forcedOnly;
      }
      return forcedOnly;
    default: // 'Default'
      return first((s) => flagged(s) || forced(s));
  }
}
// ─── Converting (transcoding) ────────────────────────────────────────────────

/// The item's first media source, as Jellyfin describes it.
Map? _sourceOf(JellyfinItem item) => (item.raw['MediaSources'] as List?)?.firstOrNull as Map?;

String _randomId() {
  final random = math.Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// A stream the server converts while you watch: H.264 video under the quality limit, with one
/// audio track, and picture subtitles burned in if they're on. Settings decide the audio:
/// passthrough keeps surround formats as they are, downmix asks for stereo.
class _Transcode {
  const _Transcode._({
    required this.url,
    required this.session,
    required this.audioIndex,
    required this.burnIn,
    required this.maxBitrate,
  });

  /// Sent with each conversion, so it can be stopped by name afterwards.
  static const deviceId = 'chameleon-player';

  final String url;
  final String session; // Jellyfin's PlaySessionId for this conversion
  final int? audioIndex; // the audio stream carried
  final int? burnIn; // the picture subtitles burned in, if any
  final int? maxBitrate; // bits per second, or null for no limit

  factory _Transcode.build(JellyfinItem item, {int? audioIndex, int? burnIn, int? maxBitrate}) {
    final client = jellyfin.client!;
    final s = playbackSettings;
    final session = _randomId();
    final channels = s.passthrough ? 8 : (s.downmix ? 2 : 6);
    final url = Uri.parse('${client.baseUrl}/Videos/${item.id}/master.m3u8').replace(
      queryParameters: {
        'MediaSourceId': (_sourceOf(item)?['Id'] as String?) ?? item.id,
        'DeviceId': deviceId,
        'PlaySessionId': session,
        'api_key': client.token ?? '',
        'VideoCodec': 'h264',
        'AudioCodec': s.passthrough ? 'aac,ac3,eac3,dts,truehd,mp3' : 'aac,ac3,eac3,mp3',
        // Copy what already fits instead of converting it again.
        'AllowVideoStreamCopy': 'true',
        'AllowAudioStreamCopy': 'true',
        'TranscodingMaxAudioChannels': '$channels',
        'MaxStreamingBitrate': '${maxBitrate ?? 120000000}',
        if (maxBitrate != null) 'VideoBitrate': '${math.max(maxBitrate - 384000, 500000)}',
        'SegmentContainer': 'ts',
        'BreakOnNonKeyFrames': 'true',
        if (audioIndex != null) 'AudioStreamIndex': '$audioIndex',
        if (burnIn != null) ...{'SubtitleStreamIndex': '$burnIn', 'SubtitleMethod': 'Encode'},
      },
    ).toString();

    return _Transcode._(
      url: url,
      session: session,
      audioIndex: audioIndex,
      burnIn: burnIn,
      maxBitrate: maxBitrate,
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
  String get title => season != null && episode != null ? 'S$season:E$episode · $name' : name;
}

/// The episode after [item] in its series, or null for movies and the last episode.
Future<_NextEpisode?> _fetchNextEpisode(JellyfinItem item) async {
  if (item.type != JellyfinItemKind.episode) return null;
  final client = jellyfin.client;
  final base = client?.baseUrl;
  final seriesId = item.raw['SeriesId'] as String?;
  if (client == null || base == null || seriesId == null) return null;

  try {
    final uri = Uri.parse('$base/Shows/$seriesId/Episodes').replace(
      queryParameters: {
        'userId': ?client.userId,
        'startItemId': item.id, // this episode first, then the ones after it
        'limit': '2',
      },
    );
    final res = await http.get(uri, headers: jellyfin.authHeaders).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final items = ((jsonDecode(res.body) as Map)['Items'] as List?) ?? const [];
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