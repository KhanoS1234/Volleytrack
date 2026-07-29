import 'dart:async';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import '../models/game_event.dart';
import '../models/session_model.dart';
import '../services/camera_service.dart';
import '../services/database_service.dart';

class TrackingViewModel extends ChangeNotifier {
  final String jersey;
  final String playerName;

  final CameraService _cameraService = CameraService();
  final DatabaseService _db = DatabaseService();

  int hits = 0;
  int blocks = 0;
  int points = 0;
  int timerSeconds = 0;
  final List<GameEvent> events = [];

  bool isPlayerLocked = false;
  Rect? playerBoundingBox;
  bool showFlash = false;
  EventType? flashType;

  Timer? _flashTimer;
  Timer? _sessionTimer;

  get cameraController => _cameraService.controller;

  int get pointPercentage => hits > 0 ? ((points / hits) * 100).round() : 0;

  TrackingViewModel({required this.jersey, required this.playerName});

  Future<void> initialise() async {
    await _cameraService.initialise();

    _cameraService.poseAnalyser.onHitDetected   = () => recordEvent(EventType.hit,   auto: true);
    _cameraService.poseAnalyser.onBlockDetected = () => recordEvent(EventType.block, auto: true);

    _cameraService.onPlayerDetected = (number, box) {
      isPlayerLocked = true;
      playerBoundingBox = box;
      notifyListeners();
    };

    await _cameraService.startCamera(jersey);
    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      timerSeconds++;
      notifyListeners();
    });
  }

  void recordEvent(EventType type, {bool auto = false}) {
    switch (type) {
      case EventType.hit:   hits++;   break;
      case EventType.block: blocks++; break;
      case EventType.point: points++; break;
    }
    events.add(GameEvent(type: type, timestampSeconds: timerSeconds, isAutoDetected: auto));
    _triggerFlash(type);
    notifyListeners();
  }

  void _triggerFlash(EventType type) {
    showFlash = true;
    flashType = type;
    notifyListeners();
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1200), () {
      showFlash = false;
      notifyListeners();
    });
  }

  Future<SessionModel> endSession() async {
    _sessionTimer?.cancel();
    _flashTimer?.cancel();
    await _cameraService.stopCamera();

    final session = SessionModel(
      jersey: jersey,
      playerName: playerName,
      date: DateTime.now(),
      durationSeconds: timerSeconds,
      hits: hits,
      blocks: blocks,
      points: points,
      events: List.from(events),
    );
    await _db.saveSession(session);
    return session;
  }

  String get formattedTime {
    final m = (timerSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (timerSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _flashTimer?.cancel();
    _cameraService.dispose();
    super.dispose();
  }
}
