import 'dart:typed_data';
import 'dart:ui' show Color, Rect, Offset;
import 'package:flutter/foundation.dart';
import 'color_detector.dart';

/// Scans camera frames for regions matching a player's registered
/// jersey colour, used as a pre-filter and confidence booster
/// alongside OCR and photo matching.
class ColorMatcher {
  // How close a pixel's colour must be to the target jersey colour
  // to count as a match. Lower = stricter match required.
  static const double _colorTolerance = 4500.0; // squared RGB distance

  // Minimum contiguous region size (in sampled points) to count as
  // a real jersey-sized colour blob, not noise
  static const int _minRegionPoints = 40;

  final Map<String, JerseyColors> _playerColors = {};

  bool get hasColors => _playerColors.isNotEmpty;

  void registerPlayerColor(String jersey, JerseyColors? colors) {
    if (colors == null) return;
    _playerColors[jersey] = colors;
  }

  /// Scan a frame for regions matching any registered player's jersey
  /// colour. Returns a map of jersey -> best matching region found,
  /// for jerseys whose colour was detected with reasonable confidence.
  Future<Map<String, Rect>> findColorRegions(
      Uint8List frameBytes, int width, int height) async {
    if (_playerColors.isEmpty) return {};

    return compute(_scanForColors, _ColorScanInput(
      frameBytes: frameBytes,
      width: width,
      height: height,
      playerColors: _playerColors,
      tolerance: _colorTolerance,
      minRegionPoints: _minRegionPoints,
    ));
  }

  /// Quick check — does the given region's average colour match this
  /// jersey's registered colour? Used as a confidence booster when OCR
  /// finds a candidate number, to confirm it's on the right coloured jersey.
  Future<bool> regionMatchesJerseyColor(
    Uint8List frameBytes,
    int width,
    int height,
    String jersey,
    Rect region,
  ) async {
    final target = _playerColors[jersey];
    if (target == null) return true; // no color data — don't block the match

    return compute(_checkRegionColor, _RegionCheckInput(
      frameBytes: frameBytes,
      width: width,
      height: height,
      region: region,
      targetColor: target.jerseyColor,
      tolerance: _colorTolerance,
    ));
  }

  void clear() => _playerColors.clear();
}

// ─── Isolate data classes ───────────────────────────────────────────────

class _ColorScanInput {
  final Uint8List frameBytes;
  final int width;
  final int height;
  final Map<String, JerseyColors> playerColors;
  final double tolerance;
  final int minRegionPoints;

  _ColorScanInput({
    required this.frameBytes,
    required this.width,
    required this.height,
    required this.playerColors,
    required this.tolerance,
    required this.minRegionPoints,
  });
}

class _RegionCheckInput {
  final Uint8List frameBytes;
  final int width;
  final int height;
  final Rect region;
  final Color targetColor;
  final double tolerance;

  _RegionCheckInput({
    required this.frameBytes,
    required this.width,
    required this.height,
    required this.region,
    required this.targetColor,
    required this.tolerance,
  });
}

// ─── Isolate functions ─────────────────────────────────────────────────

/// Scans the whole frame in a grid, clustering pixels that match each
/// registered player's jersey colour, and returns the largest matching
/// region found per jersey.
Map<String, Rect> _scanForColors(_ColorScanInput input) {
  final Map<String, List<Offset>> matchPoints = {
    for (final jersey in input.playerColors.keys) jersey: []
  };

  const step = 8; // sample every 8th pixel for performance
  // BGRA format: 4 bytes per pixel
  final bytesPerPixel = 4;

  // Only scan the court area (skip top scoreboard/sign zone)
  final startY = (input.height * 0.15).toInt();
  final endY   = (input.height * 0.95).toInt();

  for (int y = startY; y < endY; y += step) {
    for (int x = 0; x < input.width; x += step) {
      final idx = (y * input.width + x) * bytesPerPixel;
      if (idx + 2 >= input.frameBytes.length) continue;

      final b = input.frameBytes[idx];
      final g = input.frameBytes[idx + 1];
      final r = input.frameBytes[idx + 2];

      for (final entry in input.playerColors.entries) {
        final target = entry.value.jerseyColor;
        final dist = _rgbDistance(
          r, g, b,
          target.red, target.green, target.blue,
        );

        if (dist < input.tolerance) {
          matchPoints[entry.key]!.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
  }

  // Build a bounding box from matched points per jersey
  final Map<String, Rect> results = {};
  for (final entry in matchPoints.entries) {
    if (entry.value.length < input.minRegionPoints) continue;

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;

    for (final p in entry.value) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }

    results[entry.key] = Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  return results;
}

/// Checks if the average colour in a specific region matches the
/// target jersey colour — used to boost confidence on an OCR candidate.
bool _checkRegionColor(_RegionCheckInput input) {
  const bytesPerPixel = 4;
  const step = 4;

  final x0 = input.region.left.clamp(0, input.width - 1).toInt();
  final y0 = input.region.top.clamp(0, input.height - 1).toInt();
  final x1 = input.region.right.clamp(0, input.width - 1).toInt();
  final y1 = input.region.bottom.clamp(0, input.height - 1).toInt();

  int rTotal = 0, gTotal = 0, bTotal = 0, count = 0;

  for (int y = y0; y < y1; y += step) {
    for (int x = x0; x < x1; x += step) {
      final idx = (y * input.width + x) * bytesPerPixel;
      if (idx + 2 >= input.frameBytes.length) continue;

      bTotal += input.frameBytes[idx];
      gTotal += input.frameBytes[idx + 1];
      rTotal += input.frameBytes[idx + 2];
      count++;
    }
  }

  if (count == 0) return true; // couldn't sample — don't block

  final avgR = rTotal ~/ count;
  final avgG = gTotal ~/ count;
  final avgB = bTotal ~/ count;

  final dist = _rgbDistance(
    avgR, avgG, avgB,
    input.targetColor.red, input.targetColor.green, input.targetColor.blue,
  );

  return dist < (input.tolerance * 1.5); // slightly more lenient for region avg
}

double _rgbDistance(int r1, int g1, int b1, int r2, int g2, int b2) {
  final dr = r1 - r2;
  final dg = g1 - g2;
  final db = b1 - b2;
  return (dr * dr + dg * dg + db * db).toDouble();
}
