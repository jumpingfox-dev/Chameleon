import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/theme_controller.dart';
import '../utils/theme_presets.dart';
import '../theme/app_icons.dart';
import '../widgets/switch_setting.dart';

String _pad3(int n) => n.toString().padLeft(3, '0');

class CustomThemeEditor extends StatefulWidget {
  const CustomThemeEditor({super.key});

  @override
  State<CustomThemeEditor> createState() => _CustomThemeEditorState();
}

class _CustomThemeEditorState extends State<CustomThemeEditor> {
  late final _ini = TextEditingController(text: themeController.customIni);
  List<String> _errors = const [];

  @override
  void dispose() {
    _ini.dispose();
    super.dispose();
  }

  void _setAdvanced(bool on) {
    if (on) {
      // Refresh the box so it reflects the latest seed or saved INI.
      _ini.text = themeController.customIni;
      _errors = const [];
    }
    themeController.setAdvanced(on);
  }

  Future<void> _apply() async {
    final errors = await themeController.applyCustomIni(_ini.text);
    if (mounted) setState(() => _errors = errors);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: themeController,
    builder: (context, _) {
      final advanced = themeController.advanced;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (advanced) ...[
            _AdvancedEditor(controller: _ini, errors: _errors),
            const SizedBox(height: 12),
            FButton(
              onPress: _apply,
              child: const Text('Apply'),
            ),
          ] else
            _SeedEditor(seed: themeController.seed),
          const SizedBox(height: 12),
          SwitchSetting(
            label: 'Advanced',
            description: 'Edit every color directly instead of picking hues.',
            value: advanced,
            onChange: _setAdvanced,
          ),
        ],
      );
    },
  );
}

// ─── Simple mode ─────────────────────────────────────────────────────────────

class _SeedEditor extends StatefulWidget {
  const _SeedEditor({required this.seed});

  final ThemeSeed seed;

  @override
  State<_SeedEditor> createState() => _SeedEditorState();
}

class _SeedEditorState extends State<_SeedEditor> {
  final _code = TextEditingController();
  String? _codeError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _set(ThemeSeed seed) => themeController.applySeed(seed);

  void _loadCode() {
    final seed = ThemeSeed.parse(_code.text);
    if (seed == null) {
      setState(() => _codeError = 'Enter 8 digits, e.g. 28533082');
      return;
    }
    setState(() => _codeError = null);
    _code.clear();
    _set(seed);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.seed;
    Color hueSwatch(int hue) =>
        HSLColor.fromAHSL(1, hue.toDouble(), 0.8, 0.55).toColor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stepper(
          label: 'Base Hue',
          value: _pad3(s.baseHue),
          swatch: hueSwatch(s.baseHue),
          onPrev: () => _set(s.copyWith(baseHue: (s.baseHue - 15) % 360)),
          onNext: () => _set(s.copyWith(baseHue: (s.baseHue + 15) % 360)),
        ),
        _Stepper(
          label: 'Accent Hue',
          value: _pad3(s.accentHue),
          swatch: hueSwatch(s.accentHue),
          onPrev: () => _set(s.copyWith(accentHue: (s.accentHue - 15) % 360)),
          onNext: () => _set(s.copyWith(accentHue: (s.accentHue + 15) % 360)),
        ),
        _Stepper(
          label: 'Vibrance',
          value: '${s.vibrance}',
          onPrev: s.vibrance > 0
              ? () => _set(s.copyWith(vibrance: s.vibrance - 1))
              : null,
          onNext: s.vibrance < 9
              ? () => _set(s.copyWith(vibrance: s.vibrance + 1))
              : null,
        ),
        _Stepper(
          label: 'Depth',
          value: '${s.depth}',
          onPrev: s.depth > 0
              ? () => _set(s.copyWith(depth: s.depth - 1))
              : null,
          onNext: s.depth < 9
              ? () => _set(s.copyWith(depth: s.depth + 1))
              : null,
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            text: 'Theme Code: ',
            children: [
              TextSpan(
                text:
                    '${_pad3(s.baseHue)}-${_pad3(s.accentHue)}-${s.vibrance}-${s.depth}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          style: context.theme.typography.body.sm,
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            FTextField(
              control: .managed(controller: _code),
              hint: 'Enter a code, e.g. 28533082',
              keyboardType: TextInputType.number,
              error: _codeError == null ? null : Text(_codeError!),
            ),
            FButton(
              onPress: _loadCode,
              child: const Text('Load'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onPrev,
    required this.onNext,
    this.swatch,
  });

  final String label;
  final String value;
  final VoidCallback?
  onPrev; // null disables the button at the ends of the range
  final VoidCallback? onNext;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    // Not isPhoneLayout (which uses shortestSide, not width): a phone held sideways gets the
    // smaller button here instead of the touch-sized one. Left as-is for this pass rather
    // than guessed at -- switching it changes what a landscape phone sees.
    final isPhone = MediaQuery
        .sizeOf(context)
        .width < 600;
    final buttonSize = isPhone ? FButtonSizeVariant.lg : FButtonSizeVariant.sm;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (swatch != null)
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
            ),
          FButton.icon(
            variant: .ghost,
            size: buttonSize,
            onPress: onPrev,
            child: Icon(appIcons.stepBack, fill: 1),
          ),
          SizedBox(width: isPhone ? 48 : 40,
              child: Text(value, textAlign: TextAlign.center)),
          FButton.icon(
            variant: .ghost,
            size: buttonSize,
            onPress: onNext,
            child: Icon(appIcons.stepForward, fill: 1),
          ),
        ],
      ),
    );
  }
}

// ─── Advanced mode ───────────────────────────────────────────────────────────

class _AdvancedEditor extends StatelessWidget {
  const _AdvancedEditor({required this.controller, required this.errors});

  final TextEditingController controller;
  final List<String> errors;

  @override
  Widget build(BuildContext context) => FTextField.multiline(
    control: .managed(controller: controller),
    label: const Text('Custom Colors'),
    hint: 'One "name = color" per line: #RRGGBB, #AARRGGBB, or hsl(h, s%, l%).',
    error: errors.isEmpty ? null : Text(errors.join('\n')),
    minLines: 5,
  );
}
