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
    'jerseyR': jerseyColor.r, 'jerseyG': jerseyColor.g, 'jerseyB': jerseyColor.b,
    'numberR': numberColor.r, 'numberG': numberColor.g, 'numberB': numberColor.b,
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
}

class _ColorAnalysisInput {
  final Uint8List bytes;
  _ColorAnalysisInput({required this.bytes});
}

/// Runs in isolate — analyses the image to separate jersey fabric
/// colour from number/text colour using a clustering approach.
JerseyColors? _analyseColors(_ColorAnalysisInput input) {
  try {
    final image = img.decodeImage(input.bytes);
    if (image == null) return null;

    // Focus on the centre region — matches the "AIM HERE" guide box
    // shown during registration (roughly centre 35% x 25% of frame)
    final cropX = (image.width  * 0.325).toInt();
    final cropY = (image.height * 0.375).toInt();
    final cropW = (image.width  * 0.35).toInt();
    final cropH = (image.height * 0.25).toInt();

    final region = img.copyCrop(
      image, x: cropX, y: cropY, width: cropW, height: cropH,
    );

    // Collect all pixel colours and their luminance in this region
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

    if (samples.isEmpty) return null;

    // Sort by luminance to separate bright pixels (likely number/text)
    // from darker/mid-tone pixels (likely jersey fabric)
    samples.sort((a, b) => a.luminance.compareTo(b.luminance));

    // The jersey fabric is typically the majority colour (most common
    // luminance band), while the number is a minority high-contrast
    // colour (either much brighter or much darker than the fabric)

    // Take the middle 60% of samples by luminance as "fabric" —
    // excludes the very brightest and very darkest outliers which
    // are likely the number/text edges and shadows
    final fabricStart = (samples.length * 0.20).toInt();
    final fabricEnd   = (samples.length * 0.80).toInt();
    final fabricSamples = samples.sublist(fabricStart, fabricEnd);

    final jerseyColor = _averageColor(fabricSamples);

    // The number colour is likely at one of the luminance extremes —
    // check both the brightest 15% and darkest 15% and pick whichever
    // has the strongest contrast against the fabric colour
    final brightSamples = samples.sublist((samples.length * 0.85).toInt());
    final darkSamples   = samples.sublist(0, (samples.length * 0.15).toInt());

    final brightColor = _averageColor(brightSamples);
    final darkColor    = _averageColor(darkSamples);

    final contrastBright = _colorDistance(jerseyColor, brightColor);
    final contrastDark   = _colorDistance(jerseyColor, darkColor);

    final numberColor = contrastBright > contrastDark ? brightColor : darkColor;

    return JerseyColors(
      jerseyColor: Color.fromARGB(255, jerseyColor.$1, jerseyColor.$2, jerseyColor.$3),
      numberColor: Color.fromARGB(255, numberColor.$1, numberColor.$2, numberColor.$3),
    );
  } catch (_) {
    return null;
  }
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
