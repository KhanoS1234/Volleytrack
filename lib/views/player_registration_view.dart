import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../theme.dart';
import '../models/team_model.dart';

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

  // Guide text for each photo
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

      // Save to app documents directory
      final docsDir = await getApplicationDocumentsDirectory();
      final jersey  = _jerseyController.text.trim().isEmpty
          ? 'player'
          : _jerseyController.text.trim();
      final fileName =
          'jersey_${jersey}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = path.join(docsDir.path, fileName);

      await File(xFile.path).copy(savedPath);

      setState(() {
        _photoPaths.add(savedPath);
        _capturing = false;
      });
    } catch (e) {
      setState(() => _capturing = false);
    }
  }

  void _removePhoto(int index) {
    setState(() => _photoPaths.removeAt(index));
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
                  // Jersey number + name
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

                  // Photo guide steps
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
                          // Status icon
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

                          // Remove button for taken photos
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

                  // Camera preview
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
                            CameraPreview(_cameraController!)
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

                          // Guide overlay — centre box for jersey number
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

                    // Capture button
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

                  // Thumbnails of taken photos
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
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color:
                                      VTColors.pointGreen.withValues(alpha: 0.4)),
                              image: DecorationImage(
                                image: FileImage(File(entry.value)),
                                fit: BoxFit.cover,
                              ),
                            ),
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

          // Save button
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
