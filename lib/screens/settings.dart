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
import '../widgets/custom_theme_editor.dart';
import '../widgets/choice_picker.dart';
import '../widgets/app_logo.dart';
import '../widgets/profile_actions.dart';
import '../utils/account_settings.dart';

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

  @override
  Widget build(BuildContext context) => FScaffold(
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
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
    if (MediaQuery.sizeOf(context).width < 600) {
      return FSelect<String>.searchBuilder(
        label: Text(label),
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
    listenable: Listenable.merge([themeController, fontController, iconController]),
    builder: (context, _) {
      final preset = themeController.value;
      final isPhone = MediaQuery.sizeOf(context).width < 600;

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

          // ── Theme ──
          const _SectionTitle('Theme', description: 'Pick a preset, or "Custom" to build your own.'),
          if (isPhone)
            FSelect<ThemePreset>(
              label: const Text('Theme'),
              hint: 'Prism',
              items: {for (final p in themeController.allPresets) p.label: p},
              control: FSelectControl.lifted(
                value: preset,
                onChange: (selected) {
                  if (selected != null) themeController.select(selected);
                },
              ),
            )
          else
            ChoiceField(
              label: 'Theme',
              value: preset.label,
              onPress: () async {
                final picked = await showChoicePicker<ThemePreset>(
                  context: context,
                  title: 'Theme',
                  selected: preset,
                  search: (_) async => themeController.allPresets.toList(),
                  itemBuilder: (context, p) => Text(p.label),
                );
                if (picked != null) themeController.select(picked);
              },
            ),
          if (preset.id == customThemeId) ...[
            const SizedBox(height: 16),
            const CustomThemeEditor(),
          ],

          // ── Icons ──
          const _SectionTitle('Icons', description: 'The icon style used across the app.'),
          if (isPhone)
            FSelect<IconStyle>(
              label: const Text('Icons'),
              items: {for (final s in IconStyle.values) s.label: s},
              control: FSelectControl.lifted(
                value: iconController.value,
                onChange: (style) {
                  if (style != null) iconController.select(style);
                },
              ),
            )
          else
            ChoiceField(
              label: 'Icons',
              value: iconController.value.label,
              onPress: () async {
                final picked = await showChoicePicker<IconStyle>(
                  context: context,
                  title: 'Icons',
                  selected: iconController.value,
                  search: (_) async => IconStyle.values,
                  itemBuilder: (context, style) {
                    // A small preview of each style.
                    final set = style.iconSet;
                    return Row(
                      spacing: 12,
                      children: [
                        Icon(set.play, size: 18, fill: 1),
                        Icon(set.favorite, size: 18, fill: 1),
                        Text(style.label),
                      ],
                    );
                  },
                );
                if (picked != null) iconController.select(picked);
              },
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
    required this.label,
    required this.value,
    required this.options,
    required this.format,
    required this.onChange,
    this.searchable = false,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T) format;
  final ValueChanged<T> onChange;
  final bool searchable; // for long lists like languages

  List<T> _filter(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ? options : options.where((o) => format(o).toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) {
      final control = FSelectControl<T>.lifted(
        value: value,
        onChange: (v) {
          if (v != null) onChange(v);
        },
      );
      if (searchable) {
        return FSelect<T>.searchBuilder(
          label: Text(label),
          format: format,
          filter: _filter,
          contentBuilder: (context, _, items) => [
            for (final item in items) .item(title: Text(format(item)), value: item),
          ],
          control: control,
        );
      }
      return FSelect<T>(
        label: Text(label),
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
          title: label,
          searchable: searchable,
          searchHint: 'Search',
          selected: value,
          search: (query) async => _filter(query),
          itemBuilder: (context, o) => Text(format(o)),
        );
        if (picked != null) onChange(picked);
      },
    );
  }
}

/// Playback Settings Tab
class _PlaybackCard extends StatelessWidget {
  const _PlaybackCard();

  @override
  Widget build(BuildContext context) {
    return const _SettingsCard(
      children: [
        _SectionTitle('Playback', description: 'Coming soon.', first: true),
      ],
    );
  }
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

      // ── App ──
      const _SectionTitle('App'),
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
            applicationName: 'chameleon',
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