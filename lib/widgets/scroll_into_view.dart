import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// Scrolls the page so this widget sits comfortably in view whenever keyboard or remote focus
/// arrives inside it: about a third of the way down, rather than Flutter's default of
/// scrolling just far enough to fit, which leaves it hugging the edge of the screen.
///
/// Wrap whole rows or single items, never a card inside a sideways-scrolling row: the scroll
/// applies to every scrolling area above this widget, including that row.
class ScrollIntoViewOnFocus extends StatelessWidget {
  const ScrollIntoViewOnFocus({
    super.key,
    required this.child,
    this.alignment = 0.3,
  });

  final Widget child;

  /// Where the widget's top edge lands: 0 = top of the screen, 0.5 = middle.
  final double alignment;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus:
        false, // doesn't take focus itself; only notices it arriving inside
    skipTraversal: true,
    onFocusChange: (hasFocus) {
      // Keyboard and remote only: clicking or tapping shouldn't scroll the page.
      if (!hasFocus ||
          FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        alignment: alignment,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    },
    child: child,
  );
}

/// Makes a long block of content (like an expanded description) readable with a keyboard or remote.
/// While it has focus, ↓/↑ scroll the page through it. At its end, ↓ calls [onEnd] (e.g. to focus
/// a link inside it), or else lets focus move on as usual.
class KeyboardReadable extends StatefulWidget {
  const KeyboardReadable({
    super.key,
    required this.child,
    required this.enabled,
    this.focusNode,
    this.onEnd,
  });

  final Widget child;

  /// When false, it can't be focused and is skipped entirely (e.g. while collapsed).
  final bool enabled;
  final FocusNode? focusNode;

  /// Called when ↓ is pressed with the end of the content already shown.
  final VoidCallback? onEnd;

  @override
  State<KeyboardReadable> createState() => _KeyboardReadableState();
}

class _KeyboardReadableState extends State<KeyboardReadable> {
  static const _step = 120.0; // how far each ↓/↑ scrolls
  static const _margin =
      48.0; // treat content this close to the edge as fully shown

  late final FocusNode _node = widget.focusNode ?? FocusNode();
  bool _reading = false; // this block itself has focus (not a link inside it)

  bool get _keyboard =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void dispose() {
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!down && !up) return KeyEventResult.ignored;

    // Focus is on something inside (like the "Show less" link): ↑ goes back to reading,
    // ↓ moves on normally.
    if (!node.hasPrimaryFocus) {
      if (up && widget.enabled) {
        node.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final scrollable = Scrollable.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    final viewport = scrollable?.context.findRenderObject() as RenderBox?;
    if (scrollable == null || box == null || viewport == null) return KeyEventResult.ignored;

    // Where this content sits within the visible area.
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final bottom = top + box.size.height;
    final position = scrollable.position;

    void scrollBy(double delta) => position.animateTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );

    if (down) {
      if (bottom > viewport.size.height - _margin) {
        scrollBy(
          math.min(_step, bottom - (viewport.size.height - _margin)),
        ); // more below: keep reading
      } else if (widget.onEnd != null) {
        widget.onEnd!(); // reached the end
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (top < _margin) {
      scrollBy(-math.min(_step, _margin - top)); // more above: keep reading
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored; // back at the start: let focus move up
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _node,
    canRequestFocus: widget.enabled,
    skipTraversal: !widget.enabled,
    onKeyEvent: _onKey,
    onFocusChange: (_) {
      final reading = _node.hasPrimaryFocus;
      if (reading != _reading) setState(() => _reading = reading);
      // Arriving by keyboard: bring the start of the content near the top.
      if (reading && _keyboard) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    },
    // The reading bar sits in the margin just left of the content, so the content itself
    // never moves, whether it's expanded, being read, or neither.
    child: Stack(
      clipBehavior: Clip.none, // the bar sits outside the content's edge
      children: [
        widget.child,
        Positioned(
          left: -12,
          top: 0,
          bottom: 0,
          child: AnimatedOpacity(
            opacity: widget.enabled && _reading && _keyboard ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: context.theme.colors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
