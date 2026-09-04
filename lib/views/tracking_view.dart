import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../theme.dart';
import '../models/game_event.dart';
import '../models/player_config.dart';
import '../services/detection_settings.dart';
import '../viewmodels/tracking_viewmodel.dart';
import 'multi_stats_view.dart';

class TrackingView extends StatefulWidget {
  final List<PlayerConfig> players;

  const TrackingView({super.key, required this.players});

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

    // Tracking captures more of the court in landscape — switch
    // orientation for this screen only, restore on exit
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _vm = TrackingViewModel(players: widget.players);
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _initialise();
    _vm.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initialise() async {
    try {
      await _vm.initialise();
      setState(() => _isInitialising = false);
    } catch (e) {
      setState(() {
        _isInitialising = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _endSession() async {
    final results = await _vm.endSession();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MultiStatsView(
          playerStats: results,
          players: widget.players,
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Restore portrait for the rest of the app (setup, stats, etc.)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
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
          // Camera — 60% of screen
          Expanded(
            flex: 60,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildCamera(),

                // Skeleton overlays for all players
                ...widget.players.map((p) {
                  final visible = _vm.playerVisible[p.jersey] ?? false;
                  if (!visible) return const SizedBox.shrink();
                  final landmarks = _vm.skeletons[p.jersey] ?? [];
                  if (landmarks.isEmpty) return const SizedBox.shrink();
                  return CustomPaint(
                    painter: _SkeletonPainter(
                      landmarks: landmarks,
                      color: p.color,
                      cameraController: _vm.cameraController,
                      visible: _vm.playerVisible[p.jersey] ?? false,
                    ),
                  );
                }),

                // Scan line when searching
                if (!widget.players.any((p) => _vm.playerLocked[p.jersey] == true))
                  AnimatedBuilder(
                    animation: _scanController,
                    builder: (_, __) => Positioned(
                      top: _scanController.value *
                          MediaQuery.of(context).size.height *
                          0.60,
                      left: 0,
                      right: 0,
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
                _corner(top: true, left: true),
                _corner(top: true, left: false),
                _corner(top: false, left: true),
                _corner(top: false, left: false),

                // Bounding boxes for all players
                ...widget.players.map((p) => _buildPlayerBox(p)),

                // HUD top bar
                _buildHUD(),

                // Jersey sensitivity slider — DEVELOPMENT ONLY
                // Remove once optimal value is found and hardcoded
                _buildSensitivitySlider(),

                // Event flash
                if (_vm.showFlash) _buildFlash(),
              ],
            ),
          ),

          // Player cards + controls — 40% of screen
          Expanded(
            flex: 40,
            child: Container(
              color: VTColors.courtBlue,
              child: Column(
                children: [
                  // Player stat cards — side by side
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Row(
                        children: widget.players.asMap().entries.map((entry) {
                          final i = entry.key;
                          final p = entry.value;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => _vm.selectPlayer(i),
                              child: _PlayerCard(
                                player: p,
                                stats: _vm.stats[p.jersey]!,
                                isSelected: _vm.selectedPlayerIndex == i,
                                isLocked: _vm.playerLocked[p.jersey] ?? false,
                                isVisible: _vm.playerVisible[p.jersey] ?? false,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // Manual log buttons for selected player
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _vm.selectedPlayer.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'LOGGING FOR #${_vm.selectedPlayer.jersey}',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                                color: VTColors.textDim,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(
                              child: _manualBtn(
                                  '💥',
                                  'HIT',
                                  VTColors.spikeGold,
                                  () => _vm.recordEvent(
                                      _vm.selectedPlayer.jersey, EventType.hit))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _manualBtn(
                                  '🤚',
                                  'BLOCK',
                                  VTColors.blockCyan,
                                  () => _vm.recordEvent(
                                      _vm.selectedPlayer.jersey, EventType.block))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _manualBtn(
                                  '✅',
                                  'POINT',
                                  VTColors.pointGreen,
                                  () => _vm.recordEvent(
                                      _vm.selectedPlayer.jersey, EventType.point))),
                        ]),
                      ],
                    ),
                  ),

                  // End session
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _endSession,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: VTColors.dangerRed, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('END SESSION',
                            style: GoogleFonts.bebasNeue(
                                fontSize: 16,
                                letterSpacing: 2,
                                color: VTColors.dangerRed)),
                      ),
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
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: VTColors.blockCyan),
          const SizedBox(height: 16),
          Text('Starting camera...',
              style: GoogleFonts.inter(color: VTColors.textDim)),
        ])),
      );
    }
    if (_error != null ||
        _vm.cameraController == null ||
        !_vm.cameraController!.value.isInitialized) {
      return Container(
        color: VTColors.courtBlue,
        child: Center(
            child: Text('Camera unavailable\nUse manual buttons below',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: VTColors.textDim))),
      );
    }
    return CameraPreview(_vm.cameraController!);
  }

  Widget _buildPlayerBox(PlayerConfig p) {
    final box = _vm.playerBoxes[p.jersey];
    if (box == null) return const SizedBox.shrink();

    final screenSize = MediaQuery.of(context).size;
    final viewHeight = screenSize.height * 0.60;
    final viewWidth = screenSize.width;

    final scaleX = viewWidth /
        (_vm.cameraController?.value.previewSize?.height ?? viewWidth);
    final scaleY = viewHeight /
        (_vm.cameraController?.value.previewSize?.width ?? viewHeight);

    final visible = _vm.playerVisible[p.jersey] ?? false;
    final crossing = _vm.isCrossing[p.jersey] ?? false;
    final color = crossing
        ? VTColors.dangerRed
        : (visible ? p.color : VTColors.spikeGold);
    final source = _vm.lockSource[p.jersey] ?? '';

    // Badge colour per source — helps distinguish at a glance
    final sourceColor = source == 'OCR'
        ? VTColors.blockCyan
        : source == 'PHOTO'
            ? VTColors.spikeGold
            : source == 'COLOR'
                ? const Color(0xFFFF69B4) // pink — distinct from other sources
                : VTColors.pointGreen; // SKELETON

    return Positioned(
      left: (box.left * scaleX).clamp(0, viewWidth - 20),
      top: (box.top * scaleY).clamp(0, viewHeight - 20),
      width: (box.width * scaleX).clamp(20, viewWidth),
      height: (box.height * scaleY).clamp(20, viewHeight),
      child: Stack(clipBehavior: Clip.none, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(4),
            color: color.withValues(alpha: 0.05),
          ),
        ),
        Positioned(
          top: -22,
          left: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4), topRight: Radius.circular(4)),
            ),
            child: Text(
              crossing
                  ? '#${p.jersey} · HOLD'
                  : '#${p.jersey} · ${visible ? "ON" : "LOST"}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.black),
            ),
          ),
        ),
        // Source badge — shows which method locked this player
        if (visible && source.isNotEmpty)
          Positioned(
            bottom: -18,
            left: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: sourceColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                source,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.black),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildHUD() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: widget.players
                .map((p) => Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: p.color.withValues(alpha: 0.4)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: (_vm.playerLocked[p.jersey] ?? false)
                                ? ((_vm.playerVisible[p.jersey] ?? false)
                                    ? p.color
                                    : VTColors.spikeGold)
                                : VTColors.dangerRed,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('#${p.jersey}',
                            style: GoogleFonts.bebasNeue(
                                fontSize: 14, color: p.color, height: 1)),
                      ]),
                    ))
                .toList(),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: VTColors.blockCyan.withValues(alpha: 0.2)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: VTColors.dangerRed, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(_vm.formattedTime,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 13, color: VTColors.netWhite)),
            ]),
          ),
        ],
      ),
    );
  }

  /// Live jersey number recognition tuning sliders.
  /// DEVELOPMENT ONLY — remove once optimal values are found and hardcoded.
  Widget _buildSensitivitySlider() {
    final settings = DetectionSettings();

    return Positioned(
      left: 16,
      right: 16,
      bottom: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: VTColors.spikeGold.withValues(alpha: 0.3)),
        ),
        child: StatefulBuilder(
          builder: (context, setSliderState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // DEBUG — proves the live value the detection loop is
                // actually reading right now. Remove once confirmed working.
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'LIVE: minWidth=${settings.minDetectionWidth.toStringAsFixed(1)}px  '
                    'confirmFrames=${settings.confirmationFrames}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: VTColors.pointGreen,
                    ),
                  ),
                ),

                // Slider 1 — distance sensitivity
                Row(
                  children: [
                    const Icon(Icons.tune, color: VTColors.spikeGold, size: 16),
                    const SizedBox(width: 8),
                    Text('Jersey Sensitivity',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: VTColors.textDim)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 7),
                          activeTrackColor: VTColors.spikeGold,
                          inactiveTrackColor: VTColors.surface2,
                          thumbColor: VTColors.spikeGold,
                        ),
                        child: Slider(
                          value: settings.minDetectionWidth,
                          min: DetectionSettings.minWidthAllowed,
                          max: DetectionSettings.maxWidthAllowed,
                          onChanged: (v) {
                            settings.setMinDetectionWidth(v);
                            setSliderState(() {});
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 46,
                      child: Text(
                        settings.minDetectionWidth < 12
                            ? 'FAR'
                            : settings.minDetectionWidth > 25
                                ? 'CLOSE'
                                : 'MID',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.bebasNeue(
                          fontSize: 14,
                          letterSpacing: 1,
                          color: VTColors.spikeGold,
                        ),
                      ),
                    ),
                  ],
                ),

                // Slider 2 — lock confidence (false positive prevention)
                Row(
                  children: [
                    const Icon(Icons.verified_outlined,
                        color: VTColors.blockCyan, size: 16),
                    const SizedBox(width: 8),
                    Text('Lock Confidence',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: VTColors.textDim)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 7),
                          activeTrackColor: VTColors.blockCyan,
                          inactiveTrackColor: VTColors.surface2,
                          thumbColor: VTColors.blockCyan,
                        ),
                        child: Slider(
                          value: settings.confirmationFrames.toDouble(),
                          min: DetectionSettings.minConfirmationAllowed
                              .toDouble(),
                          max: DetectionSettings.maxConfirmationAllowed
                              .toDouble(),
                          divisions: DetectionSettings.maxConfirmationAllowed -
                              DetectionSettings.minConfirmationAllowed,
                          onChanged: (v) {
                            settings.setConfirmationFrames(v.round());
                            setSliderState(() {});
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 46,
                      child: Text(
                        '${settings.confirmationFrames}x',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.bebasNeue(
                          fontSize: 14,
                          letterSpacing: 1,
                          color: VTColors.blockCyan,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFlash() {
    final type = _vm.flashType;
    final jersey = _vm.flashJersey;
    if (type == null || jersey == null) return const SizedBox.shrink();

    final player = widget.players.firstWhere(
      (p) => p.jersey == jersey,
      orElse: () => widget.players.first,
    );

    final styles = {
      EventType.hit: {'label': '💥 HIT', 'color': VTColors.spikeGold},
      EventType.block: {'label': '🤚 BLOCK', 'color': VTColors.blockCyan},
      EventType.point: {'label': '✅ POINT', 'color': VTColors.pointGreen},
    };

    final color = styles[type]!['color'] as Color;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('#$jersey ${player.name}',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  color: player.color,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(styles[type]!['label'] as String,
              style: GoogleFonts.bebasNeue(
                  fontSize: 32, letterSpacing: 3, color: color, height: 1)),
        ]),
      ),
    );
  }

  Widget _corner({required bool top, required bool left}) {
    const size = 20.0;
    return Positioned(
      top: top ? 10 : null,
      bottom: top ? null : 10,
      left: left ? 10 : null,
      right: left ? null : 10,
      child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _CornerPainter(top: top, left: left))),
    );
  }

  Widget _manualBtn(
          String emoji, String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: VTColors.surface,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: VTColors.blockCyan.withValues(alpha: 0.15), width: 1.5),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.bebasNeue(
                    fontSize: 12, letterSpacing: 1, color: VTColors.textDim)),
          ]),
        ),
      );
}

// ─── Player Stat Card ──────────────────────────────────────────────────────

class _PlayerCard extends StatelessWidget {
  final PlayerConfig player;
  final PlayerStats stats;
  final bool isSelected;
  final bool isLocked;
  final bool isVisible;

  const _PlayerCard({
    required this.player,
    required this.stats,
    required this.isSelected,
    required this.isLocked,
    required this.isVisible,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isSelected
            ? player.color.withValues(alpha: 0.12)
            : VTColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? player.color : player.color.withValues(alpha: 0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Text('#${player.jersey}',
                style: GoogleFonts.bebasNeue(
                    fontSize: 20, color: player.color, height: 1)),
            const Spacer(),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isLocked
                    ? (isVisible ? player.color : VTColors.spikeGold)
                    : VTColors.dangerRed,
                shape: BoxShape.circle,
              ),
            ),
          ]),
          Text(
            stats.name,
            style: GoogleFonts.inter(fontSize: 9, color: VTColors.textDim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Divider(color: VTColors.surface2, height: 8),
          _statRow('HIT', '${stats.hits}', VTColors.spikeGold),
          _statRow('BLK', '${stats.blocks}', VTColors.blockCyan),
          _statRow('PT%', '${stats.pointPercentage}%', VTColors.pointGreen),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 9,
                  color: VTColors.textDim,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(value,
              style: GoogleFonts.bebasNeue(fontSize: 14, color: color, height: 1)),
        ]),
      );
}

// ─── Skeleton Painter ──────────────────────────────────────────────────────

class _SkeletonPainter extends CustomPainter {
  final List<PoseLandmark> landmarks;
  final Color color;
  final dynamic cameraController;
  final bool visible;

  _SkeletonPainter({
    required this.landmarks,
    required this.color,
    required this.cameraController,
    required this.visible,
  });

  static const List<List<PoseLandmarkType>> _connections = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.nose],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.nose],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    final drawColor = visible ? color : color.withValues(alpha: 0.3);

    final linePaint = Paint()
      ..color = drawColor.withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = drawColor
      ..style = PaintingStyle.fill;

    final Map<PoseLandmarkType, PoseLandmark> landmarkMap = {
      for (final l in landmarks) l.type: l
    };

    final previewW = cameraController?.value.previewSize?.height ?? size.width;
    final previewH = cameraController?.value.previewSize?.width ?? size.height;

    Offset toScreen(PoseLandmark l) => Offset(
          (l.x / previewW) * size.width,
          (l.y / previewH) * size.height,
        );

    for (final conn in _connections) {
      final a = landmarkMap[conn[0]];
      final b = landmarkMap[conn[1]];
      if (a == null || b == null) continue;
      if (a.likelihood < 0.4 || b.likelihood < 0.4) continue;
      canvas.drawLine(toScreen(a), toScreen(b), linePaint);
    }

    for (final l in landmarks) {
      if (l.likelihood < 0.4) continue;
      canvas.drawCircle(toScreen(l), 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) =>
      old.landmarks != landmarks || old.visible != visible;
}

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

    final x = left ? 0.0 : size.width;
    final y = top ? 0.0 : size.height;
    canvas.drawLine(
        Offset(x, y), Offset(x + (left ? size.width : -size.width), y), paint);
    canvas.drawLine(
        Offset(x, y), Offset(x, y + (top ? size.height : -size.height)), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
