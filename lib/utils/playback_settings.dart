import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Choices ─────────────────────────────────────────────────────────────────

/// What happens when an intro, recap, credits or preview starts.
enum SkipMode {
  ask('Show a skip button'),
  auto('Skip automatically'),
  ignore('Do nothing');

  const SkipMode(this.label);
  final String label;
}

/// The kinds of skippable segments you can set a [SkipMode] for.
enum SkipKind {
  intro('Intros'),
  recap('Recaps'),
  credits('Credits'),
  preview('Previews');

  const SkipKind(this.label);
  final String label;
}

/// Whether to play the file as it is, or have the server convert it first.
enum StreamMode {
  auto('Direct play, convert only to stay under the quality limit'),
  direct('Always direct play (ignore the quality limit)'),
  transcode('Always convert (for devices that struggle with some formats)');

  const StreamMode(this.label);
  final String label;
}

enum ResumeMode {
  resume('Always resume'),
  ask('Ask each time'),
  startOver('Always start over');

  const ResumeMode(this.label);
  final String label;
}

enum SubtitleSize {
  small('Small', 0.8),
  medium('Medium', 1.0),
  large('Large', 1.25),
  extraLarge('Extra large', 1.5);

  const SubtitleSize(this.label, this.scale);
  final String label;
  final double scale;
}

enum SubtitleColor {
  white('White', Color(0xFFFFFFFF)),
  yellow('Yellow', Color(0xFFFFE14D)),
  cyan('Cyan', Color(0xFF6EE7F0)),
  green('Green', Color(0xFF86EFAC));

  const SubtitleColor(this.label, this.color);
  final String label;
  final Color color;
}

enum SubtitleBackground {
  shadow('Drop shadow'),
  outline('Outline'),
  box('Dark box');

  const SubtitleBackground(this.label);
  final String label;
}

enum AspectMode {
  fit('Fit (show the whole picture)'),
  fill('Fill (zoom to cover the screen)');

  const AspectMode(this.label);
  final String label;
}

/// Clear at small sizes, and covers most languages and scripts.
const defaultSubtitleFont = 'Noto Sans';

/// Quality limits, in bits per second. 0 means no limit (original quality).
const bitrateOptions = <int>[
  0,
  120000000,
  60000000,
  40000000,
  20000000,
  10000000,
  8000000,
  4000000,
  2000000,
  1000000,
];

String bitrateLabel(int bps) {
  if (bps <= 0) return 'Auto (original quality)';
  final mbps = bps / 1000000;
  final hint = switch (bps) {
    >= 60000000 => '4K',
    >= 10000000 => '1080p',
    >= 4000000 => '720p',
    >= 2000000 => '480p',
    _ => '360p',
  };
  return '${mbps == mbps.roundToDouble() ? mbps.toInt() : mbps} Mbps · $hint';
}

const seekStepOptions = [5, 10, 15, 30];
const countdownOptions = [5, 10, 15, 20, 30];

/// 0 means never ask.
const stillWatchingOptions = [0, 2, 3, 4, 5];

// ─── The settings ────────────────────────────────────────────────────────────

/// Playback preferences for this device, saved between launches.
///
/// Change them through [change], which saves and tells listeners:
/// `playbackSettings.change((s) => s.seekStep = 15);`
class PlaybackSettings extends ChangeNotifier {
  PlaybackSettings._();

  static const _key = 'playback_settings';

  // Skipping
  Map<SkipKind, SkipMode> skip = {for (final k in SkipKind.values) k: SkipMode.ask};

  // Up next
  bool autoplayNext = true;
  int countdownSeconds = 10;
  int stillWatchingAfter = 3; // episodes in a row with no button pressed; 0 = never ask

  // Quality
  int wifiBitrate = 0; // 0 = original quality
  int mobileBitrate = 8000000;
  StreamMode streamMode = StreamMode.auto;

  // Seeking
  int seekStep = 10;
  bool seekAccelerates = true;

  // Resuming
  ResumeMode resume = ResumeMode.resume;

  // Subtitles
  String subtitleFont = defaultSubtitleFont; // any Google Font
  SubtitleSize subtitleSize = SubtitleSize.medium;
  SubtitleColor subtitleColor = SubtitleColor.white;
  SubtitleBackground subtitleBackground = SubtitleBackground.shadow;
  bool liftSubtitles = true; // move up while the controls show

  // Audio
  bool passthrough = false; // send surround sound to a soundbar or receiver untouched
  bool downmix = false; // mix everything down to stereo
  bool nightMode = false; // even out loud and quiet parts

  // Display
  bool showRating = true;
  bool trickplay = true;
  AspectMode aspect = AspectMode.fit;

  /// Episodes played in a row by the Up Next countdown, with no button pressed in between.
  /// Not saved: it starts over each time the app opens.
  int autoplayStreak = 0;

  static Future<PlaybackSettings> load() async {
    final settings = PlaybackSettings._();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) settings._read(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('PlaybackSettings.load: $e'); // unreadable: keep the defaults
    }
    return settings;
  }

  /// Applies [edit], tells listeners and saves.
  void change(void Function(PlaybackSettings s) edit) {
    edit(this);
    notifyListeners();
    _save();
  }

  /// The quality limit for the connection in use right now (Wi-Fi/Ethernet or mobile data),
  /// in bits per second, or null for no limit.
  Future<int?> currentMaxBitrate() async {
    final limit = await _limitForConnection();
    return limit > 0 ? limit : null;
  }

  Future<int> _limitForConnection() async {
    try {
      final connections = await Connectivity().checkConnectivity();
      final onMobile = connections.contains(ConnectivityResult.mobile) &&
          !connections.contains(ConnectivityResult.wifi) &&
          !connections.contains(ConnectivityResult.ethernet);
      return onMobile ? mobileBitrate : wifiBitrate;
    } catch (_) {
      return wifiBitrate;
    }
  }

  /// The subtitle text style for these settings. [baseSize] is the medium size for the screen.
  /// Used by the player and by the preview in Settings, so they always match.
  ///
  /// The outline style isn't drawn here (a text style can't have both a fill and an outline);
  /// [SubtitleText] adds it.
  TextStyle subtitleStyle({required double baseSize, double height = 1.3}) {
    final style = TextStyle(
      fontSize: baseSize * subtitleSize.scale,
      height: height,
      color: subtitleColor.color,
      fontWeight: FontWeight.w600, // a little heavier than body text, to read over busy pictures
      letterSpacing: 0.2,
      backgroundColor: subtitleBackground == SubtitleBackground.box ? const Color(0xB3000000) : null,
      shadows: switch (subtitleBackground) {
        SubtitleBackground.shadow => const [Shadow(blurRadius: 6, color: Color(0xCC000000))],
      // A soft shadow under the outline, so it still reads over white.
        SubtitleBackground.outline => const [Shadow(blurRadius: 4, color: Color(0x99000000))],
        SubtitleBackground.box => const [],
      },
    );
    try {
      return GoogleFonts.getFont(subtitleFont, textStyle: style);
    } catch (_) {
      return style; // a font Google Fonts doesn't know: the app's own font instead
    }
  }

  // ── Saving ──

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_write()));
    } catch (e) {
      debugPrint('PlaybackSettings._save: $e');
    }
  }

  Map<String, dynamic> _write() => {
    'skip': {for (final e in skip.entries) e.key.name: e.value.name},
    'autoplayNext': autoplayNext,
    'countdownSeconds': countdownSeconds,
    'stillWatchingAfter': stillWatchingAfter,
    'wifiBitrate': wifiBitrate,
    'mobileBitrate': mobileBitrate,
    'streamMode': streamMode.name,
    'seekStep': seekStep,
    'seekAccelerates': seekAccelerates,
    'resume': resume.name,
    'subtitleFont': subtitleFont,
    'subtitleSize': subtitleSize.name,
    'subtitleColor': subtitleColor.name,
    'subtitleBackground': subtitleBackground.name,
    'liftSubtitles': liftSubtitles,
    'passthrough': passthrough,
    'downmix': downmix,
    'nightMode': nightMode,
    'showRating': showRating,
    'trickplay': trickplay,
    'aspect': aspect.name,
  };

  void _read(Map<String, dynamic> j) {
    // Each value falls back to its default if it's missing or from an older version.
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.asNameMap()[name] ?? fallback;
    bool flag(String key, bool fallback) => j[key] is bool ? j[key] as bool : fallback;
    int number(String key, int fallback) => j[key] is int ? j[key] as int : fallback;

    if (j['skip'] case final Map saved) {
      for (final k in SkipKind.values) {
        skip[k] = pick(SkipMode.values, saved[k.name], SkipMode.ask);
      }
    }
    autoplayNext = flag('autoplayNext', autoplayNext);
    countdownSeconds = number('countdownSeconds', countdownSeconds);
    stillWatchingAfter = number('stillWatchingAfter', stillWatchingAfter);
    wifiBitrate = number('wifiBitrate', wifiBitrate);
    mobileBitrate = number('mobileBitrate', mobileBitrate);
    streamMode = pick(StreamMode.values, j['streamMode'], streamMode);
    seekStep = number('seekStep', seekStep);
    seekAccelerates = flag('seekAccelerates', seekAccelerates);
    resume = pick(ResumeMode.values, j['resume'], resume);
    if (j['subtitleFont'] case final String f when f.isNotEmpty) subtitleFont = f;
    subtitleSize = pick(SubtitleSize.values, j['subtitleSize'], subtitleSize);
    subtitleColor = pick(SubtitleColor.values, j['subtitleColor'], subtitleColor);
    subtitleBackground = pick(SubtitleBackground.values, j['subtitleBackground'], subtitleBackground);
    liftSubtitles = flag('liftSubtitles', liftSubtitles);
    passthrough = flag('passthrough', passthrough);
    downmix = flag('downmix', downmix);
    nightMode = flag('nightMode', nightMode);
    showRating = flag('showRating', showRating);
    trickplay = flag('trickplay', trickplay);
    aspect = pick(AspectMode.values, j['aspect'], aspect);
  }
}

late final PlaybackSettings playbackSettings;

/// Subtitles drawn in the chosen style. For the outline style, the same text is drawn twice:
/// a thick black stroke underneath, then the filled letters on top, which gives a smooth,
/// even outline at any size.
class SubtitleText extends StatelessWidget {
  const SubtitleText(this.text, {super.key, required this.baseSize, this.height = 1.3});

  final String text;
  final double baseSize; // the medium size for this screen
  final double height;

  @override
  Widget build(BuildContext context) {
    final settings = playbackSettings;
    final style = settings.subtitleStyle(baseSize: baseSize, height: height);
    final fill = Text(text, textAlign: TextAlign.center, style: style);
    if (settings.subtitleBackground != SubtitleBackground.outline) return fill;

    final stroke = (style.fontSize ?? baseSize) * 0.14; // half of it shows outside the letters
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: style.copyWith(
            shadows: const [], // the fill on top keeps the shadow
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xFF000000),
          ),
        ),
        fill,
      ],
    );
  }
}