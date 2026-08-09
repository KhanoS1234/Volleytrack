import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:ui' show Rect, Size, Offset;
import 'package:image/image.dart' as img;
import 'pose_analyser.dart';
import 'photo_matcher.dart';

class CameraService {
  CameraController? controller;
  List<CameraDescription> _cameras = [];

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

  // Upscaling adds processing cost, so OCR runs slightly less often
  static const int _ocrEveryNFrames    = 2;
  static const int _ocrAfterLockFrames = 45;
  static const int _photoEveryNFrames  = 5;
  static const int _confirmationFrames = 2;
  static const int _maxFramesWithoutDetection = 300;
  static const double _maxReacquisitionDistance = 200000.0;
  static const int _relockConfirmationFrames = 3;

  static const double _frameW = 1280.0;
  static const double _frameH = 720.0;

  static const double _minDetectionY     = 0.15;
  static const double _maxDetectionY     = 0.95;
  // Lower minimum since upscaling makes small numbers detectable
  static const double _minDetectionWidth = 6.0;
  static const double _maxDetectionWidth = 250.0;

  // 2x upscale makes a 15px number appear as 30px — much easier for OCR
  static const double _upscaleFactor = 2.0;

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
      // 1. Pose detection every frame — full resolution frame
      final fullInputImage = _buildInputImage(
        image.planes[0].bytes, image.width, image.height, image,
      );
      if (fullInputImage == null) return;

      final poses = await _poseDetector.processImage(fullInputImage);
      _assignPosesToPlayers(poses);

      // 2. OCR — upscale first, then run ML Kit on the larger image
      final anyLocked   = _playerLockedPermanent.values.any((v) => v);
      final ocrInterval = anyLocked ? _ocrAfterLockFrames : _ocrEveryNFrames;
      if (_frameCount % ocrInterval == 0) {
        await _runUpscaledOCR(image);
      }

      // 3. Photo matching for unlocked players
      final hasUnlocked = _playerLockedPermanent.values.any((v) => !v);
      if (hasUnlocked &&
          _photoMatcher.hasFingerprints &&
          _frameCount % _photoEveryNFrames == 0 &&
          image.planes.isNotEmpty) {
        await _runPhotoMatch(image);
      }

      // 4. Handle locked/lost state
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

  /// Upscales the frame in a background isolate (pure computation,
  /// no platform channels needed), then runs ML Kit OCR on the main
  /// thread using the upscaled bytes. This makes distant small jersey
  /// numbers appear larger and more readable.
  Future<void> _runUpscaledOCR(CameraImage image) async {
    try {
      // Step 1: Upscale in background isolate (safe - pure Dart)
      final upscaled = await compute(_upscaleFrame, _UpscaleInput(
        bytes:  image.planes[0].bytes,
        width:  image.width,
        height: image.height,
        scale:  _upscaleFactor,
      ));

      if (upscaled == null) return;

      // Step 2: Run ML Kit OCR on main thread with upscaled bytes
      final upscaledInputImage = InputImage.fromBytes(
        bytes: upscaled.bytes,
        metadata: InputImageMetadata(
          size: Size(upscaled.width.toDouble(), upscaled.height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(
                  controller?.description.sensorOrientation ?? 0) ??
              InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: upscaled.width * 4,
        ),
      );

      final recognised = await _textRecognizer.processImage(upscaledInputImage);
      _processOCRResults(recognised, image.width.toDouble(), image.height.toDouble());

    } catch (_) {
      // Continue silently — next frame will retry
    }
  }

  void _processOCRResults(
      RecognizedText recognised, double origWidth, double origHeight) {
    for (final block in recognised.blocks) {
      final bb = block.boundingBox;

      // Scale coordinates back down to original frame size
      final origLeft   = bb.left   / _upscaleFactor;
      final origTop    = bb.top    / _upscaleFactor;
      final origBWidth = bb.width  / _upscaleFactor;
      final origBHeight= bb.height / _upscaleFactor;

      final relativeY      = origTop / origHeight;
      final relativeBottom = (origTop + origBHeight) / origHeight;

      if (relativeY < _minDetectionY) continue;
      if (relativeBottom > _maxDetectionY) continue;
      if (origBWidth < _minDetectionWidth) continue;
      if (origBWidth > _maxDetectionWidth) continue;

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
          final boxWidth  = (origBWidth  * 8).clamp(_frameW * 0.06, _frameW * 0.25);
          final boxHeight = (origBHeight * 20).clamp(_frameH * 0.25, _frameH * 0.80);

          final expanded = Rect.fromCenter(
            center: Offset(
              origLeft + origBWidth  / 2,
              origTop  + origBHeight * 6,
            ),
            width:  boxWidth,
            height: boxHeight,
          );

          _tryLockPlayer(jersey, expanded);
        }
      }
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

  InputImage? _buildInputImage(
      Uint8List bytes, int width, int height, CameraImage image) {
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
        size: Size(width.toDouble(), height.toDouble()),
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

// ─── Upscaling isolate (pure computation, safe to run in background) ──────

class _UpscaleInput {
  final Uint8List bytes;
  final int width;
  final int height;
  final double scale;

  _UpscaleInput({
    required this.bytes,
    required this.width,
    required this.height,
    required this.scale,
  });
}

class _UpscaleResult {
  final Uint8List bytes;
  final int width;
  final int height;

  _UpscaleResult({
    required this.bytes,
    required this.width,
    required this.height,
  });
}

/// Runs in a background isolate — pure image processing, no platform
/// channels, so this is safe to run off the main thread.
_UpscaleResult? _upscaleFrame(_UpscaleInput input) {
  try {
    final image = img.Image.fromBytes(
      width:  input.width,
      height: input.height,
      bytes:  input.bytes.buffer,
      order:  img.ChannelOrder.bgra,
    );

    final newWidth  = (input.width  * input.scale).toInt();
    final newHeight = (input.height * input.scale).toInt();

    final upscaled = img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.cubic,
    );

    final bytes = upscaled.getBytes(order: img.ChannelOrder.bgra);

    return _UpscaleResult(
      bytes:  Uint8List.fromList(bytes),
      width:  newWidth,
      height: newHeight,
    );
  } catch (_) {
    return null;
  }
}
