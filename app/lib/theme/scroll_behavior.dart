import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Keeps scrolling (wheel / trackpad / drag) without drawing scrollbar thumbs.
class BodylineScrollBehavior extends MaterialScrollBehavior {
  const BodylineScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
