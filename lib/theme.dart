import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VTColors {
  static const courtBlue  = Color(0xFF0A1628);
  static const courtMid   = Color(0xFF0D1F3C);
  static const surface    = Color(0xFF0F2040);
  static const surface2   = Color(0xFF162B4A);
  static const netWhite   = Color(0xFFE8EEF7);
  static const spikeGold  = Color(0xFFF5A623);
  static const blockCyan  = Color(0xFF00D4FF);
  static const pointGreen = Color(0xFF00E87A);
  static const dangerRed  = Color(0xFFFF4757);
  static const muted      = Color(0xFF4A6080);
  static const textDim    = Color(0xFF7A9BC0);
}

ThemeData buildTheme() {
  return ThemeData(
    scaffoldBackgroundColor: VTColors.courtBlue,
    colorScheme: const ColorScheme.dark(
      primary: VTColors.spikeGold,
      secondary: VTColors.blockCyan,
      surface: VTColors.surface,
      error: VTColors.dangerRed,
    ),
    textTheme: GoogleFonts.interTextTheme(
      const TextTheme(
        bodyMedium: TextStyle(color: VTColors.netWhite),
        bodySmall:  TextStyle(color: VTColors.textDim),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VTColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: VTColors.blockCyan, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: VTColors.blockCyan.withValues(alpha: 0.3), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: VTColors.blockCyan, width: 1.5),
      ),
    ),
    useMaterial3: true,
  );
}
