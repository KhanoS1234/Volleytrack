import 'dart:async';
import 'dart:ui' show Rect, Offset;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/game_event.dart';
import '../models/player_config.dart';
import '../services/camera_service.dart';
import '../services/database_service.dart';

class TrackingViewModel extends ChangeNotifier {
  final List<PlayerConfig> players;

  final CameraService _cameraService = CameraService();
  final DatabaseService _db = DatabaseService();

  // Per-player stats
  final Map<String, PlayerStats> stats = {};

  // Per-player tracking state
  final Map<String, bool> playerLocked  = {};
  final Map<String, bool> playerVisible = {};
  final Map<String, Rect?> playerBoxes  = {};
  final Map<String, List<PoseLandmark>> skeletons = {};
  final Map<String, double> confidences = {};

  // Flash state
  bool showFlash = false;
  String? flashJersey;
  EventType? flashType;

  // Session timer
  int timerSeconds = 0;
  Timer? _sessionTimer;
  Timer? _flashTimer;
  final Map<String, Timer?> _playerLostTimers = {};

  // Which player is selected for manual logging
  int selectedPlayerIndex = 0;

  get cameraController => _cameraService.controller;

  TrackingViewModel({required this.players}) {
    for (final p in players) {
      stats[p.jersey]         = PlayerStats(jersey: p.jersey, name: p.name);
      playerLocked[p.jersey]  = false;
      playerVisible[p.jersey] = false;
      playerBoxes[p.jersey]   = null;
      skeletons[p.jersey]     = [];
      confidences[p.jersey]   = 0.0;
    }
  }

  Future<void> initialise() async {
    await _cameraService.initialise();

    // Wire up pose analysers for each player
    for (final p in players) {
      _cameraService.poseAnalysers[p.jersey]?.onHitDetected = () {
        recordEvent(p.jersey, EventType.hit, auto: true);
      };
      _cameraService.poseAnalysers[p.jersey]?.onBlockDetected = () {
        recordEvent(p.jersey, EventType.block, auto: true);
      };
    }

    _cameraService.onPlayerDetected = (jersey, box) {
      playerLocked[jersey]  = true;
      playerVisible[jersey] = true;
      playerBoxes[jersey]   = box;

      _playerLostTimers[jersey]?.cancel();
      _playerLostTimers[jersey] = Timer(const Duration(seconds: 2), () {
        playerVisible[jersey] = false;
        notifyListeners();
      });

      notifyListeners();
    };

    _cameraService.onPlayerLost = (jersey) {
      playerVisible[jersey] = false;
      notifyListeners();
    };

    _cameraService.onPoseUpdated = (landmarks, confidence, jersey) {
      skeletons[jersey]     = landmarks;
      confidences[jersey]   = confidence;
      notifyListeners();
    };

    await _cameraService.startCamera(players.map((p) => p.jersey).toList());
    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      timerSeconds++;
      // Increment game time for all visible players
      for (final p in players) {
        if (playerVisible[p.jersey] == true) {
          stats[p.jersey]?.gameTimeSeconds++;
        }
      }
      notifyListeners();
    });
  }

  void recordEvent(String jersey, EventType type, {bool auto = false}) {
    stats[jersey]?.recordEvent(type, timerSeconds, auto: auto);
    flashJersey = jersey;
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

  void selectPlayer(int index) {
    selectedPlayerIndex = index;
    notifyListeners();
  }

  PlayerConfig get selectedPlayer => players[selectedPlayerIndex];

  Future<List<PlayerStats>> endSession() async {
    _sessionTimer?.cancel();
    _flashTimer?.cancel();
    for (final t in _playerLostTimers.values) t?.cancel();
    await _cameraService.stopCamera();

    final results = players.map((p) => stats[p.jersey]!).toList();
    // Save each player's session
    for (final s in results) {
      await _db.saveSession(s.toSessionModel());
    }
    return results;
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
    for (final t in _playerLostTimers.values) t?.cancel();
    _cameraService.dispose();
    super.dispose();
  }
}

// Extension to convert PlayerStats to SessionModel for saving
extension PlayerStatsExt on PlayerStats {
  dynamic toSessionModel() {
    // Returns a map that DatabaseService can save
    return {
      'jersey': jersey,
      'playerName': name,
      'date': DateTime.now().toIso8601String(),
      'durationSeconds': gameTimeSeconds,
      'hits': hits,
      'blocks': blocks,
      'points': points,
      'eventsJson': '[]',
    };
  }
}
