import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:ui' show Rect, Size;
import 'pose_analyser.dart';

class CameraService {
  CameraController? controller;
  List<CameraDescription> _cameras = [];

  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );

  final TextRecognizer _textRecognizer = TextRecognizer();
  final PoseAnalyser poseAnalyser = PoseAnalyser();

  bool _isProcessing = false;
  String _targetJersey = '';
  int _frameCount = 0;
  static const int _ocrEveryNFrames = 10;

  Function(String jersey, Rect boundingBox)? onPlayerDetected;

  Future<void> initialise() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) throw Exception('No cameras found on this device');
  }

  Future<void> startCamera(String targetJersey) async {
    _targetJersey = targetJersey;
    if (_cameras.isEmpty) await initialise();

    final backCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await controller!.initialize();
    await controller!.startImageStream(_processFrame);
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;
    _frameCount++;

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final poses = await _poseDetector.processImage(inputImage);
      for (final pose in poses) {
        poseAnalyser.addPose(pose);
      }

      if (_frameCount % _ocrEveryNFrames == 0) {
        await _runOCR(inputImage);
      }
    } catch (_) {
      // Continue silently on frame errors
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _runOCR(InputImage inputImage) async {
    final recognised = await _textRecognizer.processImage(inputImage);
    for (final block in recognised.blocks) {
      final text = block.text.trim();
      if (RegExp(r'^\d{1,2}$').hasMatch(text) && text == _targetJersey) {
        final bb = block.boundingBox;
        final expanded = Rect.fromLTWH(
          bb.left - bb.width * 2,
          bb.top - bb.height * 6,
          bb.width * 5,
          bb.height * 14,
        );
        onPlayerDetected?.call(text, expanded);
        return;
      }
    }
  }

  InputImage? _buildInputImage(CameraImage image) {
    final camera = controller?.description;
    if (camera == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation)
        ?? InputImageRotation.rotation0deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    if (image.planes.isEmpty) return null;

    final plane = image.planes[0];
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> stopCamera() async {
    await controller?.stopImageStream();
    await controller?.dispose();
    controller = null;
    poseAnalyser.reset();
    _frameCount = 0;
    _isProcessing = false;
  }

  Future<void> dispose() async {
    await stopCamera();
    await _poseDetector.close();
    await _textRecognizer.close();
  }
}
