import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Arrow-key navigation for the whole app, built for TV remotes:
///  • ←/→ stay within a [FocusRow] and stop at its ends (no wrapping into the next row).
///  • ↑/↓ leave the row for the nearest row above or below, landing on the item you last had
///    focused there, or the one closest horizontally.
///  • Outside any row, ←/→ only move to items on the same line, so floating buttons don't jump.
///
/// Install [RowFocusNavigation] once near the top of the app. Call [moveFocus] directly
/// when a widget handles its own keys (like the player).

final _isRow = Expando<bool>('FocusRow');
final _lastInRow = Expando<FocusNode>('FocusRow.last');

/// Marks its focusable descendants as one horizontal row (a section's cards, a row of buttons...).
class FocusRow extends StatefulWidget {
  const FocusRow({super.key, required this.child});

  final Widget child;

  @override
  State<FocusRow> createState() => _FocusRowState();
}

class _FocusRowState extends State<FocusRow> {
  final _node = FocusNode(
    debugLabel: 'FocusRow',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    _isRow[_node] = true;
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _node, child: widget.child);
}

/// Replaces Flutter's "nearest thing in that direction" arrow navigation for everything below it.
class RowFocusNavigation extends StatelessWidget {
  const RowFocusNavigation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
        onInvoke: (intent) {
          moveFocus(intent.direction);
          return null;
        },
      ),
    },
    child: child,
  );
}

/// The row a node belongs to, or null if it isn't in one (within its own focus scope).
FocusNode? _rowOf(FocusNode node) {
  for (final ancestor in node.ancestors) {
    if (ancestor is FocusScopeNode) return null;
    if (_isRow[ancestor] == true) return ancestor;
  }
  return null;
}

bool _sameLine(Rect a, Rect b) => a.top < b.bottom && a.bottom > b.top;

/// The node with the lowest [primary] score, ties broken by [secondary].
FocusNode? _best(
  Iterable<FocusNode> nodes,
  double Function(Rect r) primary, [
  double Function(Rect r)? secondary,
]) {
  FocusNode? best;
  var bestScore = (double.infinity, double.infinity);
  for (final node in nodes) {
    final score = (primary(node.rect), secondary?.call(node.rect) ?? 0.0);
    if (score.$1 < bestScore.$1 ||
        (score.$1 == bestScore.$1 && score.$2 < bestScore.$2)) {
      best = node;
      bestScore = score;
    }
  }
  return best;
}

/// Moves focus one step in [direction] using the rules above. Returns false if there's
/// nowhere to go (e.g. the end of a row), in which case focus stays put.
bool moveFocus(TraversalDirection direction) {
  final current = FocusManager.instance.primaryFocus;
  final scope = current?.nearestScope;
  if (current == null || scope == null || current.context == null) return false;

  final cur = current.rect;
  final row = _rowOf(current);
  final candidates = scope.traversalDescendants
      .where(
        (n) =>
            n != current &&
            n is! FocusScopeNode &&
            n.context != null &&
            !n.rect.isEmpty,
      )
      .toList();
  double horizontalDistance(Rect r) => (r.center.dx - cur.center.dx).abs();

  FocusNode? target;
  switch (direction) {
    case TraversalDirection.left || TraversalDirection.right:
      final forward = direction == TraversalDirection.right;
      target = _best(
        candidates.where((n) {
          if (_rowOf(n) != row) {
            return false; // stay in this row (or among loose items)
          }
          final r = n.rect;
          if (row == null && !_sameLine(r, cur)) {
            return false; // loose items: same line only
          }
          return forward
              ? r.center.dx > cur.center.dx + 1
              : r.center.dx < cur.center.dx - 1;
        }),
        horizontalDistance,
        (r) => (r.center.dy - cur.center.dy).abs(),
      );

    case TraversalDirection.up || TraversalDirection.down:
      final down = direction == TraversalDirection.down;
      final ahead = candidates.where((n) {
        if (row != null && _rowOf(n) == row) {
          return false; // ↑/↓ always leave the row
        }
        final r = n.rect;
        return down ? r.top >= cur.center.dy : r.bottom <= cur.center.dy;
      }).toList();

      double gap(Rect r) =>
          math.max(0, down ? r.top - cur.bottom : cur.top - r.bottom);
      final nearest = _best(ahead, gap, horizontalDistance);
      if (nearest == null) break;

      final targetRow = _rowOf(nearest);
      if (targetRow != null) {
        // Back to where you were in that row, or the item closest horizontally.
        final remembered = _lastInRow[targetRow];
        target = remembered != null && ahead.contains(remembered)
            ? remembered
            : _best(
                ahead.where((n) => _rowOf(n) == targetRow),
                horizontalDistance,
              );
      } else {
        final line = nearest.rect;
        target = _best(
          ahead.where((n) => _rowOf(n) == null && _sameLine(n.rect, line)),
          horizontalDistance,
        );
      }
  }

  if (target == null) return false;
  if (row != null) {
    _lastInRow[row] = current; // remember where you left this row
  }
  final newRow = _rowOf(target);
  if (newRow != null) _lastInRow[newRow] = target;

  target.requestFocus();
  final targetContext = target.context;
  if (targetContext != null) {
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      alignmentPolicy:
          direction == TraversalDirection.down ||
              direction == TraversalDirection.right
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }
  return true;
}
