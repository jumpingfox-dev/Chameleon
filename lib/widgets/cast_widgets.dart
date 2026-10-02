import 'dart:io';

import 'package:dart_jellyfin/dart_jellyfin.dart' show JellyfinItem;
import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart' show CastMediaPlayerState;
import 'package:flutter_to_airplay/flutter_to_airplay.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/cast_controller.dart';
import '../utils/jellyfin_controller.dart';

// ─── Choosing a Chromecast ───────────────────────────────────────────────────

/// Not casting: lists the Chromecasts on the network. Casting: offers to stop.
Future<void> showCastPicker(BuildContext context) => showFDialog<void>(
  context: context,
  builder: (context, style, animation) => FDialog(
    animation: animation,
    builder: (context, _) => const _CastPickerBody(),
  ),
);

class _CastPickerBody extends StatelessWidget {
  const _CastPickerBody();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final muted = theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground);

    return ListenableBuilder(
      listenable: castController,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 10,
          children: [
            if (castController.isConnected) ...[
              Text('Casting to ${castController.deviceName ?? 'a Chromecast'}', style: theme.typography.display.lg),
              if (castController.nowPlaying != null) Text(castController.nowPlaying!.title, style: muted),
              const SizedBox(height: 4),
              FButton(
                autofocus: true,
                onPress: () {
                  castController.disconnect();
                  Navigator.of(context).pop();
                },
                child: const Text('Stop casting'),
              ),
            ] else ...[
              Text('Cast to', style: theme.typography.display.lg),
              if (castController.devices.isEmpty)
                Text('Looking for Chromecasts on your network…', style: muted)
              else
                for (final (i, device) in castController.devices.indexed)
                  FButton(
                    variant: .outline,
                    mainAxisAlignment: .start,
                    autofocus: i == 0,
                    onPress: () {
                      castController.connect(device);
                      Navigator.of(context).pop();
                    },
                    child: Row(
                      spacing: 12,
                      children: [
                        const Icon(Icons.cast_rounded, size: 20),
                        Flexible(child: Text(device.friendlyName, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
            ],
            FButton(variant: .outline, onPress: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

/// Whether to show a cast button: only when a Chromecast is around (or already casting),
/// as Google's guidelines ask, so it never shows on a TV or with no Chromecast at home.
bool get showCastButton =>
    castController.supported && (castController.isConnected || castController.devices.isNotEmpty);

IconData get castIcon => castController.isConnected ? Icons.cast_connected_rounded : Icons.cast_rounded;

// ─── AirPlay (iPhone and iPad) ───────────────────────────────────────────────

/// Apple's own AirPlay button, which opens the system's device list. iOS only.
///
/// The player plays through mpv rather than Apple's player, so AirPlay carries the sound
/// (to an Apple TV, HomePod or AirPlay speaker); for the picture on an Apple TV, use
/// Screen Mirroring in Control Center.
class AirPlayButton extends StatelessWidget {
  const AirPlayButton({super.key, this.size = 44});

  final double size;

  static bool get available => !kIsWeb && Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    if (!available) return const SizedBox.shrink();
    return Tooltip(
      message: 'AirPlay',
      child: AirPlayRoutePickerView(
        width: size,
        height: size,
        prioritizesVideoDevices: true,
        tintColor: const Color(0xFFFFFFFF),
        activeTintColor: context.theme.colors.primary,
        backgroundColor: const Color(0x00000000),
      ),
    );
  }
}

// ─── The remote, while casting ───────────────────────────────────────────────

/// Fills the player while the video plays on a Chromecast: what's playing, where it is,
/// and the controls, which all drive the Chromecast.
class CastRemote extends StatelessWidget {
  const CastRemote({
    super.key,
    required this.item,
    required this.onBack,
    required this.onAudio,
    required this.onSubtitles,
  });

  final JellyfinItem item;
  final VoidCallback onBack; // leaves the player; casting carries on
  final VoidCallback onAudio;
  final VoidCallback onSubtitles;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    const white = Color(0xFFFFFFFF);
    const dim = Color(0xB3FFFFFF);
    final base = jellyfin.client?.baseUrl;
    final backdrop = (item.raw['BackdropImageTags'] as List?)?.firstOrNull as String?;
    final backdropId = backdrop != null ? item.id : item.raw['ParentBackdropItemId'] as String?;
    final backdropTag = backdrop ?? ((item.raw['ParentBackdropImageTags'] as List?)?.firstOrNull as String?);

    return ListenableBuilder(
      listenable: castController,
      builder: (context, _) {
        final now = castController.nowPlaying;
        final buffering = castController.playerState == CastMediaPlayerState.buffering ||
            castController.playerState == CastMediaPlayerState.loading;

        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF000000)),
            if (base != null && backdropId != null && backdropTag != null)
              Opacity(
                opacity: 0.35,
                child: Image.network(
                  '$base/Items/$backdropId/Images/Backdrop?maxWidth=1280&tag=$backdropTag',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    Row(
                      children: [
                        _RemoteButton(icon: Icons.arrow_back_rounded, label: 'Back', onPress: onBack),
                        const Spacer(),
                        _RemoteButton(icon: Icons.graphic_eq_rounded, label: 'Audio', onPress: onAudio),
                        _RemoteButton(icon: Icons.subtitles_rounded, label: 'Subtitles', onPress: onSubtitles),
                        _RemoteButton(
                          icon: Icons.cast_connected_rounded,
                          label: 'Stop casting',
                          onPress: () => showCastPicker(context),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.cast_connected_rounded, size: 40, color: dim),
                    const SizedBox(height: 8),
                    Text(
                      'Casting to ${castController.deviceName ?? 'Chromecast'}',
                      textAlign: TextAlign.center,
                      style: theme.typography.body.sm.copyWith(color: dim),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      now?.title ?? item.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.display.xl.copyWith(color: white),
                    ),
                    const Spacer(),
                    StreamBuilder<Duration>(
                      stream: castController.positionStream,
                      initialData: castController.position,
                      builder: (context, snap) => _RemoteSeekBar(
                        position: snap.data ?? Duration.zero,
                        duration: now?.runtime ?? Duration.zero,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 40,
                      children: [
                        _RemoteButton(
                          icon: Icons.replay_10_rounded,
                          label: 'Back 10 seconds',
                          size: 36,
                          onPress: () => castController.seek(castController.position - const Duration(seconds: 10)),
                        ),
                        buffering
                            ? const SizedBox(width: 64, height: 64, child: Center(child: FCircularProgress()))
                            : _RemoteButton(
                                icon: castController.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                label: castController.isPlaying ? 'Pause' : 'Play',
                                size: 52,
                                onPress: castController.playOrPause,
                              ),
                        _RemoteButton(
                          icon: Icons.forward_10_rounded,
                          label: 'Forward 10 seconds',
                          size: 36,
                          onPress: () => castController.seek(castController.position + const Duration(seconds: 10)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RemoteButton extends StatelessWidget {
  const _RemoteButton({required this.icon, required this.label, required this.onPress, this.size = 26});

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
      builder: (context, states, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: states.contains(FTappableVariant.focused) || states.contains(FTappableVariant.hovered)
              ? const Color(0x33FFFFFF)
              : const Color(0x00FFFFFF),
        ),
        child: Icon(icon, size: size, color: const Color(0xFFFFFFFF)),
      ),
    ),
  );
}

/// A simple slider for the Chromecast's position; drag to seek.
class _RemoteSeekBar extends StatefulWidget {
  const _RemoteSeekBar({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  State<_RemoteSeekBar> createState() => _RemoteSeekBarState();
}

class _RemoteSeekBarState extends State<_RemoteSeekBar> {
  double? _dragging; // 0..1 while the thumb is held

  static String _format(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds;
    final fraction = _dragging ?? (total <= 0 ? 0.0 : (widget.position.inMilliseconds / total).clamp(0.0, 1.0));
    final shown = _dragging == null ? widget.position : widget.duration * fraction;
    const dim = Color(0xB3FFFFFF);
    final timeStyle = context.theme.typography.body.sm.copyWith(color: dim);

    return Column(
      mainAxisSize: .min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: context.theme.colors.primary,
            inactiveTrackColor: const Color(0x4DFFFFFF),
            thumbColor: const Color(0xFFFFFFFF),
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: fraction,
            onChanged: total <= 0 ? null : (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              castController.seek(widget.duration * v);
              setState(() => _dragging = null);
            },
          ),
        ),
        Row(
          children: [
            Text(_format(shown), style: timeStyle),
            const Spacer(),
            Text(_format(widget.duration), style: timeStyle),
          ],
        ),
      ],
    );
  }
}
