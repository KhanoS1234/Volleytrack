import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Detected colours from a jersey reference photo
class JerseyColors {
  final Color jerseyColor;  // dominant fabric colour
  final Color numberColor;  // number/text colour

  JerseyColors({required this.jerseyColor, required this.numberColor});

  Map<String, dynamic> toMap() => {
    'jerseyR': jerseyColor.red, 'jerseyG': jerseyColor.green, 'jerseyB': jerseyColor.blue,
    'numberR': numberColor.red, 'numberG': numberColor.green, 'numberB': numberColor.blue,
  };

  factory JerseyColors.fromMap(Map<String, dynamic> map) => JerseyColors(
    jerseyColor: Color.fromARGB(255,
        (map['jerseyR'] as num).toInt(),
        (map['jerseyG'] as num).toInt(),
        (map['jerseyB'] as num).toInt()),
    numberColor: Color.fromARGB(255,
        (map['numberR'] as num).toInt(),
        (map['numberG'] as num).toInt(),
        (map['numberB'] as num).toInt()),
  );

  factory JerseyColors.defaultColors() => JerseyColors(
    jerseyColor: const Color(0xFF888888),
    numberColor: const Color(0xFFFFFFFF),
  );
}

/// Analyses a close-up jersey photo to automatically detect the
/// jersey fabric colour and the number/text colour.
class ColorDetector {
  /// Analyse the photo at [photoPath], sampling from the centre
  /// "AIM HERE" region where the registration screen guided the coach
  /// to position the jersey number.
  static Future<JerseyColors?> detectColors(String photoPath) async {
    try {
      final file = File(photoPath);
      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();
      return compute(_analyseColors, _ColorAnalysisInput(bytes: bytes));
    } catch (_) {
      return null;
    }
  }

  /// Analyse ALL registration photos together and combine the results
  /// into a single, more reliable colour reading. Each photo is taken
  /// at a different distance and often slightly different lighting/angle,
  /// so combining them evens out any one photo's quirks (glare, shadow,
  /// motion blur) rather than relying on a single shot.
  static Future<JerseyColors?> detectColorsFromMultiple(
      List<String> photoPaths) async {
    if (photoPaths.isEmpty) return null;

    final List<Uint8List> byteList = [];
    for (final path in photoPaths) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          byteList.add(await file.readAsBytes());
        }
      } catch (_) {
        // Skip unreadable photo, still use the others
      }
    }

    if (byteList.isEmpty) return null;

    return compute(_analyseMultiplePhotos, _MultiColorAnalysisInput(byteList: byteList));
  }
}

class _ColorAnalysisInput {
  final Uint8List bytes;
  _ColorAnalysisInput({required this.bytes});
}

class _MultiColorAnalysisInput {
  final List<Uint8List> byteList;
  _MultiColorAnalysisInput({required this.byteList});
}

/// Runs in isolate — analyses the image to separate jersey fabric
/// colour from number/text colour using a clustering approach.
JerseyColors? _analyseColors(_ColorAnalysisInput input) {
  final samples = _extractSamples(input.bytes);
  if (samples == null || samples.isEmpty) return null;
  return _classifyColors(samples);
}

/// Runs in isolate — combines pixel samples from ALL registration
/// photos into one pool, then classifies jersey vs number colour
/// from the combined data. This produces a more reliable result than
/// any single photo since it averages out per-photo lighting quirks.
JerseyColors? _analyseMultiplePhotos(_MultiColorAnalysisInput input) {
  final List<_PixelSample> allSamples = [];

  for (final bytes in input.byteList) {
    final samples = _extractSamples(bytes);
    if (samples != null) allSamples.addAll(samples);
  }

  if (allSamples.isEmpty) return null;
  return _classifyColors(allSamples);
}

/// Extracts raw pixel samples from the centre "AIM HERE" region of
/// a single photo. Shared by both single- and multi-photo analysis.
List<_PixelSample>? _extractSamples(Uint8List bytes) {
  try {
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    final cropX = (image.width  * 0.325).toInt();
    final cropY = (image.height * 0.375).toInt();
    final cropW = (image.width  * 0.35).toInt();
    final cropH = (image.height * 0.25).toInt();

    final region = img.copyCrop(
      image, x: cropX, y: cropY, width: cropW, height: cropH,
    );

    final List<_PixelSample> samples = [];
    for (int y = 0; y < region.height; y += 2) {
      for (int x = 0; x < region.width; x += 2) {
        final pixel = region.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
        samples.add(_PixelSample(r: r, g: g, b: b, luminance: luminance));
      }
    }
    return samples;
  } catch (_) {
    return null;
  }
}

/// Classifies a pool of pixel samples into jersey (fabric) colour and
/// number (text) colour based on luminance clustering.
JerseyColors _classifyColors(List<_PixelSample> samples) {
  final sorted = List<_PixelSample>.from(samples)
    ..sort((a, b) => a.luminance.compareTo(b.luminance));

  final fabricStart = (sorted.length * 0.20).toInt();
  final fabricEnd   = (sorted.length * 0.80).toInt();
  final fabricSamples = sorted.sublist(fabricStart, fabricEnd);

  final jerseyColor = _averageColor(fabricSamples);

  final brightSamples = sorted.sublist((sorted.length * 0.85).toInt());
  final darkSamples    = sorted.sublist(0, (sorted.length * 0.15).toInt());

  final brightColor = _averageColor(brightSamples);
  final darkColor    = _averageColor(darkSamples);

  final contrastBright = _colorDistance(jerseyColor, brightColor);
  final contrastDark   = _colorDistance(jerseyColor, darkColor);

  final numberColor = contrastBright > contrastDark ? brightColor : darkColor;

  return JerseyColors(
    jerseyColor: Color.fromARGB(255, jerseyColor.$1, jerseyColor.$2, jerseyColor.$3),
    numberColor: Color.fromARGB(255, numberColor.$1, numberColor.$2, numberColor.$3),
  );
}

class _PixelSample {
  final int r, g, b;
  final double luminance;
  _PixelSample({required this.r, required this.g, required this.b, required this.luminance});
}

(int, int, int) _averageColor(List<_PixelSample> samples) {
  if (samples.isEmpty) return (128, 128, 128);
  int r = 0, g = 0, b = 0;
  for (final s in samples) {
    r += s.r; g += s.g; b += s.b;
  }
  return (r ~/ samples.length, g ~/ samples.length, b ~/ samples.length);
}

double _colorDistance((int, int, int) a, (int, int, int) b) {
  final dr = a.$1 - b.$1;
  final dg = a.$2 - b.$2;
  final db = a.$3 - b.$3;
  return (dr * dr + dg * dg + db * db).toDouble();
}
