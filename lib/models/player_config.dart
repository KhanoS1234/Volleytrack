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
  static const List<Color> palette = [
    Color(0xFF00E87A),
    Color(0xFF00D4FF),
    Color(0xFFF5A623),
  ];

  static const List<String> labels = [
    'Player 1',
    'Player 2',
    'Player 3',
  ];
}
