import 'package:flutter/material.dart';

/// Represents one player being tracked in a session
class PlayerConfig {
  final String jersey;
  final String name;
  final Color color;

  const PlayerConfig({
    required this.jersey,
    required this.name,
    required this.color,
  });
}

/// Available colours for distinguishing players on screen
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
