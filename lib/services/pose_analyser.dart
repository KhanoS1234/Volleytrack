import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseAnalyser {
  static const int _windowSize = 15;
  static const double _cooldownSeconds = 1.2;

  final List<Pose> _history = [];
  DateTime _lastHit   = DateTime(2000);
  DateTime _lastBlock = DateTime(2000);

  Function()? onHitDetected;
  Function()? onBlockDetected;

  void addPose(Pose pose) {
    _history.add(pose);
    if (_history.length > _windowSize) _history.removeAt(0);
    if (_history.length == _windowSize) _classify();
  }

  void _classify() {
    final now = DateTime.now();
    if (now.difference(_lastHit).inMilliseconds > (_cooldownSeconds * 1000).toInt()) {
      if (_detectSpike()) {
        _lastHit = now;
        onHitDetected?.call();
      }
    }
    if (now.difference(_lastBlock).inMilliseconds > (_cooldownSeconds * 1000).toInt()) {
      if (_detectBlock()) {
        _lastBlock = now;
        onBlockDetected?.call();
      }
    }
  }

  bool _detectSpike() {
    double? wristY(Pose p) {
      final rw = p.landmarks[PoseLandmarkType.rightWrist];
      final lw = p.landmarks[PoseLandmarkType.leftWrist];
      if (rw == null && lw == null) return null;
      if (rw == null) return lw!.y;
      if (lw == null) return rw.y;
      return rw.likelihood > lw.likelihood ? rw.y : lw.y;
    }

    final mid        = _windowSize ~/ 2;
    final earlyWrist = wristY(_history.first);
    final peakWrist  = wristY(_history[mid]);
    final endWrist   = wristY(_history.last);

    if (earlyWrist == null || peakWrist == null || endWrist == null) return false;

    final riseAmount = earlyWrist - peakWrist;
    final snapDown   = endWrist - peakWrist;
    return riseAmount > 80 && snapDown > 40;
  }

  bool _detectBlock() {
    int framesUp = 0;
    for (final pose in _history) {
      final rw   = pose.landmarks[PoseLandmarkType.rightWrist];
      final lw   = pose.landmarks[PoseLandmarkType.leftWrist];
      final nose = pose.landmarks[PoseLandmarkType.nose];
      if (rw == null || lw == null || nose == null) continue;
      if (rw.y < nose.y && lw.y < nose.y) {
        framesUp++;
      } else {
        framesUp = 0;
      }
      if (framesUp >= 5) return true;
    }
    return false;
  }

  void reset() {
    _history.clear();
    _lastHit   = DateTime(2000);
    _lastBlock = DateTime(2000);
  }
}
