import 'package:material_ui/material_ui.dart';

import 'orientation.dart';

/// Side padding for page content: [extra] (16 by default) plus room for a camera cutout
/// or rounded corners, which is 0 on most screens.
///
/// Put it *inside* scroll views (as their `padding`) rather than around them, so content
/// starts clear of the edge but can still scroll right up to it.
EdgeInsets pageSides(BuildContext context, {double extra = 16}) {
  final insets = MediaQuery.paddingOf(context);
  return EdgeInsets.only(left: insets.left + extra, right: insets.right + extra);
}
/// Room above a page's content. More on wider screens, where a TV can crop the edge; the
/// sidebar's logo lines up with it there.
///
/// Like [pageSides], put it inside scroll views (in their `padding`) where there is one.
double pageTop(BuildContext context) => isPhoneLayout(context) ? 12 : 32;
