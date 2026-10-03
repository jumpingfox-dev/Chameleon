import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// An on/off setting. The whole row is one button, so the remote can select and toggle it.
class SwitchSetting extends StatelessWidget {
  const SwitchSetting({
    super.key,
    required this.label,
    required this.value,
    required this.onChange,
    this.description,
    this.enabled = true,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChange;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: FTappable(
        onPress: enabled ? () => onChange(!value) : null,
        builder: (context, states, _) {
          final highlighted = states.contains(FTappableVariant.focused) || states.contains(FTappableVariant.hovered);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: highlighted ? theme.colors.secondary : const Color(0x00000000),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: Row(
                spacing: 16,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 2,
                      children: [
                        Text(label, style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w500)),
                        if (description != null)
                          Text(
                            description!,
                            style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
                          ),
                      ],
                    ),
                  ),
                  // The row handles presses and focus; the switch only shows the state.
                  ExcludeFocus(
                    child: IgnorePointer(
                      child: FSwitch(value: value, enabled: enabled, onChange: (_) {}),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}