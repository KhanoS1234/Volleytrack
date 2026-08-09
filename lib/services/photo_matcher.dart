import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Stores a perceptual fingerprint of a jersey number reference photo
class NumberFingerprint {
  final String jersey;
  final List<int> hash; // 64-bit perceptual hash
  final int avgBrightness;

  NumberFingerprint({
    required this.jersey,
    required this.hash,
    required this.avgBrightness,
  });
}

/// Matches live camera frames against stored reference photo fingerprints
class PhotoMatcher {
  // Similarity threshold — lower = stricter match, higher = more lenient
  // Range 0.0 (identical) to 1.0 (completely different)
  static const double _matchThreshold = 0.35;

  // Stored fingerprints per jersey number (3 per player)
  final Map<String, List<NumberFingerprint>> _fingerprints = {};

  bool get hasFingerprints => _fingerprints.isNotEmpty;

  /// Load and process reference photos for a player
  /// Call this once when session starts
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
  Future<String?> findMatchInFrame(Uint8List frameBytes, int width, int height) async {
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

// ─── Isolate functions ─────────────────────────────────────────────────────

/// Process reference photos into fingerprints (runs in isolate)
List<NumberFingerprint> _processPhotos(_PhotoProcessInput input) {
  final fingerprints = <NumberFingerprint>[];

  for (final photoPath in input.photoPaths) {
    try {
      final file  = File(photoPath);
      if (!file.existsSync()) continue;

      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) continue;

      // Crop the centre region — this is where the number was aimed
      // The aim box is roughly the centre 40% of the image
      final cropX = (image.width  * 0.30).toInt();
      final cropY = (image.height * 0.35).toInt();
      final cropW = (image.width  * 0.40).toInt();
      final cropH = (image.height * 0.30).toInt();

      final cropped = img.copyCrop(
        image,
        x: cropX, y: cropY,
        width: cropW, height: cropH,
      );

      // Compute perceptual hash
      final hash = _computePHash(cropped);
      final avg  = _computeAvgBrightness(cropped);

      fingerprints.add(NumberFingerprint(
        jersey:        input.jersey,
        hash:          hash,
        avgBrightness: avg,
      ));
    } catch (_) {
      // Skip failed photos
    }
  }

  return fingerprints;
}

/// Scan frame for regions matching any registered fingerprint
String? _matchFrame(_MatchInput input) {
  try {
    // Decode the BGRA frame bytes into an image
    final image = img.Image.fromBytes(
      width:  input.width,
      height: input.height,
      bytes:  input.frameBytes.buffer,
      order:  img.ChannelOrder.bgra,
    );

    // Scan the frame in a grid
    // Focus on the upper 2/3 of the frame (where players' torsos are)
    const stepX     = 60;  // scan every 60px horizontally
    const stepY     = 60;  // scan every 60px vertically
    const patchW    = 120; // patch width
    const patchH    = 80;  // patch height

    final maxY = (image.height * 0.70).toInt();

    for (int y = 0; y < maxY - patchH; y += stepY) {
      for (int x = 0; x < image.width - patchW; x += stepX) {
        final patch = img.copyCrop(
          image,
          x: x, y: y, width: patchW, height: patchH,
        );

        final patchHash = _computePHash(patch);

        // Compare against all registered fingerprints
        for (final entry in input.fingerprints.entries) {
          for (final fp in entry.value) {
            final distance = _hammingDistance(patchHash, fp.hash);
            final similarity = 1.0 - (distance / 64.0);

            if (similarity >= (1.0 - input.threshold)) {
              return entry.key; // jersey number matched
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

/// Compute a 64-bit perceptual hash (pHash) of an image
/// This creates a fingerprint that is similar for visually similar images
List<int> _computePHash(img.Image image) {
  // Resize to 8x8 for the hash
  final small = img.copyResize(image, width: 8, height: 8);

  // Convert to greyscale values
  final pixels = <double>[];
  for (int y = 0; y < 8; y++) {
    for (int x = 0; x < 8; x++) {
      final pixel = small.getPixel(x, y);
      // Luminance formula
      final grey = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      pixels.add(grey);
    }
  }

  // Average pixel value
  final avg = pixels.reduce((a, b) => a + b) / pixels.length;

  // Build hash — 1 if pixel > average, 0 if not
  return pixels.map((p) => p > avg ? 1 : 0).toList();
}

/// Calculate Hamming distance between two hashes
/// 0 = identical, 64 = completely different
int _hammingDistance(List<int> a, List<int> b) {
  if (a.length != b.length) return 64;
  int distance = 0;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) distance++;
  }
  return distance;
}

/// Calculate average brightness of an image (0-255)
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
