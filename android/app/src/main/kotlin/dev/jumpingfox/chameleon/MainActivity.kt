package dev.jumpingfox.chameleon

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaCodecInfo
import android.media.MediaCodecInfo.CodecProfileLevel
import android.media.MediaCodecList
import android.os.Build
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onPostResume() {
        super.onPostResume()
        // With a D-pad or keyboard, Android outlines the focused view, which here is the whole
        // Flutter view (a green frame around the screen). The app draws its own focus instead.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) window.decorView.hideFocusHighlight()
    }

    private fun View.hideFocusHighlight() {
        defaultFocusHighlightEnabled = false
        if (this is ViewGroup) for (i in 0 until childCount) getChildAt(i).hideFocusHighlight()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Video frames reach Flutter through a SurfaceTexture rather than an ImageReader. Flutter
        // draws an ImageReader's whole buffer, ignoring the decoder's crop, so a decoder that pads
        // its frames (many TV chips round 2160 up to 2176, say) shows the padding as green edges.
        // A SurfaceTexture applies the crop. Only the video player (media_kit) creates these.
        FlutterRenderer.debugForceSurfaceProducerGlTextures = true
        super.configureFlutterEngine(flutterEngine)
        // What this device can do with video and audio, so the player picks how to play each file
        // (see lib/core/platform/media_support.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chameleon/media").setMethodCallHandler { call, result ->
            when (call.method) {
                "hardwareDecoders" -> result.success(hardwareDecoders())
                "passthroughFormats" -> result.success(passthroughFormats())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * The video formats a hardware decoder can play, by name: "avc", "avc-10bit", "hevc",
     * "hevc-10bit", "vp9", "vp9-10bit", "av1", "av1-10bit".
     */
    private fun hardwareDecoders(): List<String> {
        val found = mutableSetOf<String>()
        for (info in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
            if (info.isEncoder || !info.isHardware()) continue
            for (type in info.supportedTypes) {
                val profiles = try {
                    info.getCapabilitiesForType(type).profileLevels.map { it.profile }.toSet()
                } catch (_: IllegalArgumentException) {
                    continue
                }
                when (type.lowercase()) {
                    "video/avc" -> {
                        found += "avc"
                        if (CodecProfileLevel.AVCProfileHigh10 in profiles) found += "avc-10bit"
                    }
                    "video/hevc" -> {
                        found += "hevc"
                        if (profiles.any { it in HEVC_10BIT }) found += "hevc-10bit"
                    }
                    "video/x-vnd.on2.vp9" -> {
                        found += "vp9"
                        if (profiles.any { it in VP9_10BIT }) found += "vp9-10bit"
                    }
                    "video/av01" -> {
                        found += "av1"
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && profiles.any { it in av1TenBit() }) {
                            found += "av1-10bit"
                        }
                    }
                }
            }
        }
        return found.toList()
    }

    /** Android 10 says outright; before that, software decoders are the ones named for Google or Android. */
    private fun MediaCodecInfo.isHardware(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return isHardwareAccelerated && !isSoftwareOnly
        val n = name.lowercase()
        return !(n.startsWith("omx.google.") || n.startsWith("c2.android.") || n.contains(".sw."))
    }

    /**
     * The surround formats the current audio output (HDMI, a soundbar, ...) takes as they are:
     * "ac3", "eac3", "dts", "dts-hd", "truehd". mpv's names, for its audio-spdif option.
     */
    private fun passthroughFormats(): List<String> {
        val formats = mutableListOf(
            "ac3" to AudioFormat.ENCODING_AC3,
            "eac3" to AudioFormat.ENCODING_E_AC3,
            "dts" to AudioFormat.ENCODING_DTS,
            "dts-hd" to AudioFormat.ENCODING_DTS_HD,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) formats += "truehd" to AudioFormat.ENCODING_DOLBY_TRUEHD

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build()
            return formats.filter { (_, encoding) ->
                val format = AudioFormat.Builder()
                    .setEncoding(encoding)
                    .setSampleRate(48000)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                    .build()
                AudioTrack.isDirectPlaybackSupported(format, attributes)
            }.map { it.first }
        }

        // Older Android: what the connected HDMI or digital outputs list as their encodings.
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val digital = setOf(AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_HDMI_ARC, AudioDeviceInfo.TYPE_LINE_DIGITAL)
        val encodings = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .filter { it.type in digital }
            .flatMap { it.encodings.toList() }
            .toSet()
        return formats.filter { (_, encoding) -> encoding in encodings }.map { it.first }
    }

    private companion object {
        val HEVC_10BIT = setOf(
            CodecProfileLevel.HEVCProfileMain10,
            CodecProfileLevel.HEVCProfileMain10HDR10,
            CodecProfileLevel.HEVCProfileMain10HDR10Plus,
        )
        val VP9_10BIT = setOf(
            CodecProfileLevel.VP9Profile2,
            CodecProfileLevel.VP9Profile2HDR,
            CodecProfileLevel.VP9Profile2HDR10Plus,
        )

        fun av1TenBit() = setOf(
            CodecProfileLevel.AV1ProfileMain10,
            CodecProfileLevel.AV1ProfileMain10HDR10,
            CodecProfileLevel.AV1ProfileMain10HDR10Plus,
        )
    }
}
