import 'dart:async';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/game_event.dart';
import '../models/player_config.dart';
import '../services/camera_service.dart';
import '../services/database_service.dart';

class TrackingViewModel extends ChangeNotifier {
  // Every registered player on the team. The camera searches for ALL
  // of these continuously — whoever gets detected automatically
  // becomes "on court" (up to maxActivePlayers), no manual sub-on
  // needed. If a locked player can't be found for the hold timeout,
  // they're automatically dropped back to the bench.
  final List<PlayerConfig> fullRoster;

  // Currently on-court, actively tracked players — populated and
  // emptied AUTOMATICALLY based on detection, not manual button taps
  List<PlayerConfig> activePlayers;

  final CameraService   _cameraService = CameraService();
  final DatabaseService _db            = DatabaseService();

  static const int maxActivePlayers = 6;

  // Stats persist per jersey across the WHOLE session, including
  // through automatic on/off-court transitions — a player who goes
  // off court and is later re-detected keeps their running totals
  final Map<String, PlayerStats> stats = {};
  // Every jersey that appeared on court at any point this session —
  // used to build the final stats summary
  final Set<String> jerseysThatPlayed = {};

  final Map<String, bool>               playerLocked  = {};
  final Map<String, bool>               playerVisible = {};
  final Map<String, Rect?>              playerBoxes   = {};
  final Map<String, List<PoseLandmark>> skeletons     = {};
  final Map<String, double>             confidences   = {};
  final Map<String, String>             lockSource    = {};
  final Map<String, bool>               isCrossing    = {};

  bool       showFlash  = false;
  String?    flashJersey;
  EventType? flashType;
  String?    flashSource;

  int timerSeconds = 0;
  Timer? _sessionTimer;
  Timer? _flashTimer;
  final Map<String, Timer?> _playerLostTimers = {};

  int selectedPlayerIndex = 0;

  get cameraController => _cameraService.controller;

  /// Registered players NOT currently on court — these are being
  /// actively searched for; they'll move to activePlayers automatically
  /// the moment the camera confidently detects them.
  List<PlayerConfig> get benchPlayers => fullRoster
      .where((p) => !activePlayers.any((a) => a.jersey == p.jersey))
      .toList();

  bool get isRosterFull => activePlayers.length >= maxActivePlayers;

  TrackingViewModel({
    required List<PlayerConfig> initialPlayers,
    required this.fullRoster,
  }) : activePlayers = List.from(initialPlayers) {
    for (final p in activePlayers) {
      _initPlayerState(p.jersey, p.name);
    }
  }

  void _initPlayerState(String jersey, String name) {
    stats.putIfAbsent(jersey, () => PlayerStats(jersey: jersey, name: name));
    playerLocked[jersey]  = false;
    playerVisible[jersey] = false;
    playerBoxes[jersey]   = null;
    skeletons[jersey]     = [];
    confidences[jersey]   = 0.0;
    lockSource[jersey]    = '';
    isCrossing[jersey]    = false;
    jerseysThatPlayed.add(jersey);
  }

  void _wirePoseCallbacks(String jersey) {
    _cameraService.poseAnalysers[jersey]?.onHitDetected = () {
      recordEvent(jersey, EventType.hit, auto: true, source: 'Pose');
    };
    _cameraService.poseAnalysers[jersey]?.onBlockDetected = () {
      recordEvent(jersey, EventType.block, auto: true, source: 'Pose');
    };
  }

  Future<void> initialise() async {
    // Register reference photos & colours for the FULL roster up front
    for (final p in fullRoster) {
      if (p.photoPaths.isNotEmpty) {
        await _cameraService.registerPlayerPhotos(p.jersey, p.photoPaths);
      }
      if (p.detectedColors != null) {
        _cameraService.registerPlayerColors(p.jersey, p.detectedColors);
      }
    }

    await _cameraService.initialise();

    // Wire pose callbacks for the FULL roster — any of them could be
    // automatically detected and promoted to on-court at any time
    for (final p in fullRoster) {
      _wirePoseCallbacks(p.jersey);
    }

    _cameraService.onPlayerDetected = (jersey, box, source) {
      // AUTOMATIC PROMOTION — if this jersey isn't currently on court,
      // add them now. No manual action needed; this fires the moment
      // the camera pipeline confidently locks onto them.
      if (!activePlayers.any((p) => p.jersey == jersey)) {
        if (activePlayers.length < maxActivePlayers) {
          final config = fullRoster.firstWhere(
            (p) => p.jersey == jersey,
            orElse: () => PlayerConfig(
              jersey: jersey,
              name: 'Player #$jersey',
              color: PlayerColors.colorForJersey(jersey),
            ),
          );
          activePlayers.add(config);
          _initPlayerState(jersey, config.name);
        } else {
          // No free slot — camera_service's own capacity check should
          // already prevent this, but guard here too just in case
          return;
        }
      }

      playerLocked[jersey]  = true;
      playerVisible[jersey] = true;
      playerBoxes[jersey]   = box;
      lockSource[jersey]    = source;

      _playerLostTimers[jersey]?.cancel();
      _playerLostTimers[jersey] = Timer(const Duration(seconds: 5), () {
        playerVisible[jersey] = false;
        notifyListeners();
      });

      notifyListeners();
    };

    _cameraService.onPlayerLost = (jersey, wasLocked) {
      playerVisible[jersey] = false;
      lockSource[jersey]    = '';
      skeletons[jersey]     = [];

      if (wasLocked) {
        // AUTOMATIC DEMOTION — this player was on court and could not
        // be found for the full hold period (or was manually/watchdog
        // removed). They go back to the bench automatically. Their
        // stats stay intact in case they're detected again later.
        activePlayers.removeWhere((p) => p.jersey == jersey);
        playerLocked[jersey] = false;
        _playerLostTimers[jersey]?.cancel();

        if (activePlayers.isEmpty) {
          selectedPlayerIndex = 0;
        } else if (selectedPlayerIndex >= activePlayers.length) {
          selectedPlayerIndex = activePlayers.length - 1;
        }
      }
      // If wasLocked is false, this player was never on court in the
      // first place — nothing to demote, just still searching for them

      notifyListeners();
    };

    _cameraService.onProximityCrossing = (jerseyA, jerseyB) {
      isCrossing[jerseyA] = true;
      isCrossing[jerseyB] = true;
      notifyListeners();

      Timer(const Duration(milliseconds: 800), () {
        isCrossing[jerseyA] = false;
        isCrossing[jerseyB] = false;
        notifyListeners();
      });
    };

    _cameraService.onPoseUpdated = (landmarks, confidence, jersey) {
      skeletons[jersey]   = landmarks;
      confidences[jersey] = confidence;
      notifyListeners();
    };

    // Search space is the FULL roster from the very start — this is
    // what enables automatic detection/promotion of any registered
    // player, not just the ones pre-selected on the setup screen
    await _cameraService.startCamera(fullRoster.map((p) => p.jersey).toList());

    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      timerSeconds++;
      for (final p in activePlayers) {
        if (playerVisible[p.jersey] == true) {
          stats[p.jersey]?.gameTimeSeconds++;
        }
      }
      notifyListeners();
    });

    notifyListeners();
  }

  /// MANUAL OVERRIDE — permanently stop tracking this player for the
  /// rest of the session (e.g. injury, they're done playing). This is
  /// different from the normal automatic on/off-court behaviour —
  /// once removed here, they will NOT be auto-detected again even if
  /// they reappear on camera.
  void removePlayerPermanently(String jersey) {
    activePlayers.removeWhere((p) => p.jersey == jersey);
    _cameraService.removePlayerPermanently(jersey);

    playerVisible[jersey] = false;
    playerLocked[jersey]  = false;
    skeletons[jersey]     = [];
    lockSource[jersey]    = '';
    _playerLostTimers[jersey]?.cancel();

    if (activePlayers.isEmpty) {
      selectedPlayerIndex = 0;
    } else if (selectedPlayerIndex >= activePlayers.length) {
      selectedPlayerIndex = activePlayers.length - 1;
    }

    notifyListeners();
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

  PlayerConfig? get selectedPlayer =>
      activePlayers.isEmpty ? null : activePlayers[selectedPlayerIndex];

  Future<List<PlayerStats>> endSession() async {
    _sessionTimer?.cancel();
    _flashTimer?.cancel();
    for (final t in _playerLostTimers.values) {
      t?.cancel();
    }
    await _cameraService.stopCamera();

    final results = jerseysThatPlayed.map((j) => stats[j]!).toList();

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
