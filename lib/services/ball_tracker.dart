import 'dart:ui' show Rect, Offset;
import 'dart:math' as math;
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Tracks a volleyball using ML Kit Object Detection.
/// Uses the base model to find round objects and filters
/// by size and aspect ratio to find the ball.
class BallTracker {
  // ── TUNING VARIABLES ─────────────────────────────────────────────────────
  // Minimum size of ball bounding box as fraction of frame width
  static const double _minSizeFraction = 0.01;  // 1% of frame
  // Maximum size — prevents detecting players as ball
  static const double _maxSizeFraction = 0.25;  // 25% of frame
  // Circularity — width/height ratio must be close to 1.0 for a round ball
  static const double _minCircularity = 0.5;
  static const double _maxCircularity = 2.0;
  // Confidence threshold for object detection
  static const double _minConfidence = 0.5;
  // How close a wrist must be to ball centre (fraction of frame) to confirm hit
  static const double _hitProximityFraction = 0.12;
  // ─────────────────────────────────────────────────────────────────────────

  late final ObjectDetector _detector;
  bool _isInitialised = false;
  bool _isProcessing  = false;

  // Ball state
  Offset? ballPosition; // normalised 0.0-1.0
  double  ballRadius   = 0;
  bool    isTracking   = false;

  DateTime _lastDetected = DateTime(2000);
  static const Duration _lostTimeout = Duration(milliseconds: 1500);

  // Callbacks
  Function(Offset position, double radius)? onBallDetected;
  Function()? onBallLost;

  void initialise() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: false,
      multipleObjects: true,
    );
    _detector = ObjectDetector(options: options);
    _isInitialised = true;
  }

  Future<void> processImage(InputImage inputImage) async {
    if (!_isInitialised || _isProcessing) return;
    _isProcessing = true;

    try {
      final objects = await _detector.processImage(inputImage);

      DetectedObject? bestCandidate;
      double bestScore = 0;

      for (final obj in objects) {
        final bb = obj.boundingBox;

        // Filter by size
        final widthFraction  = bb.width  / 1280;
        final heightFraction = bb.height / 720;

        if (widthFraction  < _minSizeFraction || widthFraction  > _maxSizeFraction) continue;
        if (heightFraction < _minSizeFraction || heightFraction > _maxSizeFraction) continue;

        // Filter by circularity — ball should be roughly round
        final circularity = bb.width / (bb.height == 0 ? 1 : bb.height);
        if (circularity < _minCircularity || circularity > _maxCircularity) continue;

        // Score based on how round and small it is
        // Smaller = more likely to be ball than player
        final roundnessScore = 1.0 - (circularity - 1.0).abs();
        final sizeScore      = 1.0 - widthFraction;
        final totalScore     = roundnessScore * 0.6 + sizeScore * 0.4;

        if (totalScore > bestScore) {
          bestScore      = totalScore;
          bestCandidate  = obj;
        }
      }

      if (bestCandidate != null) {
        final bb = bestCandidate.boundingBox;

        // Convert to normalised position
        final centreX = (bb.left + bb.width  / 2) / 1280;
        final centreY = (bb.top  + bb.height / 2) / 720;
        final radius  = (bb.width + bb.height) / 4;

        ballPosition   = Offset(centreX, centreY);
        ballRadius     = radius;
        isTracking     = true;
        _lastDetected  = DateTime.now();

        onBallDetected?.call(ballPosition!, radius);

      } else {
        // Check if ball has been lost too long
        if (DateTime.now().difference(_lastDetected) > _lostTimeout) {
          if (isTracking) {
            isTracking   = false;
            ballPosition = null;
            onBallLost?.call();
          }
        }
      }

    } catch (_) {
      // Continue silently
    } finally {
      _isProcessing = false;
    }
  }

  /// Check if ball is near a wrist position
  /// wristX/Y are in image pixel coordinates (0-1280, 0-720)
  bool isBallNearWrist(double wristX, double wristY) {
    if (ballPosition == null) return false;

    final ballX = ballPosition!.dx * 1280;
    final ballY = ballPosition!.dy * 720;

    final distance = math.sqrt(
      math.pow(ballX - wristX, 2) +
      math.pow(ballY - wristY, 2),
    );

    // Threshold in pixels
    final threshold = _hitProximityFraction * 1280;
    return distance < threshold;
  }

  void reset() {
    isTracking   = false;
    ballPosition = null;
    ballRadius   = 0;
    _lastDetected = DateTime(2000);
  }

  Future<void> dispose() async {
    if (_isInitialised) {
      await _detector.close();
    }
  }
}
