import 'package:material_ui/material_ui.dart';

import 'orientation.dart';

/// On wider screens, how far the sidebar's icons sit in from the rail's edge: half of what's
/// left of the 64-wide rail around a 24-wide icon. The rail is see-through, so the icons are
/// what reads as the sidebar's edge; see [pageSides].
const _railIconInset = 20.0;

/// Side padding for page content: [extra] (16 by default) plus room for a camera cutout
/// or rounded corners, which is 0 on most screens.
///
/// On wider screens the right side also gets [_railIconInset], so the gap after the content
/// looks the same as the one between the sidebar's icons and the content.
///
/// Put it *inside* scroll views (as their `padding`) rather than around them, so content
/// starts clear of the edge but can still scroll right up to it.
EdgeInsets pageSides(BuildContext context, {double extra = 16}) {
  final insets = MediaQuery.paddingOf(context);
  final balance = isPhoneLayout(context) ? 0.0 : _railIconInset;
  return EdgeInsets.only(left: insets.left + extra, right: insets.right + extra + balance);
}
/// Room above a page's content. More on wider screens, where a TV can crop the edge; the
/// sidebar's logo lines up with it there.
///
/// Like [pageSides], put it inside scroll views (in their `padding`) where there is one.
double pageTop(BuildContext context) => isPhoneLayout(context) ? 12 : 32;
