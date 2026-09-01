import 'dart:convert';
import 'dart:ui' show Color;
import 'color_detector.dart';

class PlayerRegistration {
  final String jersey;
  final String name;
  final List<String> photoPaths;
  // Auto-detected from the first (close-up) reference photo
  final JerseyColors? colors;

  PlayerRegistration({
    required this.jersey,
    required this.name,
    this.photoPaths = const [],
    this.colors,
  });

  Map<String, dynamic> toMap() => {
    'jersey':     jersey,
    'name':       name,
    'photoPaths': jsonEncode(photoPaths),
    'colors':     colors != null ? jsonEncode(colors!.toMap()) : null,
  };

  factory PlayerRegistration.fromMap(Map<String, dynamic> map) => PlayerRegistration(
    jersey:     map['jersey'] as String,
    name:       map['name']   as String,
    photoPaths: List<String>.from(jsonDecode(map['photoPaths'] as String? ?? '[]')),
    colors: map['colors'] != null
        ? JerseyColors.fromMap(jsonDecode(map['colors'] as String))
        : null,
  );

  PlayerRegistration copyWith({List<String>? photoPaths, JerseyColors? colors}) =>
      PlayerRegistration(
        jersey:     jersey,
        name:       name,
        photoPaths: photoPaths ?? this.photoPaths,
        colors:     colors ?? this.colors,
      );
}

class TeamModel {
  final int?   id;
  final String name;
  final DateTime createdAt;
  final List<PlayerRegistration> players;

  TeamModel({
    this.id,
    required this.name,
    required this.createdAt,
    required this.players,
  });

  Map<String, dynamic> toMap() => {
    'name':      name,
    'createdAt': createdAt.toIso8601String(),
    'players':   jsonEncode(players.map((p) => p.toMap()).toList()),
  };

  factory TeamModel.fromMap(Map<String, dynamic> map) => TeamModel(
    id:        map['id']   as int?,
    name:      map['name'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
    players:   (jsonDecode(map['players'] as String) as List)
        .map((p) => PlayerRegistration.fromMap(p as Map<String, dynamic>))
        .toList(),
  );
}
