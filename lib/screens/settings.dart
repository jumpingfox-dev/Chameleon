import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../theme/app_icons.dart';
import '../utils/font_controller.dart';
import '../utils/theme_controller.dart';
import '../utils/theme_presets.dart';
import '../widgets/custom_theme_editor.dart';
import '../widgets/choice_picker.dart';

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
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _index = 0;

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

/// A bordered settings section with a title and subtitle, like the forui example.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => FCard(
    builder: (context, style, _) => Padding(
      padding: style.padding,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Text(title, style: style.titleTextStyle),
          const SizedBox(height: 2),
          Text(subtitle, style: style.subtitleTextStyle),
          const SizedBox(height: 16),
          ...children,
        ],
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
    listenable: Listenable.merge([themeController, fontController]),
    builder: (context, _) {
      final preset = themeController.value;

      return _SettingsCard(
        title: 'Appearance',
        subtitle: 'Choose fonts and a theme, or select "Custom" to build your own theme.',
        children: [
          /// START: Font Picker
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

          /// END: Font Picker
          const SizedBox(height: 16),

          /// START: Theme Select
          if (MediaQuery.sizeOf(context).width < 600)
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

          /// END: Theme Select
          const SizedBox(height: 16),

          /// START: Icon Picker
          ListenableBuilder(
            listenable: iconController,
            builder: (context, _) => ChoiceField(
              label: 'Icons',
              value: iconController.value.label,
              onPress: () async {
                final picked = await showChoicePicker<IconStyle>(
                  context: context,
                  title: 'Icons',
                  selected: iconController.value,
                  search: (_) async => IconStyle.values,
                  itemBuilder: (context, style) => Row(
                    spacing: 12,
                    children: [
                      // A small preview of each style.
                      Icon(style == IconStyle.phosphor ? phosphorIconSet.play : materialIconSet.play, size: 18),
                      Icon(style == IconStyle.phosphor ? phosphorIconSet.favorite : materialIconSet.favorite, size: 18),
                      Text(style.label),
                    ],
                  ),
                );
                if (picked != null) iconController.select(picked);
              },
            ),
          ),
        ],
      );
    },
  );
}

/// Account Settings Tab
class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Account',
      subtitle: 'Choose fonts and a theme, or select "Custom" to build your own theme.',
      children: [],
    );
  }
}

/// Playback Settings Tab
class _PlaybackCard extends StatelessWidget {
  const _PlaybackCard();

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Playback',
      subtitle: 'Choose fonts and a theme, or select "Custom" to build your own theme.',
      children: [],
    );
  }
}

/// Server Settings Tab
class _ServerCard extends StatelessWidget {
  const _ServerCard();

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Server',
      subtitle: 'Choose fonts and a theme, or select "Custom" to build your own theme.',
      children: [],
    );
  }
}

/// About Settings Tab
class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'About',
      subtitle: 'Choose fonts and a theme, or select "Custom" to build your own theme.',
      children: [],
    );
  }
}
