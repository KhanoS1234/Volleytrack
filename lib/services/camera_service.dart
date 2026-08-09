import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:ui' show Rect, Size, Offset;
import 'pose_analyser.dart';

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

  final Map<String, PoseAnalyser> poseAnalysers = {};

  bool _isProcessing = false;
  List<String> _targetJerseys = [];
  int _frameCount = 0;

  // Scan every frame until locked, then slow down
  static const int _ocrEveryNFrames    = 1;
  static const int _ocrAfterLockFrames = 30;
  static const int _confirmationFrames = 1;
  // 150 frames = ~5 seconds at 30fps
  static const int _maxFramesWithoutDetection = 150;

  final Map<String, int>   _consecutiveDetections = {};
  final Map<String, Rect?> _lastKnownBoxes        = {};
  final Map<String, int>   _framesSinceDetection  = {};
  final Map<String, bool>  _playerLockedPermanent = {};

  Function(String jersey, Rect boundingBox)? onPlayerDetected;
  Function(String jersey)?                   onPlayerLost;
  Function(List<PoseLandmark> landmarks, double confidence, String jersey)? onPoseUpdated;

  Future<void> initialise() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) throw Exception('No cameras found');
  }

  Future<void> startCamera(List<String> targetJerseys) async {
    _targetJerseys = targetJerseys;

    for (final jersey in targetJerseys) {
      poseAnalysers[jersey]           = PoseAnalyser();
      _consecutiveDetections[jersey]  = 0;
      _lastKnownBoxes[jersey]         = null;
      _framesSinceDetection[jersey]   = 0;
      _playerLockedPermanent[jersey]  = false;
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
      _framesSinceDetection[jersey] = (_framesSinceDetection[jersey] ?? 0) + 1;
    }

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      // 1. Pose detection every frame
      final poses = await _poseDetector.processImage(inputImage);
      _assignPosesToPlayers(poses);

      // 2. OCR — every frame until locked, then every 30 frames
      final anyLocked   = _playerLockedPermanent.values.any((v) => v);
      final ocrInterval = anyLocked ? _ocrAfterLockFrames : _ocrEveryNFrames;
      if (_frameCount % ocrInterval == 0) {
        await _runOCR(inputImage);
      }

      // 3. Check lost players
      for (final jersey in _targetJerseys) {
        final framesSince = _framesSinceDetection[jersey] ?? 0;
        final isLocked    = _playerLockedPermanent[jersey] ?? false;

        if (isLocked) {
          if (framesSince > _maxFramesWithoutDetection) {
            _playerLockedPermanent[jersey] = false;
            _consecutiveDetections[jersey] = 0;
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
      // Continue silently on frame errors
    } finally {
      _isProcessing = false;
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

      // When locked, update box position to follow skeleton hips
      if (_playerLockedPermanent[matchedJersey] == true) {
        final currentBox = _lastKnownBoxes[matchedJersey];
        if (currentBox != null) {
          final newBox = Rect.fromCenter(
            center: Offset(poseCentreX, poseCentreY - currentBox.height * 0.2),
            width:  currentBox.width,
            height: currentBox.height,
          );
          _lastKnownBoxes[matchedJersey] = newBox;
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

      onPoseUpdated?.call(pose.landmarks.values.toList(), avgConf, matchedJersey);
    }
  }

  Future<void> _runOCR(InputImage inputImage) async {
    final recognised = await _textRecognizer.processImage(inputImage);

    for (final block in recognised.blocks) {
      // Clean common OCR mistakes
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

      // Extract ALL 1-2 digit numbers from the text block
      // This handles OCR reading "WATSON42" and still finding "42"
      // It also handles the name being read alongside the number
      final digitMatches = RegExp(r'\d{1,2}').allMatches(text);
      if (digitMatches.isEmpty) continue;

      for (final match in digitMatches) {
        final number = match.group(0)!;

        for (final jersey in _targetJerseys) {
          if (number != jersey) continue;

          _consecutiveDetections[jersey] = (_consecutiveDetections[jersey] ?? 0) + 1;
          _framesSinceDetection[jersey]  = 0;

          if ((_consecutiveDetections[jersey] ?? 0) >= _confirmationFrames) {
            final bb = block.boundingBox;
            final expanded = Rect.fromLTWH(
              bb.left  - bb.width  * 6,
              bb.top   - bb.height * 12,
              bb.width  * 13,
              bb.height * 28,
            );
            _lastKnownBoxes[jersey]        = expanded;
            _playerLockedPermanent[jersey] = true;
            onPlayerDetected?.call(jersey, expanded);
          }
        }
      }
    }
  }

  InputImage? _buildInputImage(CameraImage image) {
    final camera = controller?.description;
    if (camera == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation)
        ?? InputImageRotation.rotation0deg;

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
    for (final a in poseAnalysers.values) a.reset();
    poseAnalysers.clear();
    _consecutiveDetections.clear();
    _lastKnownBoxes.clear();
    _framesSinceDetection.clear();
    _playerLockedPermanent.clear();
    _frameCount   = 0;
    _isProcessing = false;
  }

  Future<void> dispose() async {
    await stopCamera();
    await _poseDetector.close();
    await _textRecognizer.close();
  }
}
