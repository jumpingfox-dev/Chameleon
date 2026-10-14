import 'package:material_ui/material_ui.dart';

/// Whether a tappable's remote-focused or mouse-hovered highlight should show. The two look
/// the same everywhere in this app, so widgets don't need to care which one it was.
bool isHighlighted(Set<WidgetState> states) =>
    states.contains(WidgetState.focused) || states.contains(WidgetState.hovered);

/// Something you can tap, click, or select with a remote (Enter, Select, Space), that draws
/// itself from its current [WidgetState]s: for the app's own cards and tiles, where a Material
/// button's look doesn't fit.
///
/// [WidgetState.focused] is only set while focus should show (a keyboard or remote is in use),
/// not after a tap. Without [onPress] it's disabled and can't take focus.
class Tappable extends StatefulWidget {
  const Tappable({
    super.key,
    this.focusNode,
    this.autofocus = false,
    required this.onPress,
    this.semanticsLabel,
    this.builder,
    this.child,
  }) : assert(builder != null || child != null);

  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onPress;
  final String? semanticsLabel;

  /// Draws it from its states. [child] is passed through, for the parts that never change.
  final Widget Function(BuildContext context, Set<WidgetState> states, Widget? child)? builder;
  final Widget? child;

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPress?.call()),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPress?.call()),
  };

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPress != null;
    final states = <WidgetState>{
      if (_focused && enabled) WidgetState.focused,
      if (_hovered && enabled) WidgetState.hovered,
      if (_pressed && enabled) WidgetState.pressed,
      if (!enabled) WidgetState.disabled,
    };
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: enabled,
      actions: _actions,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.semanticsLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPress,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          child: widget.builder?.call(context, states, widget.child) ?? widget.child,
        ),
      ),
    );
  }
}
