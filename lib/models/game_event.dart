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
