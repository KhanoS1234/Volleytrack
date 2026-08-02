import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../models/player_config.dart';
import 'tracking_view.dart';

class SetupView extends StatefulWidget {
  const SetupView({super.key});
  @override
  State<SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<SetupView> {
  // Up to 3 players
  final List<TextEditingController> _jerseyControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  final List<TextEditingController> _nameControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  int _activePlayerCount = 1;

  void _startSession() {
    // Validate at least 1 jersey
    final jersey1 = _jerseyControllers[0].text.trim();
    if (jersey1.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one jersey number')),
      );
      return;
    }

    // Build player list for active slots only
    final List<PlayerConfig> players = [];
    for (int i = 0; i < _activePlayerCount; i++) {
      final jersey = _jerseyControllers[i].text.trim();
      if (jersey.isEmpty) continue;
      players.add(PlayerConfig(
        jersey: jersey,
        name: _nameControllers[i].text.trim().isEmpty
            ? 'Player #$jersey'
            : _nameControllers[i].text.trim(),
        color: PlayerColors.palette[i],
      ));
    }

    if (players.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one jersey number')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackingView(players: players),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _jerseyControllers) c.dispose();
    for (final c in _nameControllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          CustomPaint(painter: _GridPainter(), size: Size.infinite),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: VTColors.spikeGold,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(child: Text('🏐', style: TextStyle(fontSize: 24))),
                    ),
                    const SizedBox(width: 12),
                    RichText(text: TextSpan(children: [
                      TextSpan(text: 'VOLLEY', style: GoogleFonts.bebasNeue(fontSize: 26, color: VTColors.netWhite, letterSpacing: 2)),
                      TextSpan(text: 'TRACK',  style: GoogleFonts.bebasNeue(fontSize: 26, color: VTColors.blockCyan, letterSpacing: 2)),
                    ])),
                  ]),

                  const SizedBox(height: 32),

                  RichText(text: TextSpan(children: [
                    TextSpan(text: 'TRACK\nUP TO\n', style: GoogleFonts.bebasNeue(fontSize: 52, color: VTColors.netWhite, height: 0.95)),
                    TextSpan(text: '3 PLAYERS.', style: GoogleFonts.bebasNeue(fontSize: 52, color: VTColors.spikeGold, height: 0.95)),
                  ])),

                  const SizedBox(height: 8),
                  Text(
                    'Add 1–3 players below then start tracking.',
                    style: GoogleFonts.inter(fontSize: 13, color: VTColors.textDim, height: 1.6),
                  ),

                  const SizedBox(height: 32),

                  // Player slots
                  for (int i = 0; i < _activePlayerCount; i++) ...[
                    _PlayerSlot(
                      index: i,
                      jerseyController: _jerseyControllers[i],
                      nameController: _nameControllers[i],
                      color: PlayerColors.palette[i],
                      onRemove: i > 0 ? () => setState(() => _activePlayerCount--) : null,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Add player button — max 3
                  if (_activePlayerCount < 3)
                    GestureDetector(
                      onTap: () => setState(() => _activePlayerCount++),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: VTColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: VTColors.blockCyan.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add, color: VTColors.blockCyan, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'ADD PLAYER ${_activePlayerCount + 1}',
                              style: GoogleFonts.bebasNeue(
                                fontSize: 16,
                                letterSpacing: 2,
                                color: VTColors.blockCyan,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _startSession,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: VTColors.spikeGold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text('START TRACKING',
                        style: GoogleFonts.bebasNeue(fontSize: 22, letterSpacing: 2, color: Colors.black)),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerSlot extends StatelessWidget {
  final int index;
  final TextEditingController jerseyController;
  final TextEditingController nameController;
  final Color color;
  final VoidCallback? onRemove;

  const _PlayerSlot({
    required this.index,
    required this.jerseyController,
    required this.nameController,
    required this.color,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VTColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                PlayerColors.labels[index].toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: color,
                ),
              ),
              const Spacer(),
              if (onRemove != null)
                GestureDetector(
                  onTap: onRemove,
                  child: const Icon(Icons.close, color: VTColors.textDim, size: 18),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Jersey number
          TextField(
            controller: jerseyController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            style: GoogleFonts.bebasNeue(fontSize: 28, color: VTColors.netWhite, letterSpacing: 3),
            decoration: InputDecoration(
              prefixText: '#  ',
              prefixStyle: GoogleFonts.bebasNeue(fontSize: 28, color: color),
              hintText: '07',
              hintStyle: GoogleFonts.bebasNeue(fontSize: 28, color: VTColors.muted, letterSpacing: 3),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),

          const SizedBox(height: 10),

          // Player name
          TextField(
            controller: nameController,
            style: GoogleFonts.inter(fontSize: 14, color: VTColors.netWhite),
            decoration: InputDecoration(
              hintText: 'Player name (optional)',
              hintStyle: GoogleFonts.inter(fontSize: 14, color: VTColors.muted),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00D4FF).withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width;  x += 80) canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    for (double y = 0; y < size.height; y += 80) canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
  @override
  bool shouldRepaint(_) => false;
}
