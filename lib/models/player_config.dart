import 'package:flutter/material.dart';

class PlayerConfig {
  final String jersey;
  final String name;
  final Color color;
  final List<String> photoPaths;

  const PlayerConfig({
    required this.jersey,
    required this.name,
    required this.color,
    this.photoPaths = const [],
  });
}

class PlayerColors {
  static const List<Color> palette = [
    Color(0xFF00E87A), // green
    Color(0xFF00D4FF), // cyan
    Color(0xFFF5A623), // gold
  ];

  static const List<String> labels = [
    'Player 1',
    'Player 2',
    'Player 3',
  ];
}
