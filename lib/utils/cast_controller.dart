import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_jellyfin/dart_jellyfin.dart' show JellyfinItem, JellyfinItemKind;
import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:http/http.dart' as http;

import 'jellyfin_controller.dart';

/// Chromecast support, on Android and iOS phones and tablets.
///
/// Videos are cast to Google's standard receiver. Instead of the original file (which a
/// Chromecast often can't play), it gets an HLS stream from Jellyfin in a format every
/// Chromecast can: H.264 video and AAC audio. Jellyfin only converts what it has to, so a
/// file that's already H.264/AAC is passed straight through.
///
/// Text subtitles are sent alongside as WebVTT and can be switched instantly; picture
/// subtitles (PGS, DVD) are drawn into the video by Jellyfin, which means reloading.
///
/// While casting, this reports playback to Jellyfin itself, so "Continue watching" and
/// watched status stay right.
class CastController extends ChangeNotifier {
  /// Whether this device can cast at all (Android or iOS, with the Cast SDK set up).
  bool supported = false;

  /// Chromecasts found on the network. The cast button only appears when there's one.
  List<GoogleCastDevice> devices = const [];

  GoogleCastSession? _session;
  bool get isConnected => _session?.connectionState == GoogleCastConnectState.connected;
  bool get isConnecting => _session?.connectionState == GoogleCastConnectState.connecting;
  String? get deviceName => _session?.device?.friendlyName;

  /// What's playing on the Chromecast, if it came from this app.
  CastNowPlaying? nowPlaying;

  /// Playing, paused, buffering… as the Chromecast reports it.
  CastMediaPlayerState playerState = CastMediaPlayerState.unknown;

  /// The last position the Chromecast reported for [nowPlaying]. Kept after casting stops,
  /// so the phone can carry on from the same spot.
  Duration lastPosition = Duration.zero;
  bool get isPlaying =>
      playerState == CastMediaPlayerState.playing || playerState == CastMediaPlayerState.buffering;

  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _progressTimer;

  /// Call once at startup, before runApp. Does nothing on platforms without Cast.
  Future<void> init() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId; // Google's standard receiver
      final options = Platform.isIOS
          ? IOSGoogleCastOptions(
              GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
              stopCastingOnAppTerminated: false, // keep playing on the TV if the app closes
            )
          : GoogleCastOptionsAndroid(appId: appId, stopCastingOnAppTerminated: false);
      await GoogleCastContext.instance.setSharedInstanceWithOptions(options);

      _subscriptions
        ..add(
          GoogleCastDiscoveryManager.instance.devicesStream.listen((found) {
            devices = found;
            notifyListeners();
          }),
        )
        ..add(GoogleCastSessionManager.instance.currentSessionStream.listen(_onSession))
        ..add(GoogleCastRemoteMediaClient.instance.mediaStatusStream.listen(_onStatus))
        ..add(
          GoogleCastRemoteMediaClient.instance.playerPositionStream.listen((p) {
            if (nowPlaying != null && p > Duration.zero) lastPosition = p;
          }),
        );
      supported = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Cast unavailable: $e'); // e.g. no Google Play services
    }
  }

  void _onSession(GoogleCastSession? session) {
    final wasConnected = isConnected;
    _session = session;
    if (wasConnected && !isConnected) _finishReporting();
    notifyListeners();
  }

  void _onStatus(GoggleCastMediaStatus? status) {
    final state = status?.playerState ?? CastMediaPlayerState.unknown;
    if (state == playerState) return;
    playerState = state;
    // Finished, or stopped from the TV's own remote. ("Interrupted" is just a reload,
    // e.g. after changing audio, so it doesn't count.)
    final reason = status?.idleReason;
    final ended = reason == GoogleCastMediaIdleReason.finished ||
        reason == GoogleCastMediaIdleReason.cancelled ||
        reason == GoogleCastMediaIdleReason.error;
    if (state == CastMediaPlayerState.idle && ended && nowPlaying != null && nowPlaying!.started) {
      _finishReporting();
    }
    notifyListeners();
  }

  // ─── Connecting ──────────────────────────────────────────────────────────

  Future<void> connect(GoogleCastDevice device) async {
    await GoogleCastSessionManager.instance.startSessionWithDevice(device);
  }

  /// Stops casting and disconnects. Playback on the TV stops too.
  Future<void> disconnect() async {
    await _finishReporting();
    await GoogleCastSessionManager.instance.endSessionAndStopCasting();
  }

  // ─── Playing ─────────────────────────────────────────────────────────────

  /// Where the Chromecast is in the video.
  Stream<Duration> get positionStream => GoogleCastRemoteMediaClient.instance.playerPositionStream;
  Duration get position => GoogleCastRemoteMediaClient.instance.playerPosition;

  /// Starts [item] on the connected Chromecast at [start], with the given Jellyfin stream
  /// indexes (null audio = the file's default; null subtitles = off).
  Future<void> load(
    JellyfinItem item, {
    Duration start = Duration.zero,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final client = jellyfin.client;
    final base = client?.baseUrl;
    final token = client?.token;
    if (!isConnected || base == null || token == null) return;

    final previous = nowPlaying;
    if (previous != null && previous.itemId != item.id) await _finishReporting();

    final source = (item.raw['MediaSources'] as List?)?.firstOrNull as Map?;
    final mediaSourceId = (source?['Id'] as String?) ?? item.id;
    final streams = [
      for (final s in (source?['MediaStreams'] as List?) ?? (item.raw['MediaStreams'] as List?) ?? const [])
        if (s is Map<String, dynamic>) s,
    ];
    final subtitle = subtitleStreamIndex == null
        ? null
        : streams.where((s) => s['Type'] == 'Subtitle' && s['Index'] == subtitleStreamIndex).firstOrNull;
    final textSubtitle = subtitle != null && subtitle['IsTextSubtitleStream'] != false;
    final playSessionId = previous?.itemId == item.id ? previous!.playSessionId : _newId();

    // ── The stream: HLS, H.264 + AAC, picture subtitles burned in ──
    final url = Uri.parse('$base/Videos/${item.id}/master.m3u8').replace(
      queryParameters: {
        'MediaSourceId': mediaSourceId,
        'DeviceId': 'chameleon-cast',
        'PlaySessionId': playSessionId,
        'api_key': token,
        'VideoCodec': 'h264',
        'AudioCodec': 'aac,mp3',
        'AllowVideoStreamCopy': 'true',
        'AllowAudioStreamCopy': 'true',
        'TranscodingMaxAudioChannels': '2',
        'MaxStreamingBitrate': '20000000',
        'SegmentContainer': 'ts',
        'BreakOnNonKeyFrames': 'true',
        if (audioStreamIndex != null) 'AudioStreamIndex': '$audioStreamIndex',
        if (subtitle != null && !textSubtitle) ...{
          'SubtitleStreamIndex': '$subtitleStreamIndex',
          'SubtitleMethod': 'Encode',
        },
      },
    );

    // ── Text subtitles, sent alongside so they can be switched without reloading ──
    final tracks = [
      for (final s in streams)
        if (s['Type'] == 'Subtitle' && s['IsTextSubtitleStream'] != false && s['Index'] is int)
          GoogleCastMediaTrack(
            trackId: _trackId(s['Index'] as int),
            type: TrackType.text,
            subtype: TextTrackType.subtitles,
            trackContentType: 'text/vtt',
            trackContentId:
                '$base/Videos/${item.id}/$mediaSourceId/Subtitles/${s['Index']}/0/Stream.vtt?api_key=$token',
            name: (s['DisplayTitle'] as String?) ?? (s['Language'] as String?) ?? 'Subtitles',
          ),
    ];

    final isEpisode = item.type == JellyfinItemKind.episode;
    final title = isEpisode
        ? [
            (item.raw['SeriesName'] as String?) ?? '',
            if (item.raw['ParentIndexNumber'] != null && item.raw['IndexNumber'] != null)
              'S${item.raw['ParentIndexNumber']}:E${item.raw['IndexNumber']}',
            item.name,
          ].where((p) => p.isNotEmpty).join(' · ')
        : item.name;
    final imageTag = item.imageTags['Primary'];

    nowPlaying = CastNowPlaying(
      itemId: item.id,
      title: title,
      mediaSourceId: mediaSourceId,
      playSessionId: playSessionId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      subtitleTextOnly: subtitle == null || textSubtitle,
      runtime: item.raw['RunTimeTicks'] is int
          ? Duration(microseconds: (item.raw['RunTimeTicks'] as int) ~/ 10)
          : null,
      started: previous?.itemId == item.id && previous!.started,
    );
    lastPosition = start; // until the Chromecast reports in
    notifyListeners();

    await GoogleCastRemoteMediaClient.instance.loadMedia(
      GoogleCastMediaInformation(
        contentId: url.toString(),
        contentUrl: url,
        streamType: CastMediaStreamType.buffered,
        contentType: 'application/x-mpegURL',
        metadata: GoogleCastMovieMediaMetadata(
          title: title,
          images: [
            if (imageTag != null)
              GoogleCastImage(
                url: Uri.parse('$base/Items/${item.id}/Images/Primary?maxWidth=600&tag=$imageTag'),
              ),
          ],
        ),
        tracks: tracks,
      ),
      autoPlay: true,
      playPosition: start,
      activeTrackIds: [
        if (subtitle != null && textSubtitle) _trackId(subtitleStreamIndex!),
      ],
    );

    await _startReporting(start);
  }

  /// Text subtitles switch instantly; anything else (picture subtitles, audio) reloads
  /// the stream from the current position.
  Future<void> setSubtitles(JellyfinItem item, int? streamIndex, {required bool isText}) async {
    final now = nowPlaying;
    if (now == null) return;
    // Switching between text subtitles (or to off) is instant, unless picture subtitles are
    // burned into the current stream, which needs a clean stream without them.
    if ((streamIndex == null || isText) && now.subtitleTextOnly) {
      await GoogleCastRemoteMediaClient.instance.setActiveTrackIDs([
        if (streamIndex != null) _trackId(streamIndex),
      ]);
      nowPlaying = now.copyWith(subtitleStreamIndex: streamIndex, clearSubtitle: streamIndex == null, subtitleTextOnly: true);
      notifyListeners();
      return;
    }
    await load(item, start: position, audioStreamIndex: now.audioStreamIndex, subtitleStreamIndex: streamIndex);
  }

  Future<void> setAudio(JellyfinItem item, int streamIndex) async {
    final now = nowPlaying;
    if (now == null) return;
    await load(item, start: position, audioStreamIndex: streamIndex, subtitleStreamIndex: now.subtitleStreamIndex);
  }

  Future<void> play() => GoogleCastRemoteMediaClient.instance.play();
  Future<void> pause() => GoogleCastRemoteMediaClient.instance.pause();
  Future<void> playOrPause() => isPlaying ? pause() : play();

  Future<void> seek(Duration to) =>
      GoogleCastRemoteMediaClient.instance.seek(GoogleCastMediaSeekOption(position: to < Duration.zero ? Duration.zero : to));

  // Text subtitle track ids: the Jellyfin stream index + 1 (Cast track ids start at 1).
  static int _trackId(int streamIndex) => streamIndex + 1;

  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // ─── Telling Jellyfin what's playing ─────────────────────────────────────

  Future<void> _report(String path, {bool paused = false}) async {
    final now = nowPlaying;
    final base = jellyfin.client?.baseUrl;
    if (now == null || base == null || !jellyfin.isConnected) return;
    try {
      await http.post(
        Uri.parse('$base$path'),
        headers: {...jellyfin.authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'ItemId': now.itemId,
          'MediaSourceId': now.mediaSourceId,
          'PlaySessionId': now.playSessionId,
          'PositionTicks': position.inMicroseconds * 10,
          'IsPaused': paused,
          'PlayMethod': 'Transcode',
          'CanSeek': true,
          if (now.audioStreamIndex != null) 'AudioStreamIndex': now.audioStreamIndex,
          if (now.subtitleStreamIndex != null) 'SubtitleStreamIndex': now.subtitleStreamIndex,
        }),
      );
    } catch (e) {
      debugPrint('Cast progress report failed: $e'); // offline: try again next time
    }
  }

  Future<void> _startReporting(Duration start) async {
    final now = nowPlaying;
    if (now == null) return;
    if (!now.started) {
      nowPlaying = now.copyWith(started: true);
      await _report('/Sessions/Playing');
    }
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _report('/Sessions/Playing/Progress', paused: playerState == CastMediaPlayerState.paused);
    });
  }

  Future<void> _finishReporting() async {
    _progressTimer?.cancel();
    _progressTimer = null;
    final now = nowPlaying;
    if (now == null) return;
    await _report('/Sessions/Playing/Stopped');
    nowPlaying = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}

/// The video this app sent to the Chromecast.
class CastNowPlaying {
  const CastNowPlaying({
    required this.itemId,
    required this.title,
    required this.mediaSourceId,
    required this.playSessionId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.subtitleTextOnly = true,
    this.runtime,
    this.started = false,
  });

  final String itemId;
  final String title;
  final String mediaSourceId;
  final String playSessionId;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final bool subtitleTextOnly; // false when picture subtitles are burned into the stream
  final Duration? runtime;
  final bool started; // Jellyfin has been told playback started

  CastNowPlaying copyWith({
    int? subtitleStreamIndex,
    bool clearSubtitle = false,
    bool? subtitleTextOnly,
    bool? started,
  }) => CastNowPlaying(
    itemId: itemId,
    title: title,
    mediaSourceId: mediaSourceId,
    playSessionId: playSessionId,
    audioStreamIndex: audioStreamIndex,
    subtitleStreamIndex: clearSubtitle ? null : (subtitleStreamIndex ?? this.subtitleStreamIndex),
    subtitleTextOnly: subtitleTextOnly ?? this.subtitleTextOnly,
    runtime: runtime,
    started: started ?? this.started,
  );
}

final castController = CastController();
