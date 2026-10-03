import 'dart:convert';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_icons.dart';
import '../utils/font_controller.dart';
import '../utils/theme_controller.dart';
import '../utils/theme_presets.dart';
import '../utils/jellyfin_controller.dart';
import '../utils/orientation.dart';
import '../widgets/custom_theme_editor.dart';
import '../widgets/choice_picker.dart';
import '../widgets/app_logo.dart';
import '../widgets/profile_actions.dart';
import '../utils/account_settings.dart';
import '../utils/playback_settings.dart';
import '../widgets/focus_reveal.dart';
import '../widgets/switch_setting.dart';

/// Phone dropdowns draw their list in the app's top-level layer. The page's own layer is
/// clipped at the bottom nav bar, which cut lists off; the top-level one isn't. Together with
/// the shell telling pages where the nav bar starts, lists flip upwards when there's no room.
const _dropdownLayer = OverlayChildLocation.rootOverlay;

/// One entry per settings tab. Add a line here to add a tab.
typedef _SettingsTab = ({String label, Widget Function() build});

final _tabs = <_SettingsTab>[
  (label: 'Appearance', build: () => const _AppearanceCard()),
  (label: 'Account', build: () => const _AccountCard()),
  (label: 'Playback', build: () => const _PlaybackCard()),
  (label: 'Server', build: () => const _ServerCard()),
  (label: 'About', build: () => const _AboutCard()),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initialTab});

  /// The label of the tab to open on, e.g. 'Account'. Opens on the first tab if not given.
  final String? initialTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // indexWhere gives -1 for no match, so clamp falls back to the first tab.
  late int _index = _tabs.indexWhere((t) => t.label == widget.initialTab).clamp(0, _tabs.length - 1);
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FScaffold(
    // With the remote, keeps headings and the end of the page in view (see FocusReveal).
    child: FocusReveal(
      controller: _scroll,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        children: [
          // Tab pills, above the card.
          SingleChildScrollView(
            scrollDirection: Axis
                .horizontal, // scrolls sideways if there are more pills than fit
            child: Row(
              spacing: 8,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  FButton(
                    variant: i == _index ? .primary : .outline,
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: () => setState(() => _index = i),
                    child: Text(_tabs[i].label),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _tabs[_index].build(),
        ],
      ),
    ),
  );
}

/// A bordered card holding one settings tab. Use [_SectionTitle] for headings inside it.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => FCard(
    builder: (context, style, _) => Padding(
      padding: style.padding,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: children,
      ),
    ),
  );
}

class _FontPreview extends StatefulWidget {
  const _FontPreview(this.font);

  final String font;

  @override
  State<_FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<_FontPreview> {
  TextStyle? _style;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    // Fonts preloaded by the search show immediately, with no placeholder.
    if (loadedFonts.contains(widget.font)) {
      _style = GoogleFonts.getFont(widget.font);
      _requested = true;
    }
  }

  void _load() {
    if (_requested) return;
    _requested = true;
    preloadFonts([widget.font]).then((_) {
      if (mounted) setState(() => _style = GoogleFonts.getFont(widget.font));
    });
  }

  @override
  Widget build(BuildContext context) => VisibilityDetector(
    key: ValueKey('font-preview-${widget.font}'),
    onVisibilityChanged: (info) {
      if (info.visibleFraction > 0) _load();
    },
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _style == null
          ? Text(
        widget.font,
        key: const ValueKey('placeholder'),
        style: TextStyle(color: context.theme.colors.mutedForeground),
      )
          : Text(widget.font, key: const ValueKey('loaded'), style: _style),
    ),
  );
}

/// A font selector FSelect reusable widget
class _FontSelect extends StatelessWidget {
  const _FontSelect({
    required this.label,
    required this.value,
    required this.onChange,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    // Phones: a compact dropdown (touch only). Elsewhere: a field that opens a remote-friendly list.
    if (isPhoneLayout(context)) {
      return FSelect<String>.searchBuilder(
        label: Text(label),
        contentOverlayLocation: _dropdownLayer,
        format: (font) => font,
        filter: searchFonts,
        searchFieldProperties: const FSelectSearchFieldProperties(
          hint: 'Search Google Fonts',
        ),
        contentBuilder: (context, _, fonts) => [
          for (final font in fonts)
                .item(title: _FontPreview(font), value: font),
        ],
        control: FSelectControl.lifted(
          value: value,
          onChange: (font) {
            if (font != null) onChange(font);
          },
        ),
      );
    }

    return ChoiceField(
      label: label,
      value: value,
      onPress: () async {
        final picked = await showChoicePicker<String>(
          context: context,
          title: label,
          searchable: true,
          searchHint: 'Search Google Fonts',
          selected: value,
          search: (query) async => [...await searchFonts(query)],
          itemBuilder: (context, font) => _FontPreview(font),
        );
        if (picked != null) onChange(picked);
      },
    );
  }
}

/// Appearance Settings Tab
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([themeController, fontController, iconController, playbackSettings]),
    builder: (context, _) {
      final preset = themeController.value;
      // final isPhone = isPhoneLayout(context);

      return _SettingsCard(
        children: [
          // ── Fonts (each picks dropdown or choice field by itself) ──
          const _SectionTitle('Fonts', description: 'Any Google Font, for headings and for everything else.', first: true),
          _FontSelect(
            label: 'Header Font',
            value: fontController.display,
            onChange: fontController.setDisplay,
          ),
          const SizedBox(height: 16),
          _FontSelect(
            label: 'Body Font',
            value: fontController.body,
            onChange: fontController.setBody,
          ),
          const SizedBox(height: 16),
          _FontSelect(
            label: 'Subtitle Font',
            value: playbackSettings.subtitleFont,
            onChange: (font) => playbackSettings.change((s) => s.subtitleFont = font),
          ),

          // ── Theme ──
          const _SectionTitle('Theme', description: 'Pick a preset, or "Custom" to build your own.'),
          _PickerSetting<ThemePreset>(
            title: 'Theme',
            value: preset,
            options: themeController.allPresets.toList(),
            format: (p) => p.label,
            onChange: themeController.select,
          ),
          if (preset.id == customThemeId) ...[
            const SizedBox(height: 16),
            const CustomThemeEditor(),
          ],

          // ── Icons ──
          const _SectionTitle('Icons', description: 'The icon style used across the app.'),
          _PickerSetting<IconStyle>(
            title: 'Icons',
            value: iconController.value,
            options: IconStyle.values,
            format: (s) => s.label,
            onChange: iconController.select,
            // A small preview of each style.
            itemBuilder: (context, style) => Row(
              spacing: 12,
              children: [
                Icon(style.iconSet.play, size: 18, fill: 1),
                Icon(style.iconSet.favorite, size: 18, fill: 1),
                Text(style.label),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// Account Settings Tab
class _AccountCard extends StatefulWidget {
  const _AccountCard();

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  final _settings = AccountSettings();
  final _code = TextEditingController();
  String? _codeResult; // feedback under the Quick Connect field
  bool _codeOk = false;

  @override
  void initState() {
    super.initState();
    _settings.load();
  }

  @override
  void dispose() {
    _settings.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _authorize() async {
    final ok = await _settings.authorizeQuickConnect(_code.text);
    if (!mounted) return;
    setState(() {
      _codeOk = ok;
      _codeResult = ok
          ? 'Signed in. The other device should continue on its own.'
          : 'That code didn\'t work. Check it and try again. Codes expire after a few minutes.';
      if (ok) _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([jellyfin, _settings]),
    builder: (context, _) {
      final s = _settings;
      final muted = context.theme.typography.body.sm.copyWith(
        color: context.theme.colors.mutedForeground,
      );

      return _SettingsCard(
        children: [
          // ── Who's signed in ──
          const Center(child: UserAvatar(size: 80)),
          const SizedBox(height: 8),
          Text(
            jellyfin.userName ?? 'Not signed in',
            textAlign: TextAlign.center,
            style: context.theme.typography.display.lg,
          ),
          if (jellyfin.lastServer != null) ...[
            const SizedBox(height: 4),
            Text(jellyfin.lastServer!, textAlign: TextAlign.center, style: muted),
          ],
          const SizedBox(height: 8),
          const FDivider(),

          // ── Switch user / sign out ──
          for (final action in profileActions(context)) ...[
            FButton(
              variant: .outline,
              mainAxisAlignment: .start,
              onPress: action.onPress,
              child: Row(
                spacing: 12,
                children: [
                  Icon(action.icon, size: 20, fill: 1),
                  Text(action.label),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Server-side preferences ──
          const _SectionTitle(
            'Languages & Subtitles',
            description: 'Saved to your Jellyfin account, so other apps use them too.',
          ),

          if (s.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: FCircularProgress()),
            )
          else ...[
            if (s.error != null) ...[
              Text(s.error!, style: muted.copyWith(color: context.theme.colors.error)),
              const SizedBox(height: 8),
            ],
            _PickerSetting<Language>(
              label: 'Audio language',
              value: s.audioLanguage,
              options: s.languages,
              format: (l) => l.name,
              searchable: true,
              onChange: s.setAudioLanguage,
            ),
            const SizedBox(height: 16),
            _PickerSetting<Language>(
              label: 'Subtitle language',
              value: s.subtitleLanguage,
              options: s.languages,
              format: (l) => l.name,
              searchable: true,
              onChange: s.setSubtitleLanguage,
            ),
            const SizedBox(height: 16),
            _PickerSetting<SubtitleMode>(
              label: 'When to show subtitles',
              value: s.subtitleMode,
              options: SubtitleMode.values,
              format: (m) => m.label,
              onChange: s.setSubtitleMode,
            ),

            // ── Parental controls (read-only) ──
            _SectionTitle(
              'Parental Controls',
              description: s.isAdmin ? null : 'Set by your server\'s admin in the Jellyfin dashboard.',
            ),
            Text(s.maxRating == null ? 'No rating limit.' : 'Limited to ${s.maxRating} and below.'),

            // ── Quick Connect ──
            if (s.quickConnectEnabled) ...[
              const _SectionTitle(
                'Quick Connect',
                description: 'Signing in on another device? Choose Quick Connect there, then enter the code it shows.',
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: FTextField(
                      control: .managed(controller: _code),
                      hint: 'Code, e.g. 123456',
                      keyboardType: TextInputType.number,
                      onSubmit: (_) => _authorize(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FButton(
                    mainAxisSize: .min,
                    onPress: _authorize,
                    child: const Text('Sign in'),
                  ),
                ],
              ),
              if (_codeResult != null) ...[
                const SizedBox(height: 6),
                Text(
                  _codeResult!,
                  style: muted.copyWith(
                    color: _codeOk ? context.theme.colors.primary : context.theme.colors.error,
                  ),
                ),
              ],
            ],
          ],
        ],
      );
    },
  );
}

/// A heading inside a settings card, with an optional line of explanation under it.
/// Brings its own spacing: a gap above (unless [first]) and a smaller one below.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.description, this.first = false});

  final String text;
  final String? description;
  final bool first; // the card's first heading, so no gap above

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 28, bottom: 12),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 2,
        children: [
          Text(text, style: theme.typography.display.md.copyWith(fontWeight: FontWeight.w600)),
          if (description != null)
            Text(
              description!,
              style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
            ),
        ],
      ),
    );
  }
}

/// A setting with a list of choices: a dropdown on phones, a remote-friendly picker elsewhere.
/// Same split as the Appearance tab.
class _PickerSetting<T> extends StatelessWidget {
  const _PickerSetting({
    this.label,
    this.title,
    required this.value,
    required this.options,
    required this.format,
    required this.onChange,
    this.searchable = false,
    this.itemBuilder,
  });

  final String? label;
  final String? title;
  final T value;
  final List<T> options;
  final String Function(T) format;
  final ValueChanged<T> onChange;
  final bool searchable; // for long lists like languages

  /// How each choice looks in the list. Defaults to its name.
  final Widget Function(BuildContext context, T option)? itemBuilder;

  Widget _item(BuildContext context, T option) => itemBuilder?.call(context, option) ?? Text(format(option));

  List<T> _filter(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ? options : options.where((o) => format(o).toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (isPhoneLayout(context)) {
      final control = FSelectControl<T>.lifted(
        value: value,
        onChange: (v) {
          if (v != null) onChange(v);
        },
      );
      if (searchable) {
        return FSelect<T>.searchBuilder(
          label: label == null ? null : Text(label!),
          contentOverlayLocation: _dropdownLayer,
          format: format,
          filter: _filter,
          contentBuilder: (context, _, items) => [
            for (final item in items) .item(title: _item(context, item), value: item),
          ],
          control: control,
        );
      }
      return FSelect<T>(
        label: label == null ? null : Text(label!),
        contentOverlayLocation: _dropdownLayer,
        items: {for (final o in options) format(o): o},
        control: control,
      );
    }
    return ChoiceField(
      label: label,
      value: format(value),
      onPress: () async {
        final picked = await showChoicePicker<T>(
          context: context,
          title: title ?? label ?? '',
          searchable: searchable,
          searchHint: 'Search',
          selected: value,
          search: (query) async => _filter(query),
          itemBuilder: _item,
        );
        if (picked != null) onChange(picked);
      },
    );
  }
}

/// Playback Settings Tab. Saved on this device, and used from the next video you play.
class _PlaybackCard extends StatelessWidget {
  const _PlaybackCard();

  static const _gap = SizedBox(height: 16);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playbackSettings,
    builder: (context, _) {
      final s = playbackSettings;
      void update(void Function(PlaybackSettings s) edit) => s.change(edit);

      return _SettingsCard(
        children: [
          // ── Skipping ──
          const _SectionTitle(
            'Skipping',
            description: 'What happens when an intro, recap, credits or preview starts. '
                'Needs Media Segments on your server, or chapters named "Intro", "Credits" and so on.',
            first: true,
          ),
          for (final (i, kind) in SkipKind.values.indexed) ...[
            if (i > 0) _gap,
            _PickerSetting<SkipMode>(
              label: kind.label,
              value: s.skip[kind]!,
              options: SkipMode.values,
              format: (m) => m.label,
              onChange: (m) => update((s) => s.skip[kind] = m),
            ),
          ],

          // ── Up next ──
          const _SectionTitle('Up Next', description: 'When an episode ends.'),
          SwitchSetting(
            label: 'Autoplay next episode',
            description: 'Counts down during the credits, then plays the next one.',
            value: s.autoplayNext,
            onChange: (v) => update((s) => s.autoplayNext = v),
          ),
          if (s.autoplayNext) ...[
            _gap,
            _PickerSetting<int>(
              label: 'Countdown',
              value: s.countdownSeconds,
              options: countdownOptions,
              format: (n) => '$n seconds',
              onChange: (n) => update((s) => s.countdownSeconds = n),
            ),
            _gap,
            _PickerSetting<int>(
              label: 'Ask "Are you still watching?"',
              value: s.stillWatchingAfter,
              options: stillWatchingOptions,
              format: (n) => n == 0 ? 'Never' : 'After $n episodes in a row',
              onChange: (n) => update((s) => s.stillWatchingAfter = n),
            ),
          ],

          // ── Quality ──
          const _SectionTitle(
            'Streaming Quality',
            description: 'Lower it if videos keep buffering. Above the limit, the server converts '
                'the video to a smaller size while you watch.',
          ),
          _PickerSetting<int>(
            label: 'On Wi-Fi or Ethernet',
            value: s.wifiBitrate,
            options: bitrateOptions,
            format: bitrateLabel,
            onChange: (b) => update((s) => s.wifiBitrate = b),
          ),
          _gap,
          _PickerSetting<int>(
            label: 'On mobile data',
            value: s.mobileBitrate,
            options: bitrateOptions,
            format: bitrateLabel,
            onChange: (b) => update((s) => s.mobileBitrate = b),
          ),
          _gap,
          _PickerSetting<StreamMode>(
            label: 'Direct play',
            value: s.streamMode,
            options: StreamMode.values,
            format: (m) => m.label,
            onChange: (m) => update((s) => s.streamMode = m),
          ),

          // ── Seeking ──
          const _SectionTitle('Seeking', description: 'Left and right on the remote, and double-tap on phones.'),
          _PickerSetting<int>(
            label: 'Jump by',
            value: s.seekStep,
            options: seekStepOptions,
            format: (n) => '$n seconds',
            onChange: (n) => update((s) => s.seekStep = n),
          ),
          _gap,
          SwitchSetting(
            label: 'Speed up when held',
            description: 'Holding left or right jumps further the longer you hold.',
            value: s.seekAccelerates,
            onChange: (v) => update((s) => s.seekAccelerates = v),
          ),

          // ── Resuming ──
          const _SectionTitle('Resuming', description: 'Playing something you stopped partway through.'),
          _PickerSetting<ResumeMode>(
            label: 'When you come back',
            value: s.resume,
            options: ResumeMode.values,
            format: (m) => m.label,
            onChange: (m) => update((s) => s.resume = m),
          ),

          // ── Subtitles ──
          const _SectionTitle(
            'Subtitle Appearance',
            description: 'For text subtitles. Picture subtitles (like Blu-ray PGS) keep their own look.',
          ),
          // ignore: prefer_const_constructors
          _SubtitlePreview(), // not const, so it redraws when a setting changes
          _gap,
          _PickerSetting<SubtitleSize>(
            label: 'Size',
            value: s.subtitleSize,
            options: SubtitleSize.values,
            format: (v) => v.label,
            onChange: (v) => update((s) => s.subtitleSize = v),
          ),
          _gap,
          _PickerSetting<SubtitlePosition>(
            label: 'Height',
            value: s.subtitlePosition,
            options: SubtitlePosition.values,
            format: (p) => p.label,
            onChange: (p) => update((s) => s.subtitlePosition = p),
          ),
          _gap,
          _PickerSetting<SubtitleColor>(
            label: 'Color',
            value: s.subtitleColor,
            options: SubtitleColor.values,
            format: (v) => v.label,
            onChange: (v) => update((s) => s.subtitleColor = v),
            itemBuilder: (context, c) => Row(
              spacing: 12,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: c.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.theme.colors.border),
                  ),
                ),
                Text(c.label),
              ],
            ),
          ),
          _gap,
          _PickerSetting<SubtitleBackground>(
            label: 'Style',
            value: s.subtitleBackground,
            options: SubtitleBackground.values,
            format: (v) => v.label,
            onChange: (v) => update((s) => s.subtitleBackground = v),
          ),
          _gap,
          SwitchSetting(
            label: 'Move up when controls show',
            description: 'Keeps subtitles above the seek bar instead of behind it.',
            value: s.liftSubtitles,
            onChange: (v) => update((s) => s.liftSubtitles = v),
          ),

          // ── Audio ──
          const _SectionTitle('Audio'),
          SwitchSetting(
            label: 'Surround sound passthrough',
            description: 'Sends Dolby and DTS audio untouched to a soundbar or receiver that decodes it. '
                'Turn off if you hear nothing.',
            value: s.passthrough,
            onChange: (v) => update((s) => s.passthrough = v),
          ),
          _gap,
          SwitchSetting(
            label: 'Mix down to stereo',
            description: s.passthrough
                ? 'Not available with passthrough on.'
                : 'For headphones and TV speakers, so dialogue from the center channel isn\'t lost.',
            value: s.downmix && !s.passthrough,
            enabled: !s.passthrough,
            onChange: (v) => update((s) => s.downmix = v),
          ),
          _gap,
          SwitchSetting(
            label: 'Night mode',
            description: s.passthrough
                ? 'Not available with passthrough on.'
                : 'Quiets explosions and lifts quiet dialogue, so you can keep the volume down.',
            value: s.nightMode && !s.passthrough,
            enabled: !s.passthrough,
            onChange: (v) => update((s) => s.nightMode = v),
          ),

          // ── Display ──
          const _SectionTitle('Display'),
          _PickerSetting<AspectMode>(
            label: 'Picture size',
            value: s.aspect,
            options: AspectMode.values,
            format: (m) => m.label,
            onChange: (m) => update((s) => s.aspect = m),
          ),
          _gap,
          SwitchSetting(
            label: 'Show the age rating',
            description: 'Slides in the rating card when a video starts.',
            value: s.showRating,
            onChange: (v) => update((s) => s.showRating = v),
          ),
          _gap,
          SwitchSetting(
            label: 'Scrubbing previews',
            description: 'Thumbnails above the seek bar. Turn off on slow devices or connections.',
            value: s.trickplay,
            onChange: (v) => update((s) => s.trickplay = v),
          ),
        ],
      );
    },
  );
}

/// A sample line of subtitles over a dark, picture-like background, in the chosen style.
class _SubtitlePreview extends StatelessWidget {
  const _SubtitlePreview();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 120,
      alignment: Alignment.bottomCenter,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 6 + 120 * playbackSettings.subtitlePosition.raise),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A4A5C), Color(0xFF8A7560), Color(0xFFD9C7A8)],
        ),
      ),
      // ignore: prefer_const_constructors
      child: SubtitleText('This is how subtitles will look.', baseSize: 18, height: 1.2),
    ),
  );
}

/// Server Settings Tab
class _ServerCard extends StatelessWidget {
  const _ServerCard();

  @override
  Widget build(BuildContext context) {
    return const _SettingsCard(
      children: [
        _SectionTitle('Server', description: 'Coming soon.', first: true),
      ],
    );
  }
}

/// About Settings Tab
class _AboutCard extends StatefulWidget {
  const _AboutCard();

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  // Fetched once when the tab opens, not on every rebuild.
  late final Future<PackageInfo> _app = PackageInfo.fromPlatform();
  late final Future<({String name, String version})?> _server = _serverInfo();

  /// The server's public info. Needs no sign-in, so it works even if the session expired.
  static Future<({String name, String version})?> _serverInfo() async {
    final baseUrl = jellyfin.client?.baseUrl;
    if (baseUrl == null) return null;

    try {
      final res = await http
          .get(Uri.parse('$baseUrl/System/Info/Public'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return (
      name: json['ServerName'] as String? ?? 'Jellyfin',
      version: json['Version'] as String? ?? 'Unknown',
      );
    } catch (_) {
      return null; // offline, timed out, or not a Jellyfin server
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsCard(
    children: [
      const Align(
        alignment: Alignment.center,
        child: AppLogo(
          asset: 'assets/images/text_logo.svg',
          colorAsset: 'assets/images/text_logo_color.svg',
          height: 48,
          variant: AppLogoVariant.auto,
        ),
      ),

      const SizedBox(height: 8),
      const FDivider(),

      // ── App ──
      const _SectionTitle('App', first: true),
      FutureBuilder(
        future: _app,
        builder: (context, snap) => _InfoRow(
          label: 'Version',
          value: snap.hasData ? '${snap.data!.version} (${snap.data!.buildNumber})' : '…',
        ),
      ),

      // ── Server ──
      const _SectionTitle('Server'),
      FutureBuilder(
        future: _server,
        builder: (context, snap) {
          final waiting = snap.connectionState != ConnectionState.done;
          final info = snap.data;
          return Column(
            crossAxisAlignment: .stretch,
            children: [
              _InfoRow(label: 'Server', value: waiting ? '…' : info?.name ?? 'Unreachable'),
              _InfoRow(label: 'Server version', value: waiting ? '…' : info?.version ?? '—'),
            ],
          );
        },
      ),
      _InfoRow(label: 'Address', value: jellyfin.client?.baseUrl ?? 'Not connected'),

      // ── Licenses ──
      const _SectionTitle('Licenses', description: 'The open-source packages this app is built on.'),
      FutureBuilder(
        future: _app,
        builder: (context, snap) => FButton(
          variant: .outline,
          mainAxisSize: .min,
          onPress: () => showLicensePage(
            context: context,
            applicationName: 'Chameleon',
            applicationVersion: snap.data?.version,
          ),
          child: const Text('Open-source licenses'),
        ),
      ),

      // ── Credits ──
      const _SectionTitle('Credits'),
      Text(
        'Built with Flutter and forui. Plays media with media_kit.\n'
            'Icons: Material Symbols, Phosphor, Lucide, Cupertino and Fluent UI.\n'
            'Fonts from Google Fonts. Not affiliated with the Jellyfin project.',
        style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground),
      ),
    ],
  );
}

/// A label on the left, its value on the right.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.theme.colors.mutedForeground),
          ),
        ),
      ],
    ),
  );
}