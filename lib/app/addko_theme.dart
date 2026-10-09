import 'package:flutter/material.dart';

ThemeData buildAddKoTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4D7CFE),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF111318),
    cardTheme: const CardThemeData(clipBehavior: Clip.antiAlias, margin: EdgeInsets.zero),
  );
}
