import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/focus/focus_rows.dart';
import '../../theme/theme.dart';
import '../../widgets/tappable.dart';

/// A form-style field showing the current choice; selecting it opens [showChoicePicker].
/// Works with a remote, unlike a dropdown (which keeps the arrow keys to itself).
class ChoiceField extends StatelessWidget {
  const ChoiceField({
    super.key,
    this.label,
    required this.value,
    required this.onPress,
  });

  final String? label;
  final String value;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => Tappable(
    onPress: onPress,
    // Drawn like Material's outlined dropdown, so it matches the DropdownMenus on phones.
    builder: (context, states, _) => InputDecorator(
      isFocused: isHighlighted(states),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.arrow_drop_down),
      ),
      child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}

/// A centered list to pick one value from, built for remotes as well as pointers:
/// the current choice starts highlighted, Select picks and closes, Back closes.
/// [search] supplies the options for a query ('' for the initial list).
Future<T?> showChoicePicker<T>({
  required BuildContext context,
  required String title,
  required Future<List<T>> Function(String query) search,
  required Widget Function(BuildContext context, T value) itemBuilder,
  T? selected,
  bool searchable = false,
  String searchHint = 'Search',
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: context.colors.scrim,
  transitionDuration: const Duration(milliseconds: 150),
  transitionBuilder: (context, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (context, _, _) => Center(
    child: _ChoicePicker<T>(
      title: title,
      search: search,
      itemBuilder: itemBuilder,
      selected: selected,
      searchable: searchable,
      searchHint: searchHint,
    ),
  ),
);

class _ChoicePicker<T> extends StatefulWidget {
  const _ChoicePicker({
    required this.title,
    required this.search,
    required this.itemBuilder,
    required this.selected,
    required this.searchable,
    required this.searchHint,
  });

  final String title;
  final Future<List<T>> Function(String query) search;
  final Widget Function(BuildContext context, T value) itemBuilder;
  final T? selected;
  final bool searchable;
  final String searchHint;

  @override
  State<_ChoicePicker<T>> createState() => _ChoicePickerState<T>();
}

class _ChoicePickerState<T> extends State<_ChoicePicker<T>> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<T>? _options;
  int _generation =
      0; // ignores results from searches that were overtaken by newer ones

  @override
  void initState() {
    super.initState();
    _load('');
    _query.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 250),
        () => _load(_query.text.trim()),
      );
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    final generation = ++_generation;
    final options = await widget.search(query);
    if (mounted && generation == _generation) setState(() => _options = options);
  }

  void _close([T? value]) => Navigator.of(context).pop(value);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxHeight = math.min(560.0, size.height * 0.85);
    final options = _options;
    // Start on the current choice, or on the first option if it isn't in the list.
    final focusIndex = options == null ? -1 : math.max(0, options.indexOf(widget.selected as T));

    // Loading and "Nothing found": a short centered message, not a full-height box.
    Widget message(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(heightFactor: 1, child: child),
    );

    final Widget list;
    if (options == null) {
      list = message(const CircularProgressIndicator());
    } else if (options.isEmpty) {
      list = message(Text('Nothing found', style: TextStyle(color: context.colors.onSurfaceVariant)));
    } else {
      list = ListView.separated(
        shrinkWrap: true, // only as tall as its options, up to the card's maximum
        padding: EdgeInsets.zero,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4), // room between highlights
        itemBuilder: (context, i) => _ChoiceOption(
          selected: options[i] == widget.selected,
          autofocus: i == focusIndex,
          onPress: () => _close(options[i]),
          child: widget.itemBuilder(context, options[i]),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.goBack): _close,
      },
      child: SizedBox(
        width: math.min(440, size.width - 32),
        // Searchable pickers keep a steady height so the card doesn't jump as you type;
        // the rest fit their contents.
        height: widget.searchable ? maxHeight : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  Text(widget.title, style: context.text.titleLarge),
                  if (widget.searchable)
                  // ↓ from the search box goes into the results (a text field would otherwise keep it).
                    CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                            moveFocus(TraversalDirection.down),
                      },
                      child: TextField(
                        controller: _query,
                        decoration: InputDecoration(
                          hintText: widget.searchHint,
                        ),
                      ),
                    ),
                  if (widget.searchable) Expanded(child: list) else Flexible(child: list),
                ],
              ),
            )),
        ),
      ),
    );
  }
}

/// One row in a choice picker: a check next to the current choice, highlighted instantly on
/// hover or focus. Built from plain Flutter pieces, with no animated focus effect, so the
/// highlight never trails behind as you move through the list.
class _ChoiceOption extends StatefulWidget {
  const _ChoiceOption({
    required this.selected,
    required this.autofocus,
    required this.onPress,
    required this.child,
  });

  final bool selected;
  final bool autofocus;
  final VoidCallback onPress;
  final Widget child;

  @override
  State<_ChoiceOption> createState() => _ChoiceOptionState();
}

class _ChoiceOptionState extends State<_ChoiceOption> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (v) =>
          setState(() => _focused = v), // keyboard or remote focus
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      actions: {
        // Select, Enter and Space all "activate" a focused item.
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPress();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _focused || _hovered
                ? colors.surfaceContainerHighest
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            spacing: 12,
            children: [
              SizedBox(
                width: 18,
                child: widget.selected
                    ? Icon(Icons.check_rounded, size: 18, color: colors.primary)
                    : null,
              ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}
