enum EventType { hit, block, point }

class GameEvent {
  final EventType type;
  final int timestampSeconds;
  final bool isAutoDetected;

  GameEvent({
    required this.type,
    required this.timestampSeconds,
    this.isAutoDetected = true,
  });

  String get typeName {
    switch (type) {
      case EventType.hit:   return 'Hit';
      case EventType.block: return 'Block';
      case EventType.point: return 'Point';
    }
  }

  String get typeEmoji {
    switch (type) {
      case EventType.hit:   return '💥';
      case EventType.block: return '🤚';
      case EventType.point: return '✅';
    }
  }

  Map<String, dynamic> toMap() => {
    'type': type.index,
    'timestampSeconds': timestampSeconds,
    'isAutoDetected': isAutoDetected ? 1 : 0,
  };

  factory GameEvent.fromMap(Map<String, dynamic> map) => GameEvent(
    type: EventType.values[map['type'] as int],
    timestampSeconds: map['timestampSeconds'] as int,
    isAutoDetected: (map['isAutoDetected'] as int) == 1,
  );
}

/// Stats for a single player during a session
class PlayerStats {
  final String jersey;
  final String name;
  int hits = 0;
  int blocks = 0;
  int points = 0;
  int gameTimeSeconds = 0;
  bool isOnCourt = false;
  final List<GameEvent> events = [];

  PlayerStats({required this.jersey, required this.name});

  int get pointPercentage =>
      hits > 0 ? ((points / hits) * 100).round() : 0;

  String get formattedTime {
    final m = (gameTimeSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (gameTimeSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void recordEvent(EventType type, int timestamp, {bool auto = false}) {
    switch (type) {
      case EventType.hit:   hits++;   break;
      case EventType.block: blocks++; break;
      case EventType.point: points++; break;
    }
    events.add(GameEvent(
      type: type,
      timestampSeconds: timestamp,
      isAutoDetected: auto,
    ));
  }
}
