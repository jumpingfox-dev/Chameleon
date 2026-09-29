import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// Text that's cut off after [limit] characters, with a "More..." link to show the rest.
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

  /// The first [limit] characters, cut at the last space so words aren't split.
  String get _preview {
    final cut = widget.text.substring(0, widget.limit);
    final lastSpace = cut.lastIndexOf(' ');
    return '${(lastSpace > 0 ? cut.substring(0, lastSpace) : cut).trimRight()}…';
  }

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > widget.limit;
    final style = widget.style ?? DefaultTextStyle.of(context).style;

    return Text.rich(
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
                onPress: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? 'Less' : 'More',
                  style: style.copyWith(
                    color: context.theme.colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}