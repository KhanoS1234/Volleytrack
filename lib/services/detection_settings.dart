import 'package:flutter/foundation.dart';

/// Holds the single live-adjustable value for jersey number recognition
/// sensitivity, used during on-court testing.
/// Remove this once an optimal value has been found and hardcoded.
class DetectionSettings extends ChangeNotifier {
  static final DetectionSettings _instance = DetectionSettings._internal();
  factory DetectionSettings() => _instance;
  DetectionSettings._internal();

  // Minimum pixel width for a detected number to be considered valid.
  // LOWER value = picks up smaller/more distant numbers, but more
  //   prone to false positives from signs, scoreboards etc.
  // HIGHER value = only accepts larger/closer numbers, more reliable
  //   but will miss distant players.
  //
  // Default 8.0 is a starting middle-ground.
  double minDetectionWidth = 8.0;

  static const double minAllowed = 2.0;
  static const double maxAllowed = 40.0;

  void setMinDetectionWidth(double value) {
    minDetectionWidth = value.clamp(minAllowed, maxAllowed);
    notifyListeners();
  }

  void reset() {
    minDetectionWidth = 8.0;
    notifyListeners();
  }
}
