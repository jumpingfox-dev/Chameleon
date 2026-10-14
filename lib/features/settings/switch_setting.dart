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
  Widget build(BuildContext context) => SwitchListTile(
    title: Text(label),
    subtitle: description == null ? null : Text(description!),
    value: value,
    onChanged: enabled ? onChange : null,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}
