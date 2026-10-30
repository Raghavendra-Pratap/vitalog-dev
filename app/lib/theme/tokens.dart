import 'package:flutter/material.dart';

/// Brand colors. Switch with [BodylineColors.applyBrightness] when the
/// MaterialApp theme mode changes so existing call sites pick up dark values.
abstract final class BodylineColors {
  static Brightness _brightness = Brightness.light;

  static void applyBrightness(Brightness brightness) {
    _brightness = brightness;
  }

  /// Prefer calling from build methods that paint with these getters.
  static void syncFrom(BuildContext context) {
    applyBrightness(Theme.of(context).brightness);
  }

  static bool get isDark => _brightness == Brightness.dark;

  static Color get teal =>
      isDark ? const Color(0xFF4DB8AE) : const Color(0xFF0E6B63);
  static Color get tealDark =>
      isDark ? const Color(0xFF9FE0D8) : const Color(0xFF0A524C);
  static Color get tealTint =>
      isDark ? const Color(0xFF0A2824) : const Color(0xFFDDEFEA);
  static Color get orange =>
      isDark ? const Color(0xFFE0955C) : const Color(0xFFB8561B);
  static Color get orangeText =>
      isDark ? const Color(0xFFF0B890) : const Color(0xFF8A3E10);
  static Color get orangeTint =>
      isDark ? const Color(0xFF3A281C) : const Color(0xFFFBE9DC);
  static Color get blue =>
      isDark ? const Color(0xFF7AA8DE) : const Color(0xFF2A5CA0);
  static Color get blueText =>
      isDark ? const Color(0xFFB4D0F0) : const Color(0xFF1E4478);
  static Color get blueTint =>
      isDark ? const Color(0xFF1C2A3D) : const Color(0xFFE3ECF8);

  /// Primary text / ink fills.
  static Color get ink =>
      isDark ? const Color(0xFFF5F2EB) : const Color(0xFF1C2230);
  /// Text/icons sitting on [ink] fills (buttons, selected chips).
  static Color get onInk =>
      isDark ? const Color(0xFF0A0A0A) : Colors.white;
  static Color get inkMuted =>
      isDark ? const Color(0xFFD6D2C8) : const Color(0xFF4A4740);
  static Color get inkSubtle =>
      isDark ? const Color(0xFFC9C4B8) : const Color(0xFF6B675E);

  /// Blank black canvas in dark; warm paper in light.
  static Color get paper =>
      isDark ? const Color(0xFF000000) : const Color(0xFFF6F4EF);
  static Color get surface =>
      isDark ? const Color(0xFF121212) : const Color(0xFFFFFDF8);
  static Color get border =>
      isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE2DDD2);
  static Color get divider =>
      isDark ? const Color(0xFF1F1F1F) : const Color(0xFFEFEBE2);

  /// Icon wells / nested chips (never hardcode cream in widgets).
  static Color get iconWell =>
      isDark ? const Color(0xFF1C1C1C) : const Color(0xFFF0EEE8);
  static Color get chip =>
      isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF6F4EF);
  /// Soft selected wash (lists, filters). Nav prefers [tealTint].
  static Color get selectedWash =>
      isDark ? const Color(0xFF0F2A26) : const Color(0xFFE4EFEC);
  static Color get outlineSoft =>
      isDark ? const Color(0xFF3A3A3A) : const Color(0xFFC9C3B6);

  static Color get bodyFill =>
      isDark ? const Color(0xFF2A2622) : const Color(0xFFEDE3D8);
  static Color get untested =>
      isDark ? const Color(0xFF8A8680) : const Color(0xFF9A968C);
  static Color get danger =>
      isDark ? const Color(0xFFE87868) : const Color(0xFFA33A2A);

  /// Chart reference bands — prefer [BodylineChartColors] for painted charts.
  static Color get chartInRangeBand => BodylineChartColors.inRangeBand;
  static Color get chartHighBand => BodylineChartColors.highBand;
  static Color get chartLowBand => BodylineChartColors.lowBand;
}

/// Trend / sparkline paint always uses the light palette — same look in dark mode.
abstract final class BodylineChartColors {
  static const ink = Color(0xFF1C2230);
  static const onInk = Color(0xFFFFFFFF);
  static const inkSubtle = Color(0xFF6B675E);
  static const surface = Color(0xFFFFFDF8);
  static const border = Color(0xFFE2DDD2);
  static const divider = Color(0xFFEFEBE2);
  static const teal = Color(0xFF0E6B63);
  static const inRangeBand = Color(0xFFDDEFEA);
  static const highBand = Color(0xFFF8E0D2);
  static const lowBand = Color(0xFFE3ECF8);

  /// Soft lift so the light chart card reads against a dark page.
  static List<BoxShadow> get cardShadow {
    if (!BodylineColors.isDark) return const [];
    return const [
      BoxShadow(
        color: Color(0x99000000),
        blurRadius: 28,
        offset: Offset(0, 12),
      ),
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 10,
        offset: Offset(0, 3),
      ),
    ];
  }
}


abstract final class BodylineRadii {
  static const pill = 8.0;
  static const input = 12.0;
  static const cardSmall = 14.0;
  static const card = 18.0;
  static const sheet = 22.0;
}

ThemeData bodylineTheme(Brightness brightness) {
  BodylineColors.applyBrightness(brightness);
  final display =
      const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w600);
  const ui = TextStyle(fontFamily: 'Manrope');

  final ink = BodylineColors.ink;
  final inkMuted = BodylineColors.inkMuted;
  final inkSubtle = BodylineColors.inkSubtle;
  final paper = BodylineColors.paper;
  final surface = BodylineColors.surface;
  final border = BodylineColors.border;
  final teal = BodylineColors.teal;
  final tealDark = BodylineColors.tealDark;
  final tealTint = BodylineColors.tealTint;
  final danger = BodylineColors.danger;
  final onInk = BodylineColors.onInk;
  final dark = brightness == Brightness.dark;

  final text = TextTheme(
    displaySmall: display.copyWith(fontSize: 44, color: ink, height: 1.05),
    headlineMedium: display.copyWith(fontSize: 26, color: ink),
    headlineSmall: display.copyWith(fontSize: 22, color: ink),
    titleLarge:
        ui.copyWith(fontSize: 18, fontWeight: FontWeight.w700, color: ink),
    titleMedium:
        ui.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: ink),
    titleSmall:
        ui.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
    bodyMedium: ui.copyWith(fontSize: 14, color: inkMuted, height: 1.4),
    bodySmall: ui.copyWith(fontSize: 12, color: inkSubtle),
    labelLarge: ui.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
    labelMedium: ui.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: ink),
  );

  final orange = BodylineColors.orange;
  final orangeTint = BodylineColors.orangeTint;
  final chip = BodylineColors.chip;
  final iconWell = BodylineColors.iconWell;
  final divider = BodylineColors.divider;
  final onPrimary = dark ? const Color(0xFF04201C) : Colors.white;

  // Full M3 scheme so NavigationBar / chips / sheets don't fall back to
  // Material defaults that fight light or dark brand tokens.
  final scheme = ColorScheme(
    brightness: brightness,
    primary: teal,
    onPrimary: onPrimary,
    primaryContainer: tealTint,
    onPrimaryContainer: tealDark,
    secondary: orange,
    onSecondary: onPrimary,
    secondaryContainer: orangeTint,
    onSecondaryContainer: BodylineColors.orangeText,
    tertiary: BodylineColors.blue,
    onTertiary: onPrimary,
    tertiaryContainer: BodylineColors.blueTint,
    onTertiaryContainer: BodylineColors.blueText,
    error: danger,
    onError: onPrimary,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: inkMuted,
    outline: border,
    outlineVariant: divider,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: ink,
    onInverseSurface: onInk,
    inversePrimary: teal,
    surfaceTint: teal,
    surfaceContainerLowest: paper,
    surfaceContainerLow: chip,
    surfaceContainer: surface,
    surfaceContainerHigh: iconWell,
    surfaceContainerHighest: iconWell,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: paper,
    canvasColor: paper,
    fontFamily: 'Manrope',
    colorScheme: scheme,
    textTheme: text,
    primaryTextTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: display.copyWith(fontSize: 22, color: ink),
      iconTheme: IconThemeData(color: ink),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BodylineRadii.card),
        side: BorderSide(color: border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: chip,
      selectedColor: tealTint,
      disabledColor: chip,
      labelStyle: ui.copyWith(fontSize: 13, color: inkMuted),
      secondaryLabelStyle: ui.copyWith(fontSize: 13, color: tealDark),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      side: BorderSide(color: border),
    ),
    dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BodylineRadii.sheet),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: ui.copyWith(color: onInk, fontSize: 14),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: teal,
      linearTrackColor: chip,
      circularTrackColor: chip,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: ui.copyWith(fontSize: 14, color: inkSubtle),
      labelStyle: ui.copyWith(fontSize: 14, color: inkMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BodylineRadii.input),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BodylineRadii.input),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BodylineRadii.input),
        borderSide: BorderSide(color: teal, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: teal,
        foregroundColor: dark ? const Color(0xFF04201C) : Colors.white,
        minimumSize: const Size(44, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BodylineRadii.input),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: teal),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        // White thumb so the knob reads clearly on teal (Android Material 3).
        if (s.contains(WidgetState.selected)) return Colors.white;
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return teal;
        return border;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return Colors.transparent;
        return inkSubtle.withValues(alpha: 0.55);
      }),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: tealTint,
      height: 76,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected ? tealDark : inkSubtle,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? teal : inkSubtle,
        );
      }),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: ink,
      foregroundColor: onInk,
      elevation: 3,
      focusElevation: 4,
      hoverElevation: 4,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BodylineRadii.sheet),
        side: BorderSide(color: border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      titleTextStyle: display.copyWith(fontSize: 22, color: ink),
      contentTextStyle:
          ui.copyWith(fontSize: 14, color: inkMuted, height: 1.4),
    ),
    dividerColor: BodylineColors.divider,
    listTileTheme: ListTileThemeData(
      iconColor: inkMuted,
      textColor: ink,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(0),
      thumbVisibility: const WidgetStatePropertyAll(false),
      trackVisibility: const WidgetStatePropertyAll(false),
      interactive: false,
    ),
  );
}
