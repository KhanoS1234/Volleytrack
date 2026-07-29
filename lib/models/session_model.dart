import 'game_event.dart';

class SessionModel {
  final int? id;
  final String jersey;
  final String playerName;
  final DateTime date;
  final int durationSeconds;
  final int hits;
  final int blocks;
  final int points;
  final List<GameEvent> events;

  SessionModel({
    this.id,
    required this.jersey,
    required this.playerName,
    required this.date,
    required this.durationSeconds,
    required this.hits,
    required this.blocks,
    required this.points,
    required this.events,
  });

  double get pointPercentage => hits > 0 ? (points / hits) * 100 : 0;

  String get formattedDuration {
    final m = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Map<String, dynamic> toMap() => {
    'jersey': jersey,
    'playerName': playerName,
    'date': date.toIso8601String(),
    'durationSeconds': durationSeconds,
    'hits': hits,
    'blocks': blocks,
    'points': points,
  };
}
