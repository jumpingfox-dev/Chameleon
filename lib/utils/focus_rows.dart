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
final _isColumn = Expando<bool>('FocusColumn');

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

/// Marks its focusable descendants as one vertical column, kept apart from the rest of the
/// page (like the A–Z down the side of a library): ↑/↓ move only within it and stop at its
/// ends, and ↑/↓ from elsewhere never land in it. ←/→ move in and out as usual.
class FocusColumn extends StatefulWidget {
  const FocusColumn({super.key, required this.child});

  final Widget child;

  @override
  State<FocusColumn> createState() => _FocusColumnState();
}

class _FocusColumnState extends State<FocusColumn> {
  final _node = FocusNode(
    debugLabel: 'FocusColumn',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    _isColumn[_node] = true;
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

/// The item to focus when a page opens: the first one on the page (in the order the page
/// lists them) that's actually laid out. Text fields (which would pop up the keyboard) and
/// items in a side [FocusColumn] (like the A–Z) only count if [mainOnly] is false and there's
/// nothing else.
///
/// Only the page on top counts. Pages underneath it (Home, under a genre you opened from it)
/// stay in the tree and keep their old positions while hidden, so without this the "first
/// item" could be one you can't see.
FocusNode? firstFocusable(FocusScopeNode scope, {bool mainOnly = false}) {
  final nodes = scope.traversalDescendants
      .where(
        (n) =>
    n.canRequestFocus &&
        !n.skipTraversal &&
        n is! FocusScopeNode &&
        isOnTopPage(n) &&
        _isLaidOut(n) &&
        !n.rect.isEmpty,
  )
      .toList();
  bool isTextField(FocusNode n) => n.context?.findAncestorStateOfType<EditableTextState>() != null;
  final main = nodes.where((n) => _columnOf(n) == null && !isTextField(n)).firstOrNull;
  return mainOnly ? main : main ?? nodes.firstOrNull;
}

/// Whether [node] has been laid out yet, so its position can be read. Something that has just
/// appeared (the edit controls on Home, say) isn't until the next frame.
bool _isLaidOut(FocusNode node) {
  final box = node.context?.findRenderObject();
  return box is RenderBox && box.attached && box.hasSize;
}

/// Whether [node] is on the page you're looking at, rather than one hidden underneath it.
bool isOnTopPage(FocusNode node) {
  final context = node.context;
  if (context == null) return false;
  return ModalRoute.of(context)?.isCurrent ?? true;
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

/// The column a node belongs to, or null if it isn't in one (within its own focus scope).
FocusNode? _columnOf(FocusNode node) {
  for (final ancestor in node.ancestors) {
    if (ancestor is FocusScopeNode) return null;
    if (_isColumn[ancestor] == true) return ancestor;
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
        isOnTopPage(n) && // never onto a page hidden underneath this one
        _isLaidOut(n) &&
        !n.rect.isEmpty,
  )
      .toList();
  double horizontalDistance(Rect r) => (r.center.dx - cur.center.dx).abs();

  FocusNode? target;
  final column = _columnOf(current); // e.g. the A–Z beside a library
  switch (direction) {
  case TraversalDirection.left || TraversalDirection.right when column != null:
  // Out of a column (the A–Z beside a library): to the nearest item on that side, by
  // height first. Its items needn't share a line with you: a letter can sit level with
  // the gap between two rows of posters.
  final forward = direction == TraversalDirection.right;
  double verticalGap(Rect r) =>
  math.max(0, math.max(r.top - cur.bottom, cur.top - r.bottom));
  target = _best(
  candidates.where((n) {
  if (_columnOf(n) == column) return false;
  final r = n.rect;
  return forward ? r.center.dx > cur.center.dx + 1 : r.center.dx < cur.center.dx - 1;
  }),
  verticalGap,
  horizontalDistance,
  );

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
  if (_columnOf(n) != column) {
  return false; // ↑/↓ stay in a column, and never go into one from outside
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

/// Lets ↑/↓ leave one-line text fields (search boxes, sign-in fields) for whatever is above
/// or below, as a remote expects. A text field normally keeps those keys to move its cursor
/// to the start or end. Multi-line fields still move between lines.
///
/// Install once near the top of the app (next to [RowFocusNavigation]).
class TextFieldArrowEscape extends StatelessWidget {
  const TextFieldArrowEscape({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: {ExtendSelectionVerticallyToAdjacentLineIntent: _LeaveTextField()},
    child: child,
  );
}

class _LeaveTextField extends ContextAction<ExtendSelectionVerticallyToAdjacentLineIntent> {
  /// The focused text field, if one is focused.
  static EditableTextState? get _field =>
      FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>();

  /// Whether ↑/↓ should leave [field] rather than move its cursor: always in a one-line field,
  /// and in a multi-line one from the first line going up or the last line going down.
  static bool _leaves(EditableTextState field, {required bool down}) {
    if (field.widget.maxLines == 1) return true;

    final editable = field.renderEditable;
    final text = field.textEditingValue.text;
    final selection = field.textEditingValue.selection;
    if (!selection.isValid) return false;

    // Compare the cursor's line with the first or last line of the text. Measured on screen,
    // so wrapped lines count as lines too.
    final caret = editable.getLocalRectForCaret(TextPosition(offset: selection.extentOffset));
    final edge = editable.getLocalRectForCaret(TextPosition(offset: down ? text.length : 0));
    return (caret.top - edge.top).abs() < editable.preferredLineHeight / 2;
  }

  // Switched off unless the cursor should leave the field. Then the key does what it normally
  // would: D-pad navigation outside text fields, or moving between lines inside the editor.
  @override
  bool isEnabled(ExtendSelectionVerticallyToAdjacentLineIntent intent, [BuildContext? context]) {
    final field = _field;
    return field != null && _leaves(field, down: intent.forward);
  }

  @override
  Object? invoke(ExtendSelectionVerticallyToAdjacentLineIntent intent, [BuildContext? context]) {
    // Leave the field for whatever is below (or above), using the app's own row rules.
    moveFocus(intent.forward ? TraversalDirection.down : TraversalDirection.up);
    return null;
  }
}