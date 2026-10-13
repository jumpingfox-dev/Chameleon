part of 'player.dart';

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
  // Subtitles mpv found in the file: as many as Jellyfin lists. mpv also lists every
  // external file added from the server (below) as a track of its own, so anything past
  // Jellyfin's count is one of those, already offered below. Only when Jellyfin knows of
  // no subtitles at all are mpv's own tracks listed as they are.
  final embedded = streams.isEmpty && external.isEmpty
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
  try {
    final me = await jellyfin.getJson('/Users/Me', timeout: const Duration(seconds: 5));
    final config = (me as Map<String, dynamic>)['Configuration'] as Map? ?? {};
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
    final session = randomHexId();
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
