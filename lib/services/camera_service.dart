import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:ui' show Rect, Size;
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

  // Use accurate mode for better recognition at distance
  // Accurate mode uses a more powerful model than fast mode
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  final PoseAnalyser poseAnalyser = PoseAnalyser();

  bool _isProcessing = false;
  String _targetJersey = '';
  int _frameCount = 0;

  // ── TUNING VARIABLES ──────────────────────────────────────────────────────
  // Run OCR every 5 frames instead of 10 for faster re-acquisition
  static const int _ocrEveryNFrames = 5;

  // How many consecutive frames a number must appear before confirming
  // Prevents false positives from partial number reads
  static const int _confirmationFrames = 2;

  // Tracks how many times we've seen the target number recently
  int _consecutiveDetections = 0;

  // Last known good bounding box — used to maintain tracking when OCR misses
  Rect? _lastKnownBox;
  int _framesSinceLastDetection = 0;
  static const int _maxFramesWithoutDetection = 30; // ~1 second at 30fps
  // ─────────────────────────────────────────────────────────────────────────

  Function(String jersey, Rect boundingBox)? onPlayerDetected;
  Function(List<PoseLandmark> landmarks, double confidence)? onPoseUpdated;
  Function()? onPlayerLost;

  Future<void> initialise() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) throw Exception('No cameras found on this device');
  }

  Future<void> startCamera(String targetJersey) async {
    _targetJersey = targetJersey;
    if (_cameras.isEmpty) await initialise();

    final backCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    controller = CameraController(
      backCamera,
      // Use veryHigh resolution for better number recognition at 12m distance
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await controller!.initialize();

    // Enable auto focus and auto exposure for mixed lighting conditions
    await controller!.setFocusMode(FocusMode.auto);
    await controller!.setExposureMode(ExposureMode.auto);

    await controller!.startImageStream(_processFrame);
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;
    _frameCount++;
    _framesSinceLastDetection++;

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      // Always run pose detection every frame
      final poses = await _poseDetector.processImage(inputImage);
      for (final pose in poses) {
        poseAnalyser.addPose(pose);

        final keyPoints = [
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.rightHip,
        ];
        final avgConfidence = keyPoints
            .map((t) => pose.landmarks[t]?.likelihood ?? 0.0)
            .reduce((a, b) => a + b) / keyPoints.length;

        onPoseUpdated?.call(pose.landmarks.values.toList(), avgConfidence);
      }

      // If player has been missing too long, notify lost
      if (_framesSinceLastDetection > _maxFramesWithoutDetection) {
        _consecutiveDetections = 0;
        onPlayerLost?.call();
      }

      // Run OCR every N frames
      if (_frameCount % _ocrEveryNFrames == 0) {
        await _runOCR(inputImage);
      }

    } catch (_) {
      // Continue silently on frame errors
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _runOCR(InputImage inputImage) async {
    final recognised = await _textRecognizer.processImage(inputImage);

    // Collect ALL candidate matches this frame
    // This handles cases where the number appears multiple times
    // or partial reads occur
    final List<_JerseyCandidate> candidates = [];

    for (final block in recognised.blocks) {
      // Clean the text — remove spaces, newlines, common OCR mistakes
      String text = block.text
          .trim()
          .replaceAll(' ', '')
          .replaceAll('\n', '')
          .replaceAll('O', '0')  // Common OCR mistake: O instead of 0
          .replaceAll('I', '1')  // Common OCR mistake: I instead of 1
          .replaceAll('l', '1'); // Common OCR mistake: l instead of 1

      // Accept 1-2 digit numbers only
      if (!RegExp(r'^\d{1,2}$').hasMatch(text)) continue;

      // Check exact match OR if the block contains our number
      // (handles partial reads when player is slightly turned)
      final bool exactMatch = text == _targetJersey;
      final bool containsMatch = block.text.contains(_targetJersey);

      if (!exactMatch && !containsMatch) continue;

      candidates.add(_JerseyCandidate(
        text: text,
        boundingBox: block.boundingBox,
        confidence: _estimateConfidence(block),
      ));
    }

    if (candidates.isEmpty) {
      // No detection this frame — keep last known box briefly
      if (_lastKnownBox != null &&
          _framesSinceLastDetection < _maxFramesWithoutDetection) {
        onPlayerDetected?.call(_targetJersey, _lastKnownBox!);
      }
      return;
    }

    // Pick the highest confidence candidate
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    final best = candidates.first;

    _consecutiveDetections++;
    _framesSinceLastDetection = 0;

    // Only confirm after seeing it N frames in a row
    // Prevents false positives from partial/blurry reads
    if (_consecutiveDetections >= _confirmationFrames) {
      final bb = best.boundingBox;

      // Expand bounding box to cover whole player body
      // At 12m the jersey number is small so we expand more aggressively
      final expanded = Rect.fromLTWH(
        bb.left  - bb.width  * 3,    // wider expansion for distance
        bb.top   - bb.height * 8,    // taller expansion to cover full body
        bb.width  * 7,
        bb.height * 18,
      );

      _lastKnownBox = expanded;
      onPlayerDetected?.call(_targetJersey, expanded);
    }
  }

  // Estimate OCR confidence based on text block properties
  double _estimateConfidence(_TextBlock block) {
    double confidence = 0.5;

    // Larger text = more confident (at 12m numbers will be small)
    final area = block.boundingBox.width * block.boundingBox.height;
    if (area > 2000) confidence += 0.3;
    else if (area > 500) confidence += 0.15;

    // More recognised elements = more confident
    if (block.lines.length == 1) confidence += 0.1;
    if (block.text.trim() == _targetJersey) confidence += 0.1;

    return confidence.clamp(0.0, 1.0);
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
    poseAnalyser.reset();
    _frameCount = 0;
    _framesSinceLastDetection = 0;
    _consecutiveDetections = 0;
    _lastKnownBox = null;
    _isProcessing = false;
  }

  Future<void> dispose() async {
    await stopCamera();
    await _poseDetector.close();
    await _textRecognizer.close();
  }
}

// Helper classes
class _JerseyCandidate {
  final String text;
  final Rect boundingBox;
  final double confidence;
  _JerseyCandidate({
    required this.text,
    required this.boundingBox,
    required this.confidence,
  });
}

// Alias to avoid import issues
typedef _TextBlock = TextBlock;
