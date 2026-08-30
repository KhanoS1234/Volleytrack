import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:ui' show Rect, Size, Offset;
import 'pose_analyser.dart';
import 'photo_matcher.dart';
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
  final Map<String, PoseAnalyser> poseAnalysers = {};

  bool _isProcessing = false;
  List<String> _targetJerseys = [];
  int _frameCount = 0;

  static const int _ocrEveryNFrames    = 1;
  static const int _ocrAfterLockFrames = 45;
  static const int _photoEveryNFrames  = 5;
  static const int _confirmationFrames = 2;
  static const int _maxFramesWithoutDetection = 300;
  static const double _maxReacquisitionDistance = 200000.0;
  static const int _relockConfirmationFrames = 3;

  static const double _frameW = 1280.0;
  static const double _frameH = 720.0;

  static const double _minDetectionY = 0.15;
  static const double _maxDetectionY = 0.95;
  // NOTE: minDetectionWidth now comes from _settings (live adjustable)
  static const double _maxDetectionWidth = 250.0;

  final Map<String, int>     _consecutiveDetections = {};
  final Map<String, Rect?>   _lastKnownBoxes        = {};
  final Map<String, int>     _framesSinceDetection  = {};
  final Map<String, bool>    _playerLockedPermanent = {};
  final Map<String, int>     _relockCandidateCount  = {};
  final Map<String, Offset?> _relockCandidatePos    = {};

  Function(String jersey, Rect boundingBox)? onPlayerDetected;
  Function(String jersey)?                   onPlayerLost;
  Function(List<PoseLandmark> landmarks, double confidence, String jersey)?
      onPoseUpdated;

  Future<void> initialise() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) throw Exception('No cameras found');
  }

  Future<void> registerPlayerPhotos(
      String jersey, List<String> photoPaths) async {
    await _photoMatcher.registerPlayer(jersey, photoPaths);
  }

  Future<void> startCamera(List<String> targetJerseys) async {
    _targetJerseys = targetJerseys;

    for (final jersey in targetJerseys) {
      poseAnalysers[jersey]           = PoseAnalyser();
      _consecutiveDetections[jersey]  = 0;
      _lastKnownBoxes[jersey]         = null;
      _framesSinceDetection[jersey]   = 0;
      _playerLockedPermanent[jersey]  = false;
      _relockCandidateCount[jersey]   = 0;
      _relockCandidatePos[jersey]     = null;
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
    await controller!.startImageStream(_processFrame);
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;
    _frameCount++;

    for (final jersey in _targetJerseys) {
      _framesSinceDetection[jersey] =
          (_framesSinceDetection[jersey] ?? 0) + 1;
    }

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final poses = await _poseDetector.processImage(inputImage);
      _assignPosesToPlayers(poses);

      final anyLocked   = _playerLockedPermanent.values.any((v) => v);
      final ocrInterval = anyLocked ? _ocrAfterLockFrames : _ocrEveryNFrames;
      if (_frameCount % ocrInterval == 0) {
        await _runOCR(inputImage, image.width.toDouble(), image.height.toDouble());
      }

      final hasUnlocked = _playerLockedPermanent.values.any((v) => !v);
      if (hasUnlocked &&
          _photoMatcher.hasFingerprints &&
          _frameCount % _photoEveryNFrames == 0 &&
          image.planes.isNotEmpty) {
        await _runPhotoMatch(image);
      }

      for (final jersey in _targetJerseys) {
        final framesSince = _framesSinceDetection[jersey] ?? 0;
        final isLocked    = _playerLockedPermanent[jersey] ?? false;

        if (isLocked) {
          if (framesSince > _maxFramesWithoutDetection) {
            _playerLockedPermanent[jersey]  = false;
            _consecutiveDetections[jersey]  = 0;
            _relockCandidateCount[jersey]   = 0;
            _relockCandidatePos[jersey]     = null;
            onPlayerLost?.call(jersey);
          } else if (_lastKnownBoxes[jersey] != null) {
            onPlayerDetected?.call(jersey, _lastKnownBoxes[jersey]!);
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

  void _tryLockPlayer(String jersey, Rect detectedBox) {
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
          _lastKnownBoxes[jersey]        = detectedBox;
          _playerLockedPermanent[jersey] = true;
          _consecutiveDetections[jersey] = 0;
          _relockCandidateCount[jersey]  = 0;
          _relockCandidatePos[jersey]    = null;
          _framesSinceDetection[jersey]  = 0;
          onPlayerDetected?.call(jersey, detectedBox);
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

      if (_playerLockedPermanent[matchedJersey] == true) {
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
      InputImage inputImage, double imageWidth, double imageHeight) async {
    final recognised = await _textRecognizer.processImage(inputImage);

    for (final block in recognised.blocks) {
      final bb = block.boundingBox;

      final relativeY      = bb.top    / imageHeight;
      final relativeBottom = bb.bottom / imageHeight;

      if (relativeY < _minDetectionY) continue;
      if (relativeBottom > _maxDetectionY) continue;

      // Live-adjustable jersey number recognition sensitivity
      if (bb.width < _settings.minDetectionWidth) continue;
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

        if ((_consecutiveDetections[jersey] ?? 0) >= _confirmationFrames) {
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

          _tryLockPlayer(jersey, expanded);
        }
      }
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
        _tryLockPlayer(matchedJersey, box);
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
    _consecutiveDetections.clear();
    _lastKnownBoxes.clear();
    _framesSinceDetection.clear();
    _playerLockedPermanent.clear();
    _relockCandidateCount.clear();
    _relockCandidatePos.clear();
    _frameCount   = 0;
    _isProcessing = false;
  }

  Future<void> dispose() async {
    await stopCamera();
    await _poseDetector.close();
    await _textRecognizer.close();
  }
}
