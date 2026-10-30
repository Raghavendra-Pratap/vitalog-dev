import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop OS (macOS / Windows / Linux).
bool get isDesktopPlatform {
  if (kIsWeb) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}

/// Minimum width to use the desktop mockup shell (sidebar + master–detail).
/// Matches tablet landscape and desktop; portrait phones stay on bottom nav.
const double kWideShellMinWidth = 900;

/// True for desktop OS, or any surface wide enough (tablet landscape).
/// Layout source: `docs/mockups/desktop/` (Mac-Extension desktop mockup export).
bool useWideShell(BuildContext context) {
  if (isDesktopPlatform) return true;
  return MediaQuery.sizeOf(context).width >= kWideShellMinWidth;
}

/// Dialog inset — keep desktop/wide mockup padding; tighten on phone / tablet portrait.
EdgeInsets bodylineDialogInset(BuildContext context) {
  if (useWideShell(context)) {
    return const EdgeInsets.symmetric(horizontal: 40, vertical: 28);
  }
  return const EdgeInsets.symmetric(horizontal: 16, vertical: 24);
}

/// Cap dialog content width so fixed desktop widths do not overflow narrow screens.
double bodylineDialogWidth(BuildContext context, double preferred) {
  final inset = bodylineDialogInset(context);
  final maxW = MediaQuery.sizeOf(context).width - inset.horizontal;
  if (maxW <= 0) return preferred;
  return preferred < maxW ? preferred : maxW;
}

Future<void> configureDesktopWindow() async {
  if (!isDesktopPlatform) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1440, 900),
    minimumSize: Size(1100, 700),
    center: true,
    title: 'Vitalog',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// Windows can present a blank white window until the surface is resized.
/// Nudge the size once after the first frame so the UI actually paints.
Future<void> nudgeWindowsSurface() async {
  if (kIsWeb || !Platform.isWindows) return;
  final size = await windowManager.getSize();
  await windowManager.setSize(Size(size.width + 1, size.height + 1));
  await windowManager.setSize(size);
}
