import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What this device can do with video and audio, asked of Android (see MainActivity.kt).
/// Elsewhere, and if Android can't say, everything is empty: nothing is assumed.
class MediaSupport {
  MediaSupport._();

  static const _channel = MethodChannel('chameleon/media');

  static Future<Set<String>>? _decoders;

  /// The video formats a hardware decoder can play: "avc", "hevc", "vp9", "av1", each also
  /// with "-10bit" when it handles 10-bit too. Empty on an emulator, whose "hardware"
  /// decoders can't draw straight to the screen.
  static Future<Set<String>> hardwareDecoders() => _decoders ??= () async {
    if (!Platform.isAndroid) return <String>{};
    try {
      if (!(await DeviceInfoPlugin().androidInfo).isPhysicalDevice) return <String>{};
      final list = await _channel.invokeListMethod<String>('hardwareDecoders');
      return {...?list};
    } catch (e) {
      debugPrint('Hardware decoders: $e');
      return <String>{};
    }
  }();

  /// The surround formats the current audio output takes as they are, in mpv's names ("ac3",
  /// "eac3", "dts", "dts-hd", "truehd"). Asked fresh each time, since a receiver can be
  /// switched on or off between videos.
  static Future<Set<String>> passthroughFormats() async {
    if (!Platform.isAndroid) return const {'ac3', 'eac3', 'dts', 'dts-hd', 'truehd'};
    try {
      final list = await _channel.invokeListMethod<String>('passthroughFormats');
      return {...?list};
    } catch (e) {
      debugPrint('Passthrough formats: $e');
      return const {};
    }
  }

  /// The [hardwareDecoders] name for a Jellyfin video stream (its Codec and BitDepth), or
  /// null for a format there's no name for.
  static String? decoderName(String? codec, int? bitDepth) {
    final base = switch (codec?.toLowerCase()) {
      'h264' || 'avc' => 'avc',
      'hevc' || 'h265' => 'hevc',
      'vp9' => 'vp9',
      'av1' => 'av1',
      _ => null,
    };
    if (base == null) return null;
    return (bitDepth ?? 8) > 8 ? '$base-10bit' : base;
  }
}
