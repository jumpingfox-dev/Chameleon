import 'dart:async';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:media_kit/media_kit.dart';

/// Tells Jellyfin what's playing and where, so progress, Continue Watching and Next Up
/// stay current in this app and every other Jellyfin client.
class PlaybackReporter {
  PlaybackReporter({
    required this.client,
    required this.itemId,
    required this.player,
  });

  final JellyfinClient client;
  final String itemId;
  final Player player;

  static const _interval = Duration(seconds: 10);

  Timer? _timer;
  StreamSubscription<bool>? _playing;

  Future<void> start() async {
    await _post('/Sessions/Playing', _state());
    _timer = Timer.periodic(
      _interval,
      (_) => _post('/Sessions/Playing/Progress', _state()),
    );
    // Report pauses and resumes straight away rather than on the next tick.
    _playing = player.stream.playing.listen(
      (_) => _post('/Sessions/Playing/Progress', _state()),
    );
  }

  /// Reports the final position. Reads it immediately, so it's safe to dispose the player right after.
  Future<void> stop() {
    final state = _state();
    _timer?.cancel();
    _playing?.cancel();
    return _post('/Sessions/Playing/Stopped', state);
  }

  Map<String, Object?> _state() => {
    'ItemId': itemId,
    'PositionTicks':
        player.state.position.inMicroseconds *
        10, // Jellyfin counts in 100 ns ticks
    'IsPaused': !player.state.playing,
    'CanSeek': true,
    'PlayMethod': 'DirectPlay',
  };

  Future<void> _post(String path, Map<String, Object?> body) async {
    try {
      await client.request(path, method: 'POST', data: body);
    } catch (_) {
      // Best effort: a missed report must never interrupt playback.
    }
  }
}
