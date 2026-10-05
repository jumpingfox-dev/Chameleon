import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import 'scroll_into_view.dart';

/// Text that's cut off after [limit] characters, with a "Read more" link to show the rest.
/// Expanded text can be read with a keyboard or remote (see [KeyboardReadable]).
class ExpandableText extends StatefulWidget {
  const ExpandableText(this.text, {super.key, this.limit = 250, this.style});

  final String text;
  final int limit;
  final TextStyle? style;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;
  final _textFocus = FocusNode(); // the text itself, while reading
  final _linkFocus = FocusNode(); // the "Read more" / "Show less" link

  @override
  void dispose() {
    _textFocus.dispose();
    _linkFocus.dispose();
    super.dispose();
  }

  /// The first [limit] characters, cut at the last space so words aren't split.
  String get _preview {
    final cut = widget.text.substring(0, widget.limit);
    final lastSpace = cut.lastIndexOf(' ');
    return '${(lastSpace > 0 ? cut.substring(0, lastSpace) : cut).trimRight()}…';
  }

  void _toggle() {
    final expanding = !_expanded;
    setState(() => _expanded = expanding);

    // With a keyboard or remote, start reading at the top of the full text.
    if (expanding &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > widget.limit;
    final style = widget.style ?? DefaultTextStyle.of(context).style;

    return KeyboardReadable(
      focusNode: _textFocus,
      enabled: isLong && _expanded,
      onEnd:
          _linkFocus.requestFocus, // finished reading: ↓ lands on "Show less"
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: isLong && !_expanded ? _preview : widget.text),
            if (isLong) ...[
              const TextSpan(text: ' '),
              // Inline with the text, but still a focusable, tappable link.
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: FTappable(
                  focusNode: _linkFocus,
                  onPress: _toggle,
                  builder: (context, states, _) {
                    // TODO(cleanup): shared focused-or-hovered helper
                    final active =
                        states.contains(FTappableVariant.hovered) ||
                        states.contains(FTappableVariant.focused);
                    final color = context.theme.colors.primary;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        Text(
                          _expanded ? 'Show less' : 'Read more',
                          style: context.theme.typography.body.sm.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                            decoration: active
                                ? TextDecoration.underline
                                : TextDecoration.none,
                            decorationColor: color,
                          ),
                        ),
                        Icon(
                          _expanded
                              ? appIcons.collapse
                              : appIcons.expand,
                          size: 14,
                          color: color,
                          fill: 1
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
