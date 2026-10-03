import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Keeps what the remote or keyboard has selected comfortably in view inside a scrolling list.
///
/// Flutter scrolls only just far enough to show the selected item, so headings above it and
/// text below it (which can't be selected themselves) stay cut off. This scrolls with a margin
/// instead, and all the way to the top or bottom when the first or last selectable item is
/// reached, so the start and end of the page always come fully into view.
///
/// Touch scrolling is left alone. Wrap the scrolling list and give both the same [controller]:
///
/// ```dart
/// FocusReveal(controller: _scroll, child: ListView(controller: _scroll, children: [...]))
/// ```
class FocusReveal extends StatefulWidget {
  const FocusReveal({super.key, required this.controller, required this.child, this.margin = 64});

  final ScrollController controller;
  final Widget child;

  /// Space kept between the selected item and the top or bottom edge.
  final double margin;

  @override
  State<FocusReveal> createState() => _FocusRevealState();
}

class _FocusRevealState extends State<FocusReveal> {
  final _scope = FocusNode(debugLabel: 'FocusReveal', skipTraversal: true, canRequestFocus: false);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    _scope.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || !focused.ancestors.contains(_scope)) return;
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return; // touch
    // After this frame, so it runs after Flutter's own scroll and wins.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(focused));
  }

  void _reveal(FocusNode node) {
    final controller = widget.controller;
    if (!mounted || !controller.hasClients || !node.hasPrimaryFocus) return;
    final box = node.context?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final position = controller.position;
    // The list's own scrolling area, skipping sideways ones in between (like a row of tabs).
    final scrollable = Scrollable.maybeOf(node.context!, axis: position.axis);
    final area = scrollable?.context.findRenderObject();
    if (area is! RenderBox || !area.attached) return;
    final corner = box.localToGlobal(Offset.zero, ancestor: area);
    final vertical = position.axis == Axis.vertical;
    final start = vertical ? corner.dy : corner.dx; // where the item starts, on screen
    final length = vertical ? box.size.height : box.size.width;

    // Where each selectable item sits, top to bottom, measured on screen. (The order of the
    // focus tree isn't reliable for this: it changes as widgets come and go.)
    double? startOf(FocusNode n) {
      final r = n.context?.findRenderObject();
      if (r is! RenderBox || !r.attached) return null;
      final o = r.localToGlobal(Offset.zero, ancestor: area);
      return vertical ? o.dy : o.dx;
    }

    final starts = [
      for (final n in _scope.traversalDescendants)
        if (n.canRequestFocus && !n.skipTraversal)
          if (startOf(n) case final s?) s,
    ];
    final isFirst = starts.isNotEmpty && start <= starts.reduce(math.min) + 1; // e.g. any of the tabs
    final isLast = starts.isNotEmpty && start >= starts.reduce(math.max) - 1;

    double target;
    if (isFirst) {
      target = position.minScrollExtent; // the top row: show everything above it too
    } else if (isLast) {
      target = position.maxScrollExtent; // the bottom row: show everything below it too
    } else {
      // Scroll so the item sits at least [margin] from whichever edge it's near.
      final current = position.pixels;
      final alignTop = current + start - widget.margin;
      final alignBottom = current + start + length - position.viewportDimension + widget.margin;
      if (alignBottom > alignTop) {
        target = alignTop; // taller than the screen: show its top
      } else if (current > alignTop) {
        target = alignTop;
      } else if (current < alignBottom) {
        target = alignBottom;
      } else {
        return; // already comfortably in view
      }
    }

    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return;
    controller.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _scope,
    skipTraversal: true,
    canRequestFocus: false,
    child: widget.child,
  );
}