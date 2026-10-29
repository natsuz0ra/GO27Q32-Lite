import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness brightness) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF0758D9),
        brightness: brightness,
      ).copyWith(
        primary: brightness == Brightness.light
            ? const Color(0xFF0758D9)
            : const Color(0xFFAAC7FF),
        onPrimary: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF002F6C),
        tertiary: brightness == Brightness.light
            ? const Color(0xFF216B45)
            : const Color(0xFF91D5A7),
        onTertiary: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF00391D),
        tertiaryContainer: brightness == Brightness.light
            ? const Color(0xFFD5F1DE)
            : const Color(0xFF174E32),
        onTertiaryContainer: brightness == Brightness.light
            ? const Color(0xFF123E27)
            : const Color(0xFFC9EDD4),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: 'HarmonyOS',
    scaffoldBackgroundColor: scheme.surface,
    listTileTheme: ListTileThemeData(
      titleTextStyle: TextStyle(
        fontFamily: 'HarmonyOS',
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'HarmonyOS',
        fontSize: 12,
        height: 1.5,
        color: scheme.onSurfaceVariant,
      ),
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
    ),
    cardTheme: CardThemeData(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    dialogTheme: const DialogThemeData(clipBehavior: Clip.antiAlias),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    sliderTheme: const SliderThemeData(
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      preferBelow: false,
      verticalOffset: 24,
      constraints: BoxConstraints(maxWidth: 320),
    ),
  );
}
