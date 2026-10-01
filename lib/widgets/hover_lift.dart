import 'package:flutter/widgets.dart';

/// Tracks mouse hover and remote/keyboard focus for its child, and tells the builder
/// whether it's "active", so it can grow or highlight itself.
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.builder});

  final Widget Function(BuildContext context, bool active) builder;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _focused = false;
  bool _hovered = false;

  // Focus from a mouse click shouldn't leave the item enlarged, hence the highlight-mode check.
  bool get _active =>
      _hovered ||
      (_focused &&
          FocusManager.instance.highlightMode ==
              FocusHighlightMode.traditional);

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Focus(
      // Doesn't take focus itself; reports when the tappable inside it does.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: widget.builder(context, _active),
    ),
  );
}
