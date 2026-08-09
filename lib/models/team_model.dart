import 'dart:convert';

class PlayerRegistration {
  final String jersey;
  final String name;
  // Paths to 3 reference photos saved on device
  final List<String> photoPaths;

  PlayerRegistration({
    required this.jersey,
    required this.name,
    this.photoPaths = const [],
  });

  Map<String, dynamic> toMap() => {
    'jersey':     jersey,
    'name':       name,
    'photoPaths': jsonEncode(photoPaths),
  };

  factory PlayerRegistration.fromMap(Map<String, dynamic> map) => PlayerRegistration(
    jersey:     map['jersey'] as String,
    name:       map['name']   as String,
    photoPaths: List<String>.from(jsonDecode(map['photoPaths'] as String? ?? '[]')),
  );

  PlayerRegistration copyWith({List<String>? photoPaths}) => PlayerRegistration(
    jersey:     jersey,
    name:       name,
    photoPaths: photoPaths ?? this.photoPaths,
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
