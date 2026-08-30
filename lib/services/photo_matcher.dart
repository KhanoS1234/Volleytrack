import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Stores a perceptual fingerprint of a jersey number reference photo
class NumberFingerprint {
  final String jersey;
  final List<int> hash;
  final int avgBrightness;

  NumberFingerprint({
    required this.jersey,
    required this.hash,
    required this.avgBrightness,
  });
}

/// Matches live camera frames against stored reference photo fingerprints,
/// and re-verifies locked players still match their reference appearance.
class PhotoMatcher {
  static const double _matchThreshold = 0.35;
  // Slightly more lenient for re-verification since lighting/angle
  // changes more during play than during initial acquisition
  static const double _verifyThreshold = 0.45;

  final Map<String, List<NumberFingerprint>> _fingerprints = {};

  bool get hasFingerprints => _fingerprints.isNotEmpty;

  Future<void> registerPlayer(
      String jersey, List<String> photoPaths) async {
    if (photoPaths.isEmpty) return;

    final fingerprints = await compute(
      _processPhotos,
      _PhotoProcessInput(jersey: jersey, photoPaths: photoPaths),
    );

    _fingerprints[jersey] = fingerprints;
  }

  /// Check if a camera frame region matches any registered player
  /// Returns the jersey number if matched, null otherwise
  Future<String?> findMatchInFrame(
      Uint8List frameBytes, int width, int height) async {
    if (_fingerprints.isEmpty) return null;

    return compute(
      _matchFrame,
      _MatchInput(
        frameBytes:  frameBytes,
        width:       width,
        height:      height,
        fingerprints: _fingerprints,
        threshold:   _matchThreshold,
      ),
    );
  }

  /// Re-verify that a SPECIFIC known region (the locked player's current
  /// bounding box) still visually matches the given jersey's reference
  /// photos. Used to catch silent identity switches during tracking.
  ///
  /// Returns:
  ///   true  — region still matches this jersey's appearance
  ///   false — region no longer matches (likely identity switch)
  ///   null  — inconclusive (e.g. no fingerprints for this jersey,
  ///           or region too small/invalid) — caller should not act
  Future<bool?> verifyRegionMatches(
    Uint8List frameBytes,
    int width,
    int height,
    String jersey,
    Rect region,
  ) async {
    final fingerprints = _fingerprints[jersey];
    if (fingerprints == null || fingerprints.isEmpty) return null;

    return compute(
      _verifyRegion,
      _VerifyInput(
        frameBytes:   frameBytes,
        width:        width,
        height:       height,
        region:       region,
        fingerprints: fingerprints,
        threshold:    _verifyThreshold,
      ),
    );
  }

  void clear() => _fingerprints.clear();
}

// ─── Data classes for isolate communication ────────────────────────────────

class _PhotoProcessInput {
  final String jersey;
  final List<String> photoPaths;
  _PhotoProcessInput({required this.jersey, required this.photoPaths});
}

class _MatchInput {
  final Uint8List frameBytes;
  final int width;
  final int height;
  final Map<String, List<NumberFingerprint>> fingerprints;
  final double threshold;

  _MatchInput({
    required this.frameBytes,
    required this.width,
    required this.height,
    required this.fingerprints,
    required this.threshold,
  });
}

class _VerifyInput {
  final Uint8List frameBytes;
  final int width;
  final int height;
  final Rect region;
  final List<NumberFingerprint> fingerprints;
  final double threshold;

  _VerifyInput({
    required this.frameBytes,
    required this.width,
    required this.height,
    required this.region,
    required this.fingerprints,
    required this.threshold,
  });
}

// ─── Isolate functions ─────────────────────────────────────────────────────

List<NumberFingerprint> _processPhotos(_PhotoProcessInput input) {
  final fingerprints = <NumberFingerprint>[];

  for (final photoPath in input.photoPaths) {
    try {
      final file = File(photoPath);
      if (!file.existsSync()) continue;

      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) continue;

      final cropX = (image.width  * 0.30).toInt();
      final cropY = (image.height * 0.35).toInt();
      final cropW = (image.width  * 0.40).toInt();
      final cropH = (image.height * 0.30).toInt();

      final cropped = img.copyCrop(
        image, x: cropX, y: cropY, width: cropW, height: cropH,
      );

      final hash = _computePHash(cropped);
      final avg  = _computeAvgBrightness(cropped);

      fingerprints.add(NumberFingerprint(
        jersey: input.jersey, hash: hash, avgBrightness: avg,
      ));
    } catch (_) {
      // Skip failed photos
    }
  }

  return fingerprints;
}

String? _matchFrame(_MatchInput input) {
  try {
    final image = img.Image.fromBytes(
      width:  input.width,
      height: input.height,
      bytes:  input.frameBytes.buffer,
      order:  img.ChannelOrder.bgra,
    );

    const stepX  = 60;
    const stepY  = 60;
    const patchW = 120;
    const patchH = 80;

    final maxY = (image.height * 0.70).toInt();

    for (int y = 0; y < maxY - patchH; y += stepY) {
      for (int x = 0; x < image.width - patchW; x += stepX) {
        final patch = img.copyCrop(image, x: x, y: y, width: patchW, height: patchH);
        final patchHash = _computePHash(patch);

        for (final entry in input.fingerprints.entries) {
          for (final fp in entry.value) {
            final distance   = _hammingDistance(patchHash, fp.hash);
            final similarity = 1.0 - (distance / 64.0);

            if (similarity >= (1.0 - input.threshold)) {
              return entry.key;
            }
          }
        }
      }
    }
  } catch (_) {
    // Continue silently
  }

  return null;
}

/// Verify a specific known region against a specific jersey's fingerprints.
/// Unlike _matchFrame (which scans the whole frame looking for ANY match),
/// this checks ONE region against ONE player's known appearance.
bool? _verifyRegion(_VerifyInput input) {
  try {
    final image = img.Image.fromBytes(
      width:  input.width,
      height: input.height,
      bytes:  input.frameBytes.buffer,
      order:  img.ChannelOrder.bgra,
    );

    // Clamp region to valid image bounds
    final x = input.region.left.clamp(0, image.width - 1).toInt();
    final y = input.region.top.clamp(0, image.height - 1).toInt();
    final w = input.region.width.clamp(10, image.width - x).toInt();
    final h = input.region.height.clamp(10, image.height - y).toInt();

    if (w < 10 || h < 10) return null; // region too small to be meaningful

    // Focus on the upper-middle portion of the box (torso area, where
    // the jersey number/colour pattern is most distinctive) rather than
    // the whole body box which includes legs/floor
    final torsoY = y + (h * 0.1).toInt();
    final torsoH = (h * 0.5).clamp(10, image.height - torsoY).toInt();

    final region = img.copyCrop(image, x: x, y: torsoY, width: w, height: torsoH);
    final regionHash = _computePHash(region);

    // Compare against best matching fingerprint for this jersey
    double bestSimilarity = 0.0;
    for (final fp in input.fingerprints) {
      final distance   = _hammingDistance(regionHash, fp.hash);
      final similarity = 1.0 - (distance / 64.0);
      if (similarity > bestSimilarity) bestSimilarity = similarity;
    }

    return bestSimilarity >= (1.0 - input.threshold);
  } catch (_) {
    return null; // inconclusive on error — don't drop lock
  }
}

List<int> _computePHash(img.Image image) {
  final small = img.copyResize(image, width: 8, height: 8);

  final pixels = <double>[];
  for (int y = 0; y < 8; y++) {
    for (int x = 0; x < 8; x++) {
      final pixel = small.getPixel(x, y);
      final grey = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      pixels.add(grey);
    }
  }

  final avg = pixels.reduce((a, b) => a + b) / pixels.length;
  return pixels.map((p) => p > avg ? 1 : 0).toList();
}

int _hammingDistance(List<int> a, List<int> b) {
  if (a.length != b.length) return 64;
  int distance = 0;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) distance++;
  }
  return distance;
}

int _computeAvgBrightness(img.Image image) {
  double total = 0;
  int count    = 0;
  for (int y = 0; y < image.height; y += 4) {
    for (int x = 0; x < image.width; x += 4) {
      final pixel = image.getPixel(x, y);
      total += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      count++;
    }
  }
  return count > 0 ? (total / count).toInt() : 128;
}
