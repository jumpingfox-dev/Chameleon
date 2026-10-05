import 'package:forui/forui.dart';

/// Whether a tappable's remote-focused or mouse-hovered highlight should show. The two look
/// the same everywhere in this app, so widgets don't need to care which one it was.
bool isHighlighted(Set<FTappableVariant> states) =>
    states.contains(FTappableVariant.focused) || states.contains(FTappableVariant.hovered);
