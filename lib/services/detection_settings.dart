import 'package:flutter/foundation.dart';

/// Holds the live-adjustable values for jersey number recognition,
/// used during on-court testing.
/// Remove this once optimal values have been found and hardcoded.
class DetectionSettings extends ChangeNotifier {
  static final DetectionSettings _instance = DetectionSettings._internal();
  factory DetectionSettings() => _instance;
  DetectionSettings._internal();

  // ── SENSITIVITY (distance) ──────────────────────────────────────────
  // Minimum pixel width for a detected number to be considered valid.
  // LOWER = picks up smaller/more distant numbers, more false positives.
  // HIGHER = only accepts larger/closer numbers, more reliable but
  //   misses distant players.
  double minDetectionWidth = 8.0;
  static const double minWidthAllowed = 2.0;
  static const double maxWidthAllowed = 40.0;

  // ── LOCK CONFIDENCE (false positive prevention) ─────────────────────
  // Number of consecutive matching detections required before the app
  // trusts a lock onto a player.
  // LOWER = locks on faster, more prone to false positives from a
  //   single lucky misread (e.g. a sign briefly matching the number).
  // HIGHER = requires the same number to be read multiple times in a
  //   row before locking, much more reliable but slower to lock on.
  int confirmationFrames = 2;
  static const int minConfirmationAllowed = 1;
  static const int maxConfirmationAllowed = 10;

  void setMinDetectionWidth(double value) {
    minDetectionWidth = value.clamp(minWidthAllowed, maxWidthAllowed);
    notifyListeners();
  }

  void setConfirmationFrames(int value) {
    confirmationFrames =
        value.clamp(minConfirmationAllowed, maxConfirmationAllowed);
    notifyListeners();
  }

  void reset() {
    minDetectionWidth  = 8.0;
    confirmationFrames = 2;
    notifyListeners();
  }
}
