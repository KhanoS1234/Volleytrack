import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../theme.dart';
import '../models/team_model.dart';
import '../services/color_detector.dart';

class PlayerRegistrationView extends StatefulWidget {
  final PlayerRegistration? existing;
  const PlayerRegistrationView({super.key, this.existing});

  @override
  State<PlayerRegistrationView> createState() =>
      _PlayerRegistrationViewState();
}

class _PlayerRegistrationViewState extends State<PlayerRegistrationView> {
  final _jerseyController = TextEditingController();
  final _nameController   = TextEditingController();

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;
  bool _capturing   = false;

  List<String> _photoPaths = [];
  JerseyColors? _detectedColors;
  bool _detectingColors = false;

  final List<Map<String, String>> _photoGuides = [
    {'distance': '1-2m',  'icon': '🔍', 'label': 'Close up'},
    {'distance': '4-6m',  'icon': '📏', 'label': 'Medium distance'},
    {'distance': '10-12m','icon': '🔭', 'label': 'Far distance'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _jerseyController.text = widget.existing!.jersey;
      _nameController.text   = widget.existing!.name;
      _photoPaths = List.from(widget.existing!.photoPaths);
      _detectedColors = widget.existing!.colors;

      // DEBUG — verify what paths we received and whether files exist
      debugPrint('=== EDIT PLAYER DEBUG ===');
      debugPrint('Received ${_photoPaths.length} photo paths:');
      for (final p in _photoPaths) {
        final exists = File(p).existsSync();
        debugPrint('  Path: $p — exists on disk: $exists');
      }
      debugPrint('=========================');
    }
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;

    final back = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    _cameraController = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (mounted) setState(() => _cameraReady = true);
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraReady || _capturing) return;
    if (_photoPaths.length >= 3) return;

    setState(() => _capturing = true);

    try {
      final xFile = await _cameraController!.takePicture();

      // Use a persistent, app-specific subfolder so files aren't
      // accidentally cleaned up by the OS or confused with temp files
      final docsDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory(path.join(docsDir.path, 'jersey_photos'));
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }

      final jersey  = _jerseyController.text.trim().isEmpty
          ? 'player'
          : _jerseyController.text.trim();
      final fileName =
          'jersey_${jersey}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = path.join(photosDir.path, fileName);

      // Copy from temp camera location to our persistent location
      final savedFile = await File(xFile.path).copy(savedPath);

      // DEBUG — verify the copy actually succeeded
      final verifyExists = await savedFile.exists();
      final fileSize = verifyExists ? await savedFile.length() : 0;
      debugPrint('=== PHOTO CAPTURE DEBUG ===');
      debugPrint('Temp file: ${xFile.path}');
      debugPrint('Saved to: $savedPath');
      debugPrint('File exists after copy: $verifyExists');
      debugPrint('File size: $fileSize bytes');
      debugPrint('===========================');

      if (!verifyExists || fileSize == 0) {
        setState(() => _capturing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo save failed — please try again'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _photoPaths.add(savedPath);
        _capturing = false;
      });

      // Auto-detect jersey and number colours from the FIRST photo only —
      // it's the closest, clearest shot and best represents true colours
      if (_photoPaths.length == 1) {
        setState(() => _detectingColors = true);
        final colors = await ColorDetector.detectColors(savedPath);
        if (mounted) {
          setState(() {
            _detectedColors = colors;
            _detectingColors = false;
          });
        }
      }
    } catch (e) {
      debugPrint('=== PHOTO CAPTURE ERROR === $e');
      setState(() => _capturing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _photoPaths.removeAt(index);
      // If the first (colour-source) photo was removed, clear
      // detected colours so they get re-detected on next photo 1
      if (index == 0) _detectedColors = null;
    });
  }

  void _savePlayer() {
    final jersey = _jerseyController.text.trim();
    final name   = _nameController.text.trim();

    if (jersey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a jersey number')),
      );
      return;
    }

    if (_photoPaths.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Take all 3 photos at different distances')),
      );
      return;
    }

    final player = PlayerRegistration(
      jersey:     jersey,
      name:       name.isEmpty ? 'Player #$jersey' : name,
      photoPaths: _photoPaths,
      colors:     _detectedColors,
    );

    Navigator.pop(context, player);
  }

  @override
  void dispose() {
    _jerseyController.dispose();
    _nameController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  /// Shows the auto-detected jersey and number colours as swatches,
  /// so the coach can glance-confirm they look right, or retake the
  /// first photo if the detection looks obviously wrong.
  Widget _buildColorSwatches() {
    if (_detectingColors) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: VTColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: VTColors.blockCyan.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: VTColors.blockCyan),
            ),
            const SizedBox(width: 10),
            Text('Detecting colours...',
                style: GoogleFonts.inter(fontSize: 12, color: VTColors.textDim)),
          ],
        ),
      );
    }

    if (_detectedColors == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VTColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VTColors.blockCyan.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, color: VTColors.blockCyan, size: 14),
              const SizedBox(width: 6),
              Text('AUTO-DETECTED COLOURS',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: VTColors.blockCyan)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _colorSwatchTile(
                  'Jersey', _detectedColors!.jerseyColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _colorSwatchTile(
                  'Number', _detectedColors!.numberColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Doesn\'t look right? Remove photo 1 below and retake it.',
            style: GoogleFonts.inter(fontSize: 10, color: VTColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _colorSwatchTile(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: GoogleFonts.inter(fontSize: 12, color: VTColors.textDim)),
      ],
    );
  }

  /// Builds a thumbnail, showing a visible broken-image state if the
  /// file is missing from disk instead of failing silently.
  Widget _buildThumbnail(String filePath) {
    final file = File(filePath);
    final exists = file.existsSync();

    if (!exists) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: VTColors.dangerRed.withValues(alpha: 0.5)),
          color: VTColors.dangerRed.withValues(alpha: 0.1),
        ),
        child: const Center(
          child: Icon(Icons.broken_image, color: VTColors.dangerRed, size: 24),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VTColors.pointGreen.withValues(alpha: 0.4)),
        image: DecorationImage(image: FileImage(file), fit: BoxFit.cover),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VTColors.courtBlue,
      appBar: AppBar(
        backgroundColor: VTColors.courtMid,
        title: Text('REGISTER PLAYER',
            style: GoogleFonts.bebasNeue(
                fontSize: 22, letterSpacing: 2, color: VTColors.netWhite)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VTColors.netWhite),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Jersey #'),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _jerseyController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(2),
                              ],
                              style: GoogleFonts.bebasNeue(
                                  fontSize: 28,
                                  color: VTColors.netWhite,
                                  letterSpacing: 3),
                              decoration: InputDecoration(
                                hintText: '07',
                                hintStyle: GoogleFonts.bebasNeue(
                                    fontSize: 28,
                                    color: VTColors.muted,
                                    letterSpacing: 3),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Player Name'),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _nameController,
                              style: GoogleFonts.inter(
                                  fontSize: 14, color: VTColors.netWhite),
                              decoration: InputDecoration(
                                hintText: 'Optional',
                                hintStyle: GoogleFonts.inter(
                                    fontSize: 14, color: VTColors.muted),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  _Label('Reference Photos'),
                  const SizedBox(height: 6),
                  Text(
                    'Take 3 photos of the jersey number from different distances. This helps the app recognise the player on court.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: VTColors.textDim, height: 1.5),
                  ),

                  const SizedBox(height: 16),

                  // Auto-detected colour swatches — appear once the
                  // first (close-up) photo has been taken
                  if (_photoPaths.isNotEmpty) ...[
                    _buildColorSwatches(),
                    const SizedBox(height: 16),
                  ],

                  ...List.generate(3, (i) {
                    final taken  = i < _photoPaths.length;
                    final active = i == _photoPaths.length;
                    final guide  = _photoGuides[i];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: taken
                            ? VTColors.pointGreen.withValues(alpha: 0.08)
                            : active
                                ? VTColors.blockCyan.withValues(alpha: 0.08)
                                : VTColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: taken
                              ? VTColors.pointGreen.withValues(alpha: 0.4)
                              : active
                                  ? VTColors.blockCyan.withValues(alpha: 0.4)
                                  : VTColors.blockCyan.withValues(alpha: 0.1),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: taken
                                  ? VTColors.pointGreen.withValues(alpha: 0.2)
                                  : active
                                      ? VTColors.blockCyan.withValues(alpha: 0.2)
                                      : VTColors.surface2,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: taken
                                  ? const Icon(Icons.check,
                                      color: VTColors.pointGreen, size: 18)
                                  : Text(guide['icon']!,
                                      style: const TextStyle(fontSize: 16)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Photo ${i + 1} — ${guide['label']}',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: taken
                                        ? VTColors.pointGreen
                                        : active
                                            ? VTColors.netWhite
                                            : VTColors.textDim,
                                  ),
                                ),
                                Text(
                                  'Distance: ${guide['distance']}',
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: VTColors.textDim),
                                ),
                              ],
                            ),
                          ),
                          if (taken)
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: VTColors.textDim, size: 16),
                              onPressed: () => _removePhoto(i),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 16),

                  if (_photoPaths.length < 3) ...[
                    _Label(
                        'Camera — ${_photoGuides[_photoPaths.length]['label']} (${_photoGuides[_photoPaths.length]['distance']})'),
                    const SizedBox(height: 8),
                    Container(
                      height: 240,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: VTColors.blockCyan.withValues(alpha: 0.3)),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_cameraReady && _cameraController != null)
                            Center(
                              child: AspectRatio(
                                aspectRatio: _cameraController!.value.aspectRatio,
                                child: CameraPreview(_cameraController!),
                              ),
                            )
                          else
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(
                                      color: VTColors.blockCyan),
                                  const SizedBox(height: 12),
                                  Text('Starting camera...',
                                      style: GoogleFonts.inter(
                                          color: VTColors.textDim,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                          Center(
                            child: Container(
                              width: 120,
                              height: 80,
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: VTColors.spikeGold, width: 2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Center(
                                child: Text(
                                  'AIM HERE',
                                  style: GoogleFonts.bebasNeue(
                                    fontSize: 12,
                                    color: VTColors.spikeGold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _cameraReady && !_capturing
                            ? _capturePhoto
                            : null,
                        icon: _capturing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.camera_alt,
                                color: Colors.black),
                        label: Text(
                          'CAPTURE PHOTO ${_photoPaths.length + 1} OF 3',
                          style: GoogleFonts.bebasNeue(
                              fontSize: 16,
                              letterSpacing: 1.5,
                              color: Colors.black),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VTColors.blockCyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],

                  // Thumbnails — now with broken-file detection
                  if (_photoPaths.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Label('Captured Photos'),
                    const SizedBox(height: 8),
                    Row(
                      children: _photoPaths.asMap().entries.map((entry) {
                        return Expanded(
                          child: Container(
                            margin: EdgeInsets.only(
                                right:
                                    entry.key < _photoPaths.length - 1 ? 8 : 0),
                            height: 80,
                            child: _buildThumbnail(entry.value),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _photoPaths.length >= 3 ? _savePlayer : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _photoPaths.length >= 3
                      ? VTColors.spikeGold
                      : VTColors.muted,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  _photoPaths.length >= 3
                      ? 'SAVE PLAYER'
                      : 'TAKE ${3 - _photoPaths.length} MORE PHOTO${3 - _photoPaths.length == 1 ? '' : 'S'}',
                  style: GoogleFonts.bebasNeue(
                      fontSize: 18, letterSpacing: 2, color: Colors.black),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: VTColors.blockCyan),
      );
}
