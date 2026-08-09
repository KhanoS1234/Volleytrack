import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:ui' show Rect, Size, Offset;
import 'pose_analyser.dart';
import 'ball_tracker.dart';

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

  final BallTracker ballTracker = BallTracker();

  final Map<String, PoseAnalyser> poseAnalysers  = {};
  final Map<String, Pose?>        _latestPoses   = {};

  bool _isProcessing = false;
  List<String> _targetJerseys = [];
  int _frameCount = 0;
  static const int _ocrEveryNFrames  = 5;
  static const int _ballEveryNFrames = 2;
  static const int _confirmationFrames = 2;

  final Map<String, int>   _consecutiveDetections = {};
  final Map<String, Rect?> _lastKnownBoxes        = {};
  final Map<String, int>   _framesSinceDetection  = {};
  static const int _maxFramesWithoutDetection = 30;

  Function(String jersey, Rect boundingBox)? onPlayerDetected;
  Function(String jersey)?                   onPlayerLost;
  Function(List<PoseLandmark> landmarks, double confidence, String jersey)? onPoseUpdated;
  Function(Offset position, double radius)?  onBallDetected;
  Function()?                                onBallLost;
  Function(String jersey)?                   onBallHitConfirmed;

  Future<void> initialise() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) throw Exception('No cameras found');
    ballTracker.initialise();
  }

  Future<void> startCamera(List<String> targetJerseys) async {
    _targetJerseys = targetJerseys;

    for (final jersey in targetJerseys) {
      poseAnalysers[jersey]          = PoseAnalyser();
      _consecutiveDetections[jersey] = 0;
      _lastKnownBoxes[jersey]        = null;
      _framesSinceDetection[jersey]  = 0;
      _latestPoses[jersey]           = null;
    }

    ballTracker.onBallDetected = (pos, radius) {
      onBallDetected?.call(pos, radius);
      _checkBallHitProximity();
    };
    ballTracker.onBallLost = () => onBallLost?.call();

    if (_cameras.isEmpty) await initialise();

    final backCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
      // Use bgra8888 for iOS
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

      // 2. Ball detection every 2 frames
     //if (_frameCount % _ballEveryNFrames == 0) {
       // await ballTracker.processImage(inputImage);
      //}

      // 3. OCR every N frames
      if (_frameCount % _ocrEveryNFrames == 0) {
        await _runOCR(inputImage);
      }

      // Check lost players
      for (final jersey in _targetJerseys) {
        if ((_framesSinceDetection[jersey] ?? 0) > _maxFramesWithoutDetection) {
          _consecutiveDetections[jersey] = 0;
          onPlayerLost?.call(jersey);
        } else if (_lastKnownBoxes[jersey] != null) {
          onPlayerDetected?.call(jersey, _lastKnownBoxes[jersey]!);
        }
      }

    } catch (_) {
      // Continue silently
    } finally {
      _isProcessing = false;
    }
  }

  void _checkBallHitProximity() {
    if (!ballTracker.isTracking) return;

    for (final jersey in _targetJerseys) {
      final pose = _latestPoses[jersey];
      if (pose == null) continue;

      final rw = pose.landmarks[PoseLandmarkType.rightWrist];
      final lw = pose.landmarks[PoseLandmarkType.leftWrist];

      if (rw != null && rw.likelihood > 0.5) {
        if (ballTracker.isBallNearWrist(rw.x, rw.y)) {
          onBallHitConfirmed?.call(jersey);
          return;
        }
      }
      if (lw != null && lw.likelihood > 0.5) {
        if (ballTracker.isBallNearWrist(lw.x, lw.y)) {
          onBallHitConfirmed?.call(jersey);
          return;
        }
      }
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
          final dist = _dist(poseCentreX, poseCentreY, cx, cy);
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
          final dist = _dist(poseCentreX, poseCentreY, cx, cy);
          if (dist < closestDistance) {
            closestDistance = dist;
            matchedJersey   = jersey;
          }
        }
      }

      if (matchedJersey == null) matchedJersey = _targetJerseys.first;

      _latestPoses[matchedJersey] = pose;
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

  double _dist(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return dx * dx + dy * dy;
  }

  Future<void> _runOCR(InputImage inputImage) async {
    final recognised = await _textRecognizer.processImage(inputImage);

    for (final block in recognised.blocks) {
      String text = block.text
          .trim()
          .replaceAll(' ', '')
          .replaceAll('\n', '')
          .replaceAll('O', '0')
          .replaceAll('I', '1')
          .replaceAll('l', '1');

      if (!RegExp(r'^\d{1,2}$').hasMatch(text)) continue;

      for (final jersey in _targetJerseys) {
        if (text != jersey && !block.text.contains(jersey)) continue;

        _consecutiveDetections[jersey] = (_consecutiveDetections[jersey] ?? 0) + 1;
        _framesSinceDetection[jersey]  = 0;

        if ((_consecutiveDetections[jersey] ?? 0) >= _confirmationFrames) {
          final bb = block.boundingBox;
          final expanded = Rect.fromLTWH(
            bb.left  - bb.width  * 3,
            bb.top   - bb.height * 8,
            bb.width  * 7,
            bb.height * 18,
          );
          _lastKnownBoxes[jersey] = expanded;
          onPlayerDetected?.call(jersey, expanded);
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

  Future<void> stopCamera() async {
    await controller?.stopImageStream();
    await controller?.dispose();
    controller = null;
    for (final a in poseAnalysers.values) a.reset();
    poseAnalysers.clear();
    ballTracker.reset();
    _consecutiveDetections.clear();
    _lastKnownBoxes.clear();
    _framesSinceDetection.clear();
    _latestPoses.clear();
    _frameCount   = 0;
    _isProcessing = false;
  }

  Future<void> dispose() async {
    await stopCamera();
    await _poseDetector.close();
    await _textRecognizer.close();
    await ballTracker.dispose();
  }
}
