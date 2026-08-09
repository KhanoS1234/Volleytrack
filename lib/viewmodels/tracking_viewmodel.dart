import 'dart:async';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/game_event.dart';
import '../models/player_config.dart';
import '../services/camera_service.dart';
import '../services/database_service.dart';

class TrackingViewModel extends ChangeNotifier {
  final List<PlayerConfig> players;

  final CameraService   _cameraService = CameraService();
  final DatabaseService _db            = DatabaseService();

  final Map<String, PlayerStats>            stats         = {};
  final Map<String, bool>                   playerLocked  = {};
  final Map<String, bool>                   playerVisible = {};
  final Map<String, Rect?>                  playerBoxes   = {};
  final Map<String, List<PoseLandmark>>     skeletons     = {};
  final Map<String, double>                 confidences   = {};

  bool       showFlash  = false;
  String?    flashJersey;
  EventType? flashType;
  String?    flashSource;

  int timerSeconds = 0;
  Timer? _sessionTimer;
  Timer? _flashTimer;
  final Map<String, Timer?> _playerLostTimers = {};

  int selectedPlayerIndex = 0;

  bool isInitialising = true;
  String initStatus   = 'Starting camera...';

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
    // Step 1 — Register reference photos
    if (players.any((p) => p.photoPaths.isNotEmpty)) {
      initStatus = 'Loading reference photos...';
      notifyListeners();

      for (final p in players) {
        if (p.photoPaths.isNotEmpty) {
          await _cameraService.registerPlayerPhotos(
              p.jersey, p.photoPaths);
        }
      }
    }

    // Step 2 — Start camera
    initStatus = 'Starting camera...';
    notifyListeners();

    await _cameraService.initialise();

    for (final p in players) {
      _cameraService.poseAnalysers[p.jersey]?.onHitDetected = () {
        recordEvent(p.jersey, EventType.hit, auto: true, source: 'Pose');
      };
      _cameraService.poseAnalysers[p.jersey]?.onBlockDetected = () {
        recordEvent(p.jersey, EventType.block, auto: true, source: 'Pose');
      };
    }

    _cameraService.onPlayerDetected = (jersey, box) {
      playerLocked[jersey]  = true;
      playerVisible[jersey] = true;
      playerBoxes[jersey]   = box;

      _playerLostTimers[jersey]?.cancel();
      _playerLostTimers[jersey] = Timer(const Duration(seconds: 5), () {
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
      skeletons[jersey]   = landmarks;
      confidences[jersey] = confidence;
      notifyListeners();
    };

    await _cameraService.startCamera(players.map((p) => p.jersey).toList());

    isInitialising = false;
    notifyListeners();

    // Start session timer
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      timerSeconds++;
      for (final p in players) {
        if (playerVisible[p.jersey] == true) {
          stats[p.jersey]?.gameTimeSeconds++;
        }
      }
      notifyListeners();
    });
  }

  void recordEvent(String jersey, EventType type,
      {bool auto = false, String source = 'Manual'}) {
    stats[jersey]?.recordEvent(type, timerSeconds, auto: auto);
    flashJersey = jersey;
    flashSource = source;
    showFlash   = true;
    flashType   = type;
    notifyListeners();

    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
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
    for (final t in _playerLostTimers.values) {
      t?.cancel();
    }
    await _cameraService.stopCamera();

    final results = players.map((p) => stats[p.jersey]!).toList();

    for (final s in results) {
      final db = await _db.database;
      await db.insert('sessions', {
        'jersey':          s.jersey,
        'playerName':      s.name,
        'date':            DateTime.now().toIso8601String(),
        'durationSeconds': s.gameTimeSeconds,
        'hits':            s.hits,
        'blocks':          s.blocks,
        'points':          s.points,
        'eventsJson':      '[]',
      });
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
    for (final t in _playerLostTimers.values) {
      t?.cancel();
    }
    _cameraService.dispose();
    super.dispose();
  }
}
