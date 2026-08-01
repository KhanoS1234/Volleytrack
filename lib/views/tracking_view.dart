import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../theme.dart';
import '../models/game_event.dart';
import '../viewmodels/tracking_viewmodel.dart';
import 'stats_view.dart';

class TrackingView extends StatefulWidget {
  final String jersey;
  final String playerName;
  final Color jerseyColor;

  const TrackingView({
    super.key,
    required this.jersey,
    required this.playerName,
    required this.jerseyColor,
  });

  @override
  State<TrackingView> createState() => _TrackingViewState();
}

class _TrackingViewState extends State<TrackingView>
    with SingleTickerProviderStateMixin {
  late TrackingViewModel _vm;
  late AnimationController _scanController;
  bool _isInitialising = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _vm = TrackingViewModel(jersey: widget.jersey, playerName: widget.playerName);
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _initialise();
    _vm.addListener(() { if (mounted) setState(() {}); });
  }

  Future<void> _initialise() async {
    try {
      await _vm.initialise();
      setState(() => _isInitialising = false);
    } catch (e) {
      setState(() { _isInitialising = false; _error = e.toString(); });
    }
  }

  Future<void> _endSession() async {
    final session = await _vm.endSession();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => StatsView(session: session)),
    );
  }

  @override
  void dispose() {
    _scanController.dispose();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Camera — 65% of screen
          Expanded(
            flex: 65,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildCamera(),

                // Skeleton overlay — drawn under the bounding box
                if (_vm.skeletonLandmarks.isNotEmpty && _vm.isPlayerLocked)
                  CustomPaint(
                    painter: _SkeletonPainter(
                      landmarks: _vm.skeletonLandmarks,
                      cameraController: _vm.cameraController,
                      playerVisible: _vm.playerVisible,
                    ),
                  ),

                // Scan line — only show when searching
                if (!_vm.isPlayerLocked)
                  AnimatedBuilder(
                    animation: _scanController,
                    builder: (_, __) => Positioned(
                      top: _scanController.value * MediaQuery.of(context).size.height * 0.65,
                      left: 0, right: 0,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.transparent,
                            VTColors.blockCyan.withValues(alpha: 0.6),
                            Colors.transparent,
                          ]),
                        ),
                      ),
                    ),
                  ),

                // Corner brackets
                _corner(top: true,  left: true),
                _corner(top: true,  left: false),
                _corner(top: false, left: true),
                _corner(top: false, left: false),

                // Player bounding box with status
                if (_vm.playerBoundingBox != null) _buildPlayerBox(),

                // HUD top bar
                _buildHUD(),

                // Confidence indicator — only when locked
                if (_vm.isPlayerLocked) _buildConfidenceBar(),

                // Bottom live stats
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: _buildLiveStats(),
                ),

                // Event flash
                if (_vm.showFlash) _buildFlash(),
              ],
            ),
          ),

          // Controls panel — 35% of screen
          Expanded(
            flex: 35,
            child: Container(
              color: VTColors.courtBlue,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                children: [
                  _buildAINote(),
                  const SizedBox(height: 12),
                  _buildManualButtons(),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _endSession,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: VTColors.dangerRed, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('END SESSION',
                        style: GoogleFonts.bebasNeue(fontSize: 18, letterSpacing: 2, color: VTColors.dangerRed)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    if (_isInitialising) {
      return Container(
        color: VTColors.courtBlue,
        child: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: VTColors.blockCyan),
            const SizedBox(height: 16),
            Text('Starting camera...', style: GoogleFonts.inter(color: VTColors.textDim)),
          ],
        )),
      );
    }
    if (_error != null || _vm.cameraController == null || !_vm.cameraController!.value.isInitialized) {
      return Container(
        color: VTColors.courtBlue,
        child: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, color: VTColors.textDim, size: 48),
            const SizedBox(height: 16),
            Text('Camera unavailable\nUse manual buttons below',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: VTColors.textDim)),
          ],
        )),
      );
    }
    return CameraPreview(_vm.cameraController!);
  }

  Widget _buildPlayerBox() {
    final box = _vm.playerBoundingBox!;
    final screenSize = MediaQuery.of(context).size;
    final viewHeight = screenSize.height * 0.65;
    final viewWidth  = screenSize.width;

    final scaleX = viewWidth  / (_vm.cameraController?.value.previewSize?.height ?? viewWidth);
    final scaleY = viewHeight / (_vm.cameraController?.value.previewSize?.width  ?? viewHeight);

    // Box colour: green = locked and visible, orange = locked but lost, cyan = searching
    final boxColor = _vm.isPlayerLocked
        ? (_vm.playerVisible ? VTColors.pointGreen : VTColors.spikeGold)
        : VTColors.blockCyan;

    final statusText = _vm.isPlayerLocked
        ? (_vm.playerVisible ? '#${widget.jersey} · TRACKING' : '#${widget.jersey} · SEARCHING...')
        : 'SCANNING FOR #${widget.jersey}';

    return Positioned(
      left:   (box.left  * scaleX).clamp(0, viewWidth  - 20),
      top:    (box.top   * scaleY).clamp(0, viewHeight - 20),
      width:  (box.width * scaleX).clamp(20, viewWidth),
      height: (box.height * scaleY).clamp(20, viewHeight),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Animated border — pulses when locked
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              border: Border.all(color: boxColor, width: _vm.playerVisible ? 2.5 : 1.5),
              borderRadius: BorderRadius.circular(4),
              color: boxColor.withValues(alpha: _vm.playerVisible ? 0.05 : 0.02),
            ),
          ),
          // Label above box
          Positioned(
            top: -26, left: -2,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: boxColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Text(
                statusText,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          // Confidence badge bottom right of box
          if (_vm.isPlayerLocked && _vm.playerVisible)
            Positioned(
              bottom: -20, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: boxColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '${(_vm.detectionConfidence * 100).toStringAsFixed(0)}% conf',
                  style: GoogleFonts.jetBrainsMono(fontSize: 9, color: boxColor),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Confidence bar shown at top right when player is locked
  Widget _buildConfidenceBar() {
    final conf = _vm.detectionConfidence;
    final color = conf > 0.7
        ? VTColors.pointGreen
        : conf > 0.4
            ? VTColors.spikeGold
            : VTColors.dangerRed;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      right: 16,
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('CONF', style: GoogleFonts.inter(fontSize: 8, color: VTColors.textDim, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: conf,
                backgroundColor: VTColors.surface2,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${(conf * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.jetBrainsMono(fontSize: 9, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _corner({required bool top, required bool left}) {
    const size = 20.0;
    return Positioned(
      top:    top  ? 10 : null,
      bottom: top  ? null : 10,
      left:   left ? 10 : null,
      right:  left ? null : 10,
      child: SizedBox(width: size, height: size,
        child: CustomPaint(painter: _CornerPainter(top: top, left: left)),
      ),
    );
  }

  Widget _buildHUD() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16, right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _glass(Row(mainAxisSize: MainAxisSize.min, children: [
            Text('#${widget.jersey}',
              style: GoogleFonts.bebasNeue(fontSize: 22, color: VTColors.spikeGold, height: 1)),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('TRACKING', style: GoogleFonts.inter(fontSize: 9, color: VTColors.textDim, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: _vm.isPlayerLocked
                        ? (_vm.playerVisible ? VTColors.pointGreen : VTColors.spikeGold)
                        : VTColors.dangerRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _vm.isPlayerLocked
                      ? (_vm.playerVisible ? 'Locked on' : 'Player lost')
                      : 'Searching...',
                  style: GoogleFonts.inter(fontSize: 9, color: VTColors.textDim),
                ),
              ]),
            ]),
          ])),
          _glass(Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 7, height: 7,
              decoration: const BoxDecoration(color: VTColors.dangerRed, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(_vm.formattedTime,
              style: GoogleFonts.jetBrainsMono(fontSize: 14, color: VTColors.netWhite)),
          ])),
        ],
      ),
    );
  }

  Widget _glass(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: VTColors.blockCyan.withValues(alpha: 0.2)),
    ),
    child: child,
  );

  Widget _buildLiveStats() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _liveStat('${_vm.hits}',             'HITS',   VTColors.spikeGold),
          _liveStat('${_vm.blocks}',           'BLOCKS', VTColors.blockCyan),
          _liveStat('${_vm.pointPercentage}%', 'PTS %',  VTColors.pointGreen),
        ],
      ),
    );
  }

  Widget _liveStat(String val, String lbl, Color color) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(val, style: GoogleFonts.bebasNeue(fontSize: 28, color: color, height: 1)),
      const SizedBox(height: 2),
      Text(lbl, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1, color: VTColors.textDim)),
    ],
  );

  Widget _buildFlash() {
    final type = _vm.flashType;
    if (type == null) return const SizedBox.shrink();
    final styles = {
      EventType.hit:   {'label': '💥 HIT',   'color': VTColors.spikeGold},
      EventType.block: {'label': '🤚 BLOCK', 'color': VTColors.blockCyan},
      EventType.point: {'label': '✅ POINT', 'color': VTColors.pointGreen},
    };
    final count = type == EventType.hit ? _vm.hits : type == EventType.block ? _vm.blocks : _vm.points;
    final color = styles[type]!['color'] as Color;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 20)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(styles[type]!['label'] as String,
            style: GoogleFonts.bebasNeue(fontSize: 36, letterSpacing: 3, color: color, height: 1)),
          const SizedBox(height: 4),
          Text('× $count', style: GoogleFonts.jetBrainsMono(fontSize: 13, color: VTColors.textDim)),
        ]),
      ),
    );
  }

  Widget _buildAINote() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: VTColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: VTColors.blockCyan.withValues(alpha: 0.15)),
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: VTColors.blockCyan, borderRadius: BorderRadius.circular(4)),
        child: Text('AI', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1, color: Colors.black)),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Skeleton overlay active. Green box = locked. Orange = player lost.',
        style: GoogleFonts.inter(fontSize: 11, color: VTColors.textDim),
      )),
    ]),
  );

  Widget _buildManualButtons() => Row(children: [
    Expanded(child: _manualBtn('💥', 'HIT',   VTColors.spikeGold,  () => _vm.recordEvent(EventType.hit))),
    const SizedBox(width: 8),
    Expanded(child: _manualBtn('🤚', 'BLOCK', VTColors.blockCyan,  () => _vm.recordEvent(EventType.block))),
    const SizedBox(width: 8),
    Expanded(child: _manualBtn('✅', 'POINT', VTColors.pointGreen, () => _vm.recordEvent(EventType.point))),
  ]);

  Widget _manualBtn(String emoji, String label, Color color, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: VTColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: VTColors.blockCyan.withValues(alpha: 0.15), width: 1.5),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.bebasNeue(fontSize: 14, letterSpacing: 1, color: VTColors.textDim)),
        ]),
      ),
    );
}

// ─── Skeleton Painter ──────────────────────────────────────────────────────

class _SkeletonPainter extends CustomPainter {
  final List<PoseLandmark> landmarks;
  final dynamic cameraController;
  final bool playerVisible;

  _SkeletonPainter({
    required this.landmarks,
    required this.cameraController,
    required this.playerVisible,
  });

  // Define which joints to connect with lines
  static const List<List<PoseLandmarkType>> _connections = [
    // Torso
    [PoseLandmarkType.leftShoulder,  PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip,       PoseLandmarkType.rightHip],
    // Left arm
    [PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow,     PoseLandmarkType.leftWrist],
    // Right arm
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow,    PoseLandmarkType.rightWrist],
    // Left leg
    [PoseLandmarkType.leftHip,       PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee,      PoseLandmarkType.leftAnkle],
    // Right leg
    [PoseLandmarkType.rightHip,      PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee,     PoseLandmarkType.rightAnkle],
    // Head
    [PoseLandmarkType.leftShoulder,  PoseLandmarkType.nose],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.nose],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    final color = playerVisible
        ? const Color(0xFF00E87A)   // green when locked
        : const Color(0xFFF5A623);  // gold when searching

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Build a lookup map for fast access
    final Map<PoseLandmarkType, PoseLandmark> landmarkMap = {
      for (final l in landmarks) l.type: l
    };

    // Get camera preview dimensions for scaling
    final previewW = cameraController?.value.previewSize?.height ?? size.width;
    final previewH = cameraController?.value.previewSize?.width  ?? size.height;

    Offset toScreen(PoseLandmark l) {
      final x = (l.x / previewW) * size.width;
      final y = (l.y / previewH) * size.height;
      return Offset(x, y);
    }

    // Draw connecting lines
    for (final connection in _connections) {
      final a = landmarkMap[connection[0]];
      final b = landmarkMap[connection[1]];
      if (a == null || b == null) continue;
      if (a.likelihood < 0.4 || b.likelihood < 0.4) continue;

      canvas.drawLine(toScreen(a), toScreen(b), linePaint);
    }

    // Draw joint dots
    for (final landmark in landmarks) {
      if (landmark.likelihood < 0.4) continue;
      canvas.drawCircle(toScreen(landmark), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) =>
      old.landmarks != landmarks || old.playerVisible != playerVisible;
}

// ─── Corner Bracket Painter ────────────────────────────────────────────────

class _CornerPainter extends CustomPainter {
  final bool top, left;
  _CornerPainter({required this.top, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = VTColors.blockCyan
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    final x  = left ? 0.0 : size.width;
    final y  = top  ? 0.0 : size.height;
    final dx = left ? size.width  : -size.width;
    final dy = top  ? size.height : -size.height;

    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
