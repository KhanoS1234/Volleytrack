import 'dart:ui' show Rect, Offset;
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Tracks a volleyball using colour and circular shape detection.
/// Works by scanning camera frames for round objects matching
/// typical volleyball colour ranges (white, yellow, blue panels).
class BallTracker {
  // ── TUNING VARIABLES ─────────────────────────────────────────────────────
  // Minimum radius of ball in pixels — increase if detecting small false objects
  static const double _minRadius = 8.0;
  // Maximum radius — prevents detecting large white areas as ball
  static const double _maxRadius = 80.0;
  // How many frames ball must appear before confirming detection
  static const int _confirmFrames = 2;
  // Seconds before ball is considered lost
  static const double _lostSeconds = 1.5;
  // How close (pixels) a player's wrist must be to ball to confirm a hit
  static const double _hitProximityThreshold = 120.0;
  // ─────────────────────────────────────────────────────────────────────────

  int _confirmCount = 0;
  Offset? _lastBallPosition;
  DateTime _lastDetected = DateTime(2000);
  bool _ballVisible = false;

  // Ball position in normalised coords (0.0 - 1.0)
  Offset? ballPosition;
  double ballRadius = 0;

  // Callbacks
  Function(Offset position, double radius)? onBallDetected;
  Function()? onBallLost;

  // Called when ball is near a player wrist — confirms a hit
  Function(String jersey)? onHitConfirmed;

  bool get isTracking => _ballVisible;

  /// Process a camera frame to find the ball.
  /// Takes raw NV21 bytes and image dimensions.
  Future<void> processFrame(
    Uint8List bytes,
    int width,
    int height,
    double screenWidth,
    double screenHeight,
  ) async {
    // Run detection in isolate to avoid blocking main thread
    final result = await compute(
      _detectBallInFrame,
      _BallDetectionInput(
        bytes: bytes,
        width: width,
        height: height,
        minRadius: _minRadius,
        maxRadius: _maxRadius,
      ),
    );

    if (result != null) {
      _confirmCount++;
      _lastDetected = DateTime.now();

      if (_confirmCount >= _confirmFrames) {
        _ballVisible = true;

        // Convert from image coords to normalised coords
        ballPosition = Offset(
          result.x / width,
          result.y / height,
        );
        ballRadius = result.radius;

        onBallDetected?.call(ballPosition!, ballRadius);
      }
    } else {
      // Check if ball is lost
      final elapsed = DateTime.now().difference(_lastDetected).inMilliseconds;
      if (elapsed > (_lostSeconds * 1000)) {
        if (_ballVisible) {
          _ballVisible = false;
          _confirmCount = 0;
          ballPosition = null;
          onBallLost?.call();
        }
      }
    }
  }

  /// Check if ball is near a player's wrist position
  /// wristX/Y are in image pixel coordinates
  bool isBallNearWrist(double wristX, double wristY, int imageWidth, int imageHeight) {
    if (ballPosition == null) return false;

    final ballX = ballPosition!.dx * imageWidth;
    final ballY = ballPosition!.dy * imageHeight;

    final distance = math.sqrt(
      math.pow(ballX - wristX, 2) + math.pow(ballY - wristY, 2),
    );

    return distance < _hitProximityThreshold;
  }

  void reset() {
    _confirmCount = 0;
    _lastBallPosition = null;
    _ballVisible = false;
    ballPosition = null;
    ballRadius = 0;
  }
}

/// Data class for passing to isolate
class _BallDetectionInput {
  final Uint8List bytes;
  final int width;
  final int height;
  final double minRadius;
  final double maxRadius;

  _BallDetectionInput({
    required this.bytes,
    required this.width,
    required this.height,
    required this.minRadius,
    required this.maxRadius,
  });
}

/// Result from ball detection
class _BallDetectionResult {
  final double x;
  final double y;
  final double radius;
  _BallDetectionResult(this.x, this.y, this.radius);
}

/// Run in isolate — scans frame for circular objects matching volleyball colours
_BallDetectionResult? _detectBallInFrame(_BallDetectionInput input) {
  try {
    final bytes = input.bytes;
    final width  = input.width;
    final height = input.height;

    // Sample every 4th pixel for performance
    const step = 4;

    // Accumulate candidate bright/white regions
    final List<_Candidate> candidates = [];

    for (int y = 0; y < height; y += step) {
      for (int x = 0; x < width; x += step) {
        final idx = y * width + x;
        if (idx >= bytes.length) continue;

        // NV21 format: Y plane is luminance (brightness)
        final luminance = bytes[idx];

        // Look for bright objects (white/yellow volleyball)
        // Luminance > 180 = bright white/yellow
        if (luminance > 180) {
          candidates.add(_Candidate(x.toDouble(), y.toDouble(), luminance));
        }
      }
    }

    if (candidates.isEmpty) return null;

    // Cluster nearby bright pixels into regions
    final clusters = _clusterCandidates(candidates, 30.0);

    // Find the most circular cluster of volleyball-like size
    for (final cluster in clusters) {
      final radius = cluster.estimatedRadius;
      if (radius < input.minRadius || radius > input.maxRadius) continue;

      // Check circularity — width/height ratio should be close to 1.0
      final circularity = cluster.width / (cluster.height == 0 ? 1 : cluster.height);
      if (circularity < 0.5 || circularity > 2.0) continue;

      return _BallDetectionResult(cluster.centreX, cluster.centreY, radius);
    }

    return null;
  } catch (_) {
    return null;
  }
}

class _Candidate {
  final double x, y;
  final int brightness;
  _Candidate(this.x, this.y, this.brightness);
}

class _Cluster {
  final List<_Candidate> points;

  _Cluster(this.points);

  double get centreX => points.map((p) => p.x).reduce((a, b) => a + b) / points.length;
  double get centreY => points.map((p) => p.y).reduce((a, b) => a + b) / points.length;

  double get minX => points.map((p) => p.x).reduce(math.min);
  double get maxX => points.map((p) => p.x).reduce(math.max);
  double get minY => points.map((p) => p.y).reduce(math.min);
  double get maxY => points.map((p) => p.y).reduce(math.max);

  double get width  => maxX - minX;
  double get height => maxY - minY;

  double get estimatedRadius => (width + height) / 4;
}

List<_Cluster> _clusterCandidates(List<_Candidate> candidates, double threshold) {
  final List<_Cluster> clusters = [];
  final used = List<bool>.filled(candidates.length, false);

  for (int i = 0; i < candidates.length; i++) {
    if (used[i]) continue;

    final group = [candidates[i]];
    used[i] = true;

    for (int j = i + 1; j < candidates.length; j++) {
      if (used[j]) continue;
      final dx = candidates[i].x - candidates[j].x;
      final dy = candidates[i].y - candidates[j].y;
      if (math.sqrt(dx * dx + dy * dy) < threshold) {
        group.add(candidates[j]);
        used[j] = true;
      }
    }

    if (group.length >= 3) {
      clusters.add(_Cluster(group));
    }
  }

  // Sort by cluster size — largest first
  clusters.sort((a, b) => b.points.length.compareTo(a.points.length));
  return clusters.take(5).toList();
}
