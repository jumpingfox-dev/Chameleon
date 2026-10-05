import 'dart:async';
import 'dart:convert';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_icons.dart';
import '../theme/tappable_states.dart';
import '../utils/font_controller.dart';
import '../utils/theme_controller.dart';
import '../utils/theme_presets.dart';
import '../utils/jellyfin_controller.dart';
import '../utils/orientation.dart';
import '../utils/sync_play_controller.dart';
import '../utils/account_settings.dart';
import '../utils/playback_settings.dart';
import '../widgets/custom_theme_editor.dart';
import '../widgets/choice_picker.dart';
import '../widgets/app_logo.dart';
import '../widgets/profile_actions.dart';
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
  (label: 'SyncPlay', build: () => const _SyncPlayCard()),
  (label: 'About', build: () => const _AboutCard()),
];

/// The settings page names in order, for the sidebar.
List<String> get settingsTabLabels => [for (final t in _tabs) t.label];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initialTab});

  /// The label of the tab to open on, e.g. 'Account'. Opens on the first tab if not given.
  final String? initialTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // indexWhere gives -1 for no match, so clamp falls back to the first tab.
  late int _index = _indexOf(widget.initialTab);
  final _scroll = ScrollController();

  static int _indexOf(String? label) =>
      _tabs.indexWhere((t) => t.label == label).clamp(0, _tabs.length - 1);

  @override
  void didUpdateWidget(covariant SettingsScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialTab != old.initialTab) _index = _indexOf(widget.initialTab);
  }

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
          // Tab pills, above the card. Phones only: wider screens pick the page from the sidebar.
          if (isPhoneLayout(context)) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal, // scrolls sideways if there are more pills than fit
              child: Row(
                spacing: 8,
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    FButton(
                      variant: i == _index ? .primary : .outline,
                      size: .sm,
                      mainAxisSize: .min,
                      // Through the address, so the sidebar shows the same page as selected.
                      onPress: () => context.go('${GoRouterState.of(context).uri.path}?tab=${_tabs[i].label}'),
                      child: Text(_tabs[i].label),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  FTextField(
                    control: .managed(controller: _code),
                    hint: 'Code, e.g. 123456',
                    keyboardType: TextInputType.number,
                    onSubmit: (_) => _authorize(),
                  ),
                  FButton(
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
    // Just a placeholder for now, kept as its own tab since it already has a spot reserved
    // in the sidebar and the icon style.
    return const _SettingsCard(
      children: [
        _SectionTitle('Server', description: 'Coming soon.', first: true),
      ],
    );
  }
}

// TODO(cleanup): the SyncPlay widgets are a third of this file; move them into their own part
/// SyncPlay Tab
class _SyncPlayCard extends StatefulWidget {
  const _SyncPlayCard();

  @override
  State<_SyncPlayCard> createState() => _SyncPlayCardState();
}

class _SyncPlayCardState extends State<_SyncPlayCard> {
  late final _name = TextEditingController(text: "${jellyfin.userName ?? 'My'}'s group");
  List<SyncPlayGroup> _groups = const [];
  bool _loading = true;
  bool _busy = false; // creating, joining or leaving
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Keep the list current (new groups, what they're watching) while the tab is open.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!syncPlay.inGroup && !_busy) _refresh(quiet: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _name.dispose();
    super.dispose();
  }

  /// [quiet]: an automatic refresh, so no spinner in place of the list.
  Future<void> _refresh({bool quiet = false}) async {
    setState(() {
      if (!quiet) _loading = true;
      _error = null;
    });
    try {
      final groups = await syncPlay.groups();
      if (mounted) setState(() => _groups = groups);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't load groups. Your server may have SyncPlay turned off.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Runs [action], disabling the buttons meanwhile and showing any error under them.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = "That didn't work. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: syncPlay,
    builder: (context, _) {
      final theme = context.theme;
      final muted = theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground);
      final message = _error ?? syncPlay.message;

      return _SettingsCard(
        children: [
          if (syncPlay.inGroup) ...[
            // ── In a group ──
            _SectionTitle(
              syncPlay.groupName ?? 'SyncPlay group',
              description: 'Play anything and everyone here watches it with you. '
                  'Anyone can pause, seek or skip, and it happens for the whole group.',
              first: true,
            ),
            // What the group is watching: select it to jump in.
            if (syncPlay.current case final entry?)
              _SyncPlayNowPlaying(itemId: entry.itemId, playerOpen: syncPlay.playerOpen)
            else
              Text('Nothing playing yet. Pick something to watch.', style: muted),

            const _SectionTitle('In this group'),
            for (final member in syncPlay.members)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  spacing: 10,
                  children: [
                    Icon(appIcons.profile, size: 18, fill: 1, color: theme.colors.mutedForeground),
                    Expanded(child: Text(member)),
                    if (member == jellyfin.userName) Text('You', style: muted),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            FButton(
              variant: .outline,
              mainAxisSize: .min,
              onPress: _busy
                  ? null
                  : () => _run(() async {
                await syncPlay.leave();
                await _refresh();
              }),
              child: const Text('Leave group'),
            ),
          ] else ...[
            // ── Join one ──
            const _SectionTitle(
              'Join a Group',
              description: 'Select a group to join it. If it is watching something, '
                  'you jump straight in where they are.',
              first: true,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: FCircularProgress()),
              )
            else if (_groups.isEmpty)
              Text('No groups right now. Start one below, or ask someone to.', style: muted)
            else
              for (final (i, group) in _groups.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                _SyncPlayGroupTile(
                  group: group,
                  onJoin: _busy ? null : () => _run(() => syncPlay.join(group.id)),
                ),
              ],

            // ── Or start one ──
            const _SectionTitle(
              'Start a Group',
              description: 'Make a group, then have others join it from their own device. '
                  "Jellyfin's web app and other apps with SyncPlay can join too.",
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                FTextField(control: .managed(controller: _name), hint: 'Group name'),
                FButton(
                  onPress: _busy
                      ? null
                      : () => _run(() => syncPlay.create(
                        _name.text.trim().isEmpty ? 'SyncPlay group' : _name.text.trim(),
                      )),
                  child: const Text('Create'),
                ),
              ],
            ),
          ],

          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message, style: muted.copyWith(color: _error != null ? theme.colors.error : null)),
          ],
        ],
      );
    },
  );
}

/// A group you can join, shown by what it's watching when that's known.
class _SyncPlayGroupTile extends StatelessWidget {
  const _SyncPlayGroupTile({required this.group, required this.onJoin});

  final SyncPlayGroup group;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final watching = group.watching;
    final people = group.members.join(', ');
    return _SyncPlayTile(
      imageUrl: watching?.imageUrl,
      title: watching?.title ?? group.name,
      lines: [
        if (watching?.subtitle case final subtitle? when subtitle.isNotEmpty) subtitle,
        watching == null ? people : '${group.name} · $people',
      ],
      action: 'Join',
      onPress: onJoin,
    );
  }
}

/// What the group is watching, in the same tile as the groups list. Selecting it opens the
/// player at the group's spot; once the player is open, it just says so.
class _SyncPlayNowPlaying extends StatefulWidget {
  const _SyncPlayNowPlaying({required this.itemId, required this.playerOpen});

  final String itemId;
  final bool playerOpen;

  @override
  State<_SyncPlayNowPlaying> createState() => _SyncPlayNowPlayingState();
}

class _SyncPlayNowPlayingState extends State<_SyncPlayNowPlaying> {
  late Future<JellyfinItem?> _item = jellyfin.client!.items.byId(widget.itemId);

  @override
  void didUpdateWidget(covariant _SyncPlayNowPlaying old) {
    super.didUpdateWidget(old);
    if (old.itemId != widget.itemId) _item = jellyfin.client!.items.byId(widget.itemId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<JellyfinItem?>(
    future: _item,
    builder: (context, snap) {
      final item = snap.data;
      final isEpisode = item?.type == JellyfinItemKind.episode;
      final season = item?.raw['ParentIndexNumber'], episode = item?.raw['IndexNumber'];

      return _SyncPlayTile(
        imageUrl: item == null ? null : _wideImage(item),
        title: item == null
            ? 'Loading…'
            : isEpisode
            ? (item.raw['SeriesName'] as String?) ?? item.name
            : item.name,
        // TODO(cleanup): shared episode-label helper
        lines: [
          if (item != null && isEpisode)
            [if (season != null && episode != null) 'S$season:E$episode', item.name].join(' · ')
          else if (item?.raw['ProductionYear'] case final year?)
            '$year',
          if (widget.playerOpen) "You're watching along.",
        ],
        action: widget.playerOpen ? null : 'Join Playback',
        // Opened as the group's player, so it starts at the group's spot instead of
        // restarting the group from this device.
        onPress: widget.playerOpen ? null : () => GoRouter.of(context).push('/play/${widget.itemId}?syncplay=1'),
        autofocus: !widget.playerOpen,
      );
    },
  );

  // TODO(cleanup): use the shared wide-image helper
  /// The backdrop (the show's, for an episode), or else the poster.
  static String? _wideImage(JellyfinItem item) {
    final base = jellyfin.client?.baseUrl;
    if (base == null) return null;
    final own = (item.raw['BackdropImageTags'] as List?)?.firstOrNull as String?;
    final parent = (item.raw['ParentBackdropImageTags'] as List?)?.firstOrNull as String?;
    final parentId = item.raw['ParentBackdropItemId'] as String?;
    final primary = item.imageTags['Primary'];
    if (own != null) return '$base/Items/${item.id}/Images/Backdrop?fillWidth=400&tag=$own';
    if (parent != null && parentId != null) {
      return '$base/Items/$parentId/Images/Backdrop?fillWidth=400&tag=$parent';
    }
    if (primary != null) return '$base/Items/${item.id}/Images/Primary?fillWidth=400&tag=$primary';
    return null;
  }
}

/// The SyncPlay tile: a bordered card with a small picture, a title, a line or two under it
/// and an action word on the right. Selecting or hovering it fills it in and lights up the
/// border. Without [onPress], it's shown the same but does nothing.
class _SyncPlayTile extends StatelessWidget {
  const _SyncPlayTile({
    required this.imageUrl,
    required this.title,
    this.lines = const [],
    this.action,
    this.onPress,
    this.autofocus = false,
  });

  final String? imageUrl;
  final String title;
  final List<String> lines;
  final String? action;
  final VoidCallback? onPress;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final muted = theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground);

    return FTappable(
      autofocus: autofocus,
      onPress: onPress,
      builder: (context, states, _) {
        final highlighted = onPress != null && isHighlighted(states);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: highlighted ? theme.colors.secondary : theme.colors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: highlighted ? theme.colors.primary : theme.colors.border),
          ),
          child: Row(
            spacing: 12,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 112,
                  height: 63,
                  child: imageUrl == null
                      ? ColoredBox(
                    color: theme.colors.muted,
                    child: Icon(appIcons.play, color: theme.colors.mutedForeground, fill: 1),
                  )
                      : Image.network(
                    imageUrl!,
                    headers: jellyfin.authHeaders,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(color: theme.colors.muted),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w600),
                    ),
                    for (final line in lines)
                      Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                  ],
                ),
              ),
              if (action != null)
                Text(
                  action!,
                  style: theme.typography.body.sm.copyWith(
                    color: theme.colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        );
      },
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
  // TODO(cleanup): use a shared getJson on JellyfinController
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