import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:ui' show Rect, Size, Offset;
import 'pose_analyser.dart';
import 'photo_matcher.dart';
import 'color_matcher.dart';
import 'color_detector.dart';
import 'detection_settings.dart';

class CameraService {
  CameraController? controller;
  List<CameraDescription> _cameras = [];

  final DetectionSettings _settings = DetectionSettings();

  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  final PhotoMatcher _photoMatcher = PhotoMatcher();
  final ColorMatcher _colorMatcher = ColorMatcher();
  final Map<String, PoseAnalyser> poseAnalysers = {};

  bool _isProcessing = false;
  List<String> _targetJerseys = [];
  int _frameCount = 0;

  static const int _ocrEveryNFrames    = 1;
  static const int _ocrAfterLockFrames = 45;
  static const int _photoEveryNFrames  = 5;
  static const int _colorEveryNFrames  = 6;
  static const int _maxFramesWithoutDetection = 300;
  static const double _maxReacquisitionDistance = 200000.0;
  static const int _relockConfirmationFrames = 3;

  static const double _frameW = 1280.0;
  static const double _frameH = 720.0;

  static const double _minDetectionY = 0.15;
  static const double _maxDetectionY = 0.95;
  static const double _maxDetectionWidth = 250.0;

  // ── RE-IDENTIFICATION SETTINGS ──────────────────────────────────────────
  // How often to re-verify a LOCKED player still matches their reference
  // photos. Lower cost than the initial-lock photo matching since it only
  // checks the player's own known box region, not the whole frame.
  static const int _appearanceCheckEveryNFrames = 18; // ~2x per second at 30fps

  // How much a NEW lock candidate's box can overlap with an ALREADY
  // locked player's box before we reject the new lock. Prevents two
  // different jerseys from both claiming the same physical player.
  static const double _newLockOccupancyThreshold = 0.30; // 30% overlap

  // If two ALREADY-locked players' boxes overlap by more than this
  // fraction, treat it as a "crossing" event — freeze position updates
  // for both until they separate. Brief and expected during normal play.
  static const double _proximityOverlapThreshold = 0.15; // 15% overlap

  // Watchdog: if two already-locked players stay overlapping above this
  // fraction for this many consecutive frames, we assume they've become
  // double-locked onto the same person (slipped past the initial check)
  // and drop the more recently locked one to force re-acquisition.
  static const double _sustainedOverlapThreshold = 0.60; // 60% overlap
  static const int _sustainedOverlapFrames = 60; // ~2 seconds at 30fps

  final Map<String, int>     _consecutiveDetections = {};
  final Map<String, Rect?>   _lastKnownBoxes        = {};
  final Map<String, int>     _framesSinceDetection  = {};
  final Map<String, bool>    _playerLockedPermanent = {};
  final Map<String, int>     _relockCandidateCount  = {};
  final Map<String, Offset?> _relockCandidatePos    = {};
  final Map<String, String>  _lockSource            = {};

  // Re-identification state
  final Map<String, bool> _isFrozen = {}; // true during a proximity crossing
  final Map<String, int>  _framesSinceAppearanceCheck = {};

  // When each player was most recently locked — used by the sustained
  // overlap watchdog to determine which of two double-locked players
  // is "newer" and should be dropped
  final Map<String, DateTime> _lockedAtTime = {};

  // Tracks consecutive frames each PAIR of players has been overlapping
  // above the sustained-overlap threshold, keyed as "jerseyA|jerseyB"
  final Map<String, int> _sustainedOverlapCounters = {};

  Function(String jersey, Rect boundingBox, String source)? onPlayerDetected;
  Function(String jersey)?                                  onPlayerLost;
  Function(List<PoseLandmark> landmarks, double confidence, String jersey)?
      onPoseUpdated;
  // Fired when a proximity crossing is detected between two players
  Function(String jerseyA, String jerseyB)? onProximityCrossing;

  Future<void> initialise() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) throw Exception('No cameras found');
  }

  Future<void> registerPlayerPhotos(
      String jersey, List<String> photoPaths) async {
    await _photoMatcher.registerPlayer(jersey, photoPaths);
  }

  /// Register a player's auto-detected jersey colours so they can be
  /// used as a pre-filter and confidence booster during tracking.
  void registerPlayerColors(String jersey, JerseyColors? colors) {
    _colorMatcher.registerPlayerColor(jersey, colors);
  }

  Future<void> startCamera(List<String> targetJerseys) async {
    _targetJerseys = targetJerseys;

    for (final jersey in targetJerseys) {
      poseAnalysers[jersey]                  = PoseAnalyser();
      _consecutiveDetections[jersey]         = 0;
      _lastKnownBoxes[jersey]                = null;
      _framesSinceDetection[jersey]          = 0;
      _playerLockedPermanent[jersey]         = false;
      _relockCandidateCount[jersey]          = 0;
      _relockCandidatePos[jersey]            = null;
      _lockSource[jersey]                    = '';
      _isFrozen[jersey]                      = false;
      _framesSinceAppearanceCheck[jersey]    = 0;
      _lockedAtTime.remove(jersey);
    }

    if (_cameras.isEmpty) await initialise();

    final backCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    controller = CameraController(
      backCamera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );

    await controller!.initialize();
    await controller!.setFocusMode(FocusMode.auto);
    await controller!.setExposureMode(ExposureMode.auto);

    // Explicitly lock the camera's capture orientation to match the
    // app's locked landscape orientation. Without this, iOS can pick
    // either landscape direction inconsistently, which flips the
    // preview upside down relative to what the sensor actually sees.
    await controller!.lockCaptureOrientation(DeviceOrientation.landscapeLeft);

    await controller!.startImageStream(_processFrame);
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;
    _frameCount++;

    for (final jersey in _targetJerseys) {
      _framesSinceDetection[jersey] =
          (_framesSinceDetection[jersey] ?? 0) + 1;
      _framesSinceAppearanceCheck[jersey] =
          (_framesSinceAppearanceCheck[jersey] ?? 0) + 1;
    }

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      // 1. Check for proximity crossings BEFORE updating positions —
      //    this determines whether we should freeze this frame
      _checkProximityCrossings();

      // 1b. Watchdog — catch cases where two players ended up double-
      // locked onto the same person despite the occupancy check at
      // lock-time (e.g. if their positions drifted together afterwards)
      _checkSustainedOverlapWatchdog();

      // 2. Pose detection every frame
      final poses = await _poseDetector.processImage(inputImage);
      _assignPosesToPlayers(poses);

      // 3. OCR
      final anyLocked   = _playerLockedPermanent.values.any((v) => v);
      final ocrInterval = anyLocked ? _ocrAfterLockFrames : _ocrEveryNFrames;
      if (_frameCount % ocrInterval == 0) {
        await _runOCR(inputImage, image.planes[0].bytes,
            image.width.toDouble(), image.height.toDouble());
      }

      // 4. Photo matching for unlocked players (initial acquisition)
      final hasUnlocked = _playerLockedPermanent.values.any((v) => !v);
      if (hasUnlocked &&
          _photoMatcher.hasFingerprints &&
          _frameCount % _photoEveryNFrames == 0 &&
          image.planes.isNotEmpty) {
        await _runPhotoMatch(image);
      }

      // 4b. Colour region scanning for unlocked players — a third,
      // lightweight signal alongside OCR and photo matching. Colour
      // alone is a weaker signal (many things can share a colour) so
      // it requires more consecutive confirmations before locking.
      if (hasUnlocked &&
          _colorMatcher.hasColors &&
          _frameCount % _colorEveryNFrames == 0 &&
          image.planes.isNotEmpty) {
        await _runColorScan(image);
      }

      // 5. Appearance re-verification for LOCKED players (re-identification)
      if (_photoMatcher.hasFingerprints) {
        await _runAppearanceVerification(image);
      }

      // 6. Handle locked/lost state
      for (final jersey in _targetJerseys) {
        final framesSince = _framesSinceDetection[jersey] ?? 0;
        final isLocked    = _playerLockedPermanent[jersey] ?? false;

        if (isLocked) {
          if (framesSince > _maxFramesWithoutDetection) {
            _resetPlayerLock(jersey);
            onPlayerLost?.call(jersey);
          } else if (_lastKnownBoxes[jersey] != null) {
            onPlayerDetected?.call(
                jersey, _lastKnownBoxes[jersey]!, _lockSource[jersey] ?? 'SKELETON');
          }
        } else {
          if (framesSince > 30) {
            onPlayerLost?.call(jersey);
          }
        }
      }

    } catch (_) {
      // Continue silently
    } finally {
      _isProcessing = false;
    }
  }

  /// Watchdog — detects when two already-locked players have been
  /// heavily overlapping (much more than a normal brief crossing) for
  /// several consecutive seconds. This catches double-locks that slip
  /// past the initial occupancy check, for example if both players'
  /// boxes drift together over time via skeleton tracking. When found,
  /// the more recently locked jersey is dropped so it can re-acquire
  /// correctly elsewhere.
  void _checkSustainedOverlapWatchdog() {
    final lockedJerseys = _targetJerseys
        .where((j) => _playerLockedPermanent[j] == true)
        .toList();

    // Track which pairs are currently overlapping heavily this frame
    final Set<String> activePairs = {};

    for (int i = 0; i < lockedJerseys.length; i++) {
      for (int j = i + 1; j < lockedJerseys.length; j++) {
        final jerseyA = lockedJerseys[i];
        final jerseyB = lockedJerseys[j];
        final boxA = _lastKnownBoxes[jerseyA];
        final boxB = _lastKnownBoxes[jerseyB];
        if (boxA == null || boxB == null) continue;

        final overlap = _overlapFraction(boxA, boxB);
        final pairKey = '$jerseyA|$jerseyB';

        if (overlap > _sustainedOverlapThreshold) {
          activePairs.add(pairKey);
          _sustainedOverlapCounters[pairKey] =
              (_sustainedOverlapCounters[pairKey] ?? 0) + 1;

          if ((_sustainedOverlapCounters[pairKey] ?? 0) >= _sustainedOverlapFrames) {
            // Sustained double-lock detected — drop whichever jersey
            // was locked more recently, keep the more established one
            final lockedAtA = _lockedAtTime[jerseyA];
            final lockedAtB = _lockedAtTime[jerseyB];

            String toDrop;
            if (lockedAtA == null) {
              toDrop = jerseyA;
            } else if (lockedAtB == null) {
              toDrop = jerseyB;
            } else {
              toDrop = lockedAtA.isAfter(lockedAtB) ? jerseyA : jerseyB;
            }

            _resetPlayerLock(toDrop);
            onPlayerLost?.call(toDrop);
            _sustainedOverlapCounters[pairKey] = 0;
          }
        }
      }
    }

    // Reset counters for pairs no longer overlapping heavily this frame
    final staleKeys = _sustainedOverlapCounters.keys
        .where((k) => !activePairs.contains(k))
        .toList();
    for (final key in staleKeys) {
      _sustainedOverlapCounters[key] = 0;
    }
  }

  /// Check if any two tracked players' boxes are overlapping significantly.
  /// If so, freeze position updates for both until they separate — this
  /// prevents the skeleton from silently "jumping" to the wrong player
  /// during a crossing.
  void _checkProximityCrossings() {
    final lockedJerseys = _targetJerseys
        .where((j) => _playerLockedPermanent[j] == true)
        .toList();

    // Reset freeze state first — will be re-set below if still overlapping
    for (final jersey in lockedJerseys) {
      _isFrozen[jersey] = false;
    }

    for (int i = 0; i < lockedJerseys.length; i++) {
      for (int j = i + 1; j < lockedJerseys.length; j++) {
        final boxA = _lastKnownBoxes[lockedJerseys[i]];
        final boxB = _lastKnownBoxes[lockedJerseys[j]];
        if (boxA == null || boxB == null) continue;

        final overlap = _overlapFraction(boxA, boxB);
        if (overlap > _proximityOverlapThreshold) {
          _isFrozen[lockedJerseys[i]] = true;
          _isFrozen[lockedJerseys[j]] = true;
          onProximityCrossing?.call(lockedJerseys[i], lockedJerseys[j]);
        }
      }
    }
  }

  /// Calculate what fraction of the smaller box's area overlaps with
  /// the other box. Returns 0.0 (no overlap) to 1.0 (fully contained).
  double _overlapFraction(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;

    final intersectionArea = intersection.width * intersection.height;
    final smallerArea = (a.width * a.height) < (b.width * b.height)
        ? a.width * a.height
        : b.width * b.height;

    if (smallerArea <= 0) return 0.0;
    return intersectionArea / smallerArea;
  }

  /// Periodically re-verify that a locked player's current box region
  /// still visually matches their reference photos. Catches silent
  /// identity switches that proximity freezing alone might miss.
  Future<void> _runAppearanceVerification(CameraImage image) async {
    for (final jersey in _targetJerseys) {
      final isLocked = _playerLockedPermanent[jersey] ?? false;
      if (!isLocked) continue;

      final framesSince = _framesSinceAppearanceCheck[jersey] ?? 0;
      if (framesSince < _appearanceCheckEveryNFrames) continue;

      _framesSinceAppearanceCheck[jersey] = 0;

      final box = _lastKnownBoxes[jersey];
      if (box == null) continue;

      try {
        final bytes = image.planes[0].bytes;
        final stillMatches = await _photoMatcher.verifyRegionMatches(
          bytes, image.width, image.height, jersey, box,
        );

        if (stillMatches == false) {
          // Appearance no longer matches — likely an identity switch.
          // Drop the lock so OCR/photo matching can re-acquire correctly.
          _resetPlayerLock(jersey);
          onPlayerLost?.call(jersey);
        }
        // If stillMatches is null (couldn't determine), we don't act —
        // avoids false drops from poor lighting or motion blur.
      } catch (_) {
        // Continue silently — don't drop lock on a processing error
      }
    }
  }

  void _resetPlayerLock(String jersey) {
    _playerLockedPermanent[jersey]      = false;
    _consecutiveDetections[jersey]      = 0;
    _relockCandidateCount[jersey]       = 0;
    _relockCandidatePos[jersey]         = null;
    _lockSource[jersey]                 = '';
    _isFrozen[jersey]                   = false;
    _framesSinceAppearanceCheck[jersey] = 0;
    _lockedAtTime.remove(jersey);
  }

  void _tryLockPlayer(String jersey, Rect detectedBox, String source) {
    final isLocked       = _playerLockedPermanent[jersey] ?? false;
    final lastBox        = _lastKnownBoxes[jersey];
    final detectedCentre = Offset(
      detectedBox.left + detectedBox.width  / 2,
      detectedBox.top  + detectedBox.height / 2,
    );

    if (isLocked && lastBox != null) {
      final lastCentre = Offset(
        lastBox.left + lastBox.width  / 2,
        lastBox.top  + lastBox.height / 2,
      );
      final dist = _squaredDistance(
        detectedCentre.dx, detectedCentre.dy,
        lastCentre.dx,     lastCentre.dy,
      );
      if (dist > _maxReacquisitionDistance) return;
      _lastKnownBoxes[jersey]       = detectedBox;
      _framesSinceDetection[jersey] = 0;
      _lockSource[jersey]           = source;
      return;
    }

    final lastCandidate = _relockCandidatePos[jersey];
    if (lastCandidate != null) {
      final dist = _squaredDistance(
        detectedCentre.dx, detectedCentre.dy,
        lastCandidate.dx,  lastCandidate.dy,
      );
      if (dist < _maxReacquisitionDistance) {
        _relockCandidateCount[jersey] =
            (_relockCandidateCount[jersey] ?? 0) + 1;
        if ((_relockCandidateCount[jersey] ?? 0) >= _relockConfirmationFrames) {
          // OCCUPANCY CHECK — before granting this new lock, make sure
          // the candidate position isn't already claimed by a different
          // locked player. This is what stops two jerseys from both
          // locking onto the same physical person.
          if (_isPositionOccupiedByOther(jersey, detectedBox)) {
            // Reset candidate tracking — don't lock here, keep searching
            _relockCandidateCount[jersey] = 0;
            _relockCandidatePos[jersey]   = null;
            return;
          }

          _lastKnownBoxes[jersey]        = detectedBox;
          _playerLockedPermanent[jersey] = true;
          _consecutiveDetections[jersey] = 0;
          _relockCandidateCount[jersey]  = 0;
          _relockCandidatePos[jersey]    = null;
          _framesSinceDetection[jersey]  = 0;
          _lockSource[jersey]            = source;
          _lockedAtTime[jersey]          = DateTime.now();
          onPlayerDetected?.call(jersey, detectedBox, source);
        }
      } else {
        _relockCandidateCount[jersey] = 1;
        _relockCandidatePos[jersey]   = detectedCentre;
      }
    } else {
      _relockCandidateCount[jersey] = 1;
      _relockCandidatePos[jersey]   = detectedCentre;
    }
  }

  /// Checks whether [candidateBox] significantly overlaps with any
  /// OTHER player's current locked box. Used to block a new lock from
  /// forming on top of an already-tracked person.
  bool _isPositionOccupiedByOther(String jersey, Rect candidateBox) {
    for (final other in _targetJerseys) {
      if (other == jersey) continue;
      if (_playerLockedPermanent[other] != true) continue;

      final otherBox = _lastKnownBoxes[other];
      if (otherBox == null) continue;

      final overlap = _overlapFraction(candidateBox, otherBox);
      if (overlap > _newLockOccupancyThreshold) return true;
    }
    return false;
  }

  void _assignPosesToPlayers(List<Pose> poses) {
    for (final pose in poses) {
      final leftHip  = pose.landmarks[PoseLandmarkType.leftHip];
      final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
      if (leftHip == null || rightHip == null) continue;

      final poseCentreX = (leftHip.x + rightHip.x) / 2;
      final poseCentreY = (leftHip.y + rightHip.y) / 2;

      String? matchedJersey;
      double  closestDistance = double.infinity;

      for (final jersey in _targetJerseys) {
        final box = _lastKnownBoxes[jersey];
        if (box == null) continue;
        if (box.contains(Offset(poseCentreX, poseCentreY))) {
          final cx   = box.left + box.width  / 2;
          final cy   = box.top  + box.height / 2;
          final dist = _squaredDistance(poseCentreX, poseCentreY, cx, cy);
          if (dist < closestDistance) {
            closestDistance = dist;
            matchedJersey   = jersey;
          }
        }
      }

      if (matchedJersey == null) {
        for (final jersey in _targetJerseys) {
          final box = _lastKnownBoxes[jersey];
          if (box == null) continue;
          final cx   = box.left + box.width  / 2;
          final cy   = box.top  + box.height / 2;
          final dist = _squaredDistance(poseCentreX, poseCentreY, cx, cy);
          if (dist < closestDistance) {
            closestDistance = dist;
            matchedJersey   = jersey;
          }
        }
      }

      if (matchedJersey == null) matchedJersey = _targetJerseys.first;

      // IMPORTANT: skip position updates for frozen players — this is
      // the proximity freeze in action. Their box stays exactly where
      // it was until the crossing resolves, preventing the skeleton
      // from jumping onto the wrong (overlapping) player.
      final frozen = _isFrozen[matchedJersey] ?? false;

      if (_playerLockedPermanent[matchedJersey] == true && !frozen) {
        final currentBox = _lastKnownBoxes[matchedJersey];
        if (currentBox != null) {
          final newBox = Rect.fromCenter(
            center: Offset(
                poseCentreX, poseCentreY - currentBox.height * 0.2),
            width:  currentBox.width,
            height: currentBox.height,
          );
          _lastKnownBoxes[matchedJersey]       = newBox;
          _framesSinceDetection[matchedJersey] = 0;
        }
      }
      // If frozen, we still record the pose for hit/block detection
      // (the player is still moving/playing) but don't let it move
      // the tracked box position.

      poseAnalysers[matchedJersey]?.addPose(pose);

      final keyPoints = [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
      ];
      final avgConf = keyPoints
          .map((t) => pose.landmarks[t]?.likelihood ?? 0.0)
          .reduce((a, b) => a + b) / keyPoints.length;

      onPoseUpdated?.call(
          pose.landmarks.values.toList(), avgConf, matchedJersey);
    }
  }

  Future<void> _runOCR(
      InputImage inputImage, Uint8List rawBytes, double imageWidth, double imageHeight) async {
    final recognised = await _textRecognizer.processImage(inputImage);

    for (final block in recognised.blocks) {
      final bb = block.boundingBox;

      final relativeY      = bb.top    / imageHeight;
      final relativeBottom = bb.bottom / imageHeight;

      if (relativeY < _minDetectionY) continue;
      if (relativeBottom > _maxDetectionY) continue;

      // DEBUG — prove the live slider value is actually being read here.
      // Remove once confirmed working.
      if (bb.width < _settings.minDetectionWidth) {
        debugPrint('OCR REJECTED "${block.text}" — width ${bb.width.toStringAsFixed(1)}px '
            '< current threshold ${_settings.minDetectionWidth.toStringAsFixed(1)}px');
        continue;
      }
      if (bb.width > _maxDetectionWidth) continue;

      String text = block.text
          .trim()
          .replaceAll(' ', '')
          .replaceAll('\n', '')
          .replaceAll('O', '0')
          .replaceAll('o', '0')
          .replaceAll('I', '1')
          .replaceAll('l', '1')
          .replaceAll('i', '1')
          .replaceAll('S', '5')
          .replaceAll('G', '6')
          .replaceAll('B', '8')
          .replaceAll('g', '9');

      for (final jersey in _targetJerseys) {
        final exactMatch      = text == jersey;
        final standaloneMatch =
            RegExp(r'(?<!\d)' + jersey + r'(?!\d)').hasMatch(text);

        if (!exactMatch && !standaloneMatch) continue;

        _consecutiveDetections[jersey] =
            (_consecutiveDetections[jersey] ?? 0) + 1;

        // Colour confidence boost — if this jersey's registered colour
        // also matches the region around the detected number, count it
        // as an extra confirmation. This lets a correct OCR read lock
        // faster when the colour agrees, without weakening the check
        // when colour data isn't available for this jersey.
        if (_colorMatcher.hasColors) {
          final expandedForColorCheck = Rect.fromCenter(
            center: Offset(bb.left + bb.width / 2, bb.top + bb.height * 6),
            width:  (bb.width  * 8).clamp(_frameW * 0.06, _frameW * 0.25),
            height: (bb.height * 20).clamp(_frameH * 0.25, _frameH * 0.80),
          );
          final colorMatches = await _colorMatcher.regionMatchesJerseyColor(
            rawBytes, imageWidth.toInt(), imageHeight.toInt(),
            jersey, expandedForColorCheck,
          );
          if (colorMatches) {
            _consecutiveDetections[jersey] =
                (_consecutiveDetections[jersey] ?? 0) + 1;
          }
        }

        if ((_consecutiveDetections[jersey] ?? 0) >= _settings.confirmationFrames) {
          final boxWidth  = (bb.width  * 8).clamp(_frameW * 0.06, _frameW * 0.25);
          final boxHeight = (bb.height * 20).clamp(_frameH * 0.25, _frameH * 0.80);

          final expanded = Rect.fromCenter(
            center: Offset(
              bb.left + bb.width  / 2,
              bb.top  + bb.height * 6,
            ),
            width:  boxWidth,
            height: boxHeight,
          );

          _tryLockPlayer(jersey, expanded, 'OCR');
        }
      }
    }
  }

  /// Scans the frame for regions matching any unlocked player's
  /// registered jersey colour. This is a weaker signal than OCR or
  /// photo matching (colour alone isn't unique) so it uses the normal
  /// candidate-confirmation flow in _tryLockPlayer, which already
  /// requires multiple consecutive stable detections before locking.
  Future<void> _runColorScan(CameraImage image) async {
    try {
      final regions = await _colorMatcher.findColorRegions(
        image.planes[0].bytes, image.width, image.height,
      );

      for (final entry in regions.entries) {
        final jersey = entry.key;
        if (_playerLockedPermanent[jersey] ?? false) continue;

        // Expand the raw colour blob into a sensible player-sized box
        final raw = entry.value;
        final expanded = Rect.fromCenter(
          center: raw.center,
          width:  (raw.width  * 2.5).clamp(_frameW * 0.06, _frameW * 0.25),
          height: (raw.height * 3.0).clamp(_frameH * 0.30, _frameH * 0.80),
        );

        _tryLockPlayer(jersey, expanded, 'COLOR');
      }
    } catch (_) {
      // Continue silently
    }
  }

  Future<void> _runPhotoMatch(CameraImage image) async {
    try {
      final bytes         = image.planes[0].bytes;
      final matchedJersey = await _photoMatcher.findMatchInFrame(
        bytes, image.width, image.height,
      );

      if (matchedJersey != null &&
          !(_playerLockedPermanent[matchedJersey] ?? false)) {
        final w   = image.width.toDouble();
        final h   = image.height.toDouble();
        final box = Rect.fromCenter(
          center: Offset(w / 2, h / 2),
          width:  w * 0.2,
          height: h * 0.5,
        );
        _tryLockPlayer(matchedJersey, box, 'PHOTO');
      }
    } catch (_) {
      // Continue silently
    }
  }

  InputImage? _buildInputImage(CameraImage image) {
    final camera = controller?.description;
    if (camera == null) return null;

    final rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    if (image.planes.isEmpty) return null;

    final plane = image.planes[0];
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  double _squaredDistance(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return dx * dx + dy * dy;
  }

  Future<void> stopCamera() async {
    await controller?.stopImageStream();
    await controller?.dispose();
    controller = null;
    for (final a in poseAnalysers.values) {
      a.reset();
    }
    poseAnalysers.clear();
    _photoMatcher.clear();
    _colorMatcher.clear();
    _consecutiveDetections.clear();
    _lastKnownBoxes.clear();
    _framesSinceDetection.clear();
    _playerLockedPermanent.clear();
    _relockCandidateCount.clear();
    _relockCandidatePos.clear();
    _lockSource.clear();
    _isFrozen.clear();
    _framesSinceAppearanceCheck.clear();
    _lockedAtTime.clear();
    _sustainedOverlapCounters.clear();
    _frameCount   = 0;
    _isProcessing = false;
  }

  Future<void> dispose() async {
    await stopCamera();
    await _poseDetector.close();
    await _textRecognizer.close();
  }
}
