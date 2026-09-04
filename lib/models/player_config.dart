import 'package:flutter/material.dart';
import '../services/color_detector.dart';

class PlayerConfig {
  final String jersey;
  final String name;
  final Color color;
  final List<String> photoPaths;
  final JerseyColors? detectedColors;

  const PlayerConfig({
    required this.jersey,
    required this.name,
    required this.color,
    this.photoPaths = const [],
    this.detectedColors,
  });
}

class PlayerColors {
  // Up to 6 simultaneously tracked players, each with a distinct colour
  static const List<Color> palette = [
    Color(0xFF00E87A), // green
    Color(0xFF00D4FF), // cyan
    Color(0xFFF5A623), // gold
    Color(0xFFFF4D8D), // pink
    Color(0xFFA78BFA), // purple
    Color(0xFFFF7A45), // orange
  ];

  static const List<String> labels = [
    'Player 1',
    'Player 2',
    'Player 3',
    'Player 4',
    'Player 5',
    'Player 6',
  ];

  /// Deterministic colour assignment based on jersey number, so a
  /// player keeps the SAME colour every time they're subbed on,
  /// rather than colour depending on which slot they happen to fill.
  static Color colorForJersey(String jersey) {
    final hash = jersey.codeUnits.fold<int>(0, (a, b) => a + b);
    return palette[hash % palette.length];
  }
}
