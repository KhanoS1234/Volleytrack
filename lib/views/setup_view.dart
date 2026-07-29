import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import 'tracking_view.dart';

class SetupView extends StatefulWidget {
  const SetupView({super.key});
  @override
  State<SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<SetupView> {
  final _jerseyController = TextEditingController();
  final _nameController   = TextEditingController();
  Color _selectedColor    = VTColors.netWhite;

  final List<Color> _jerseyColors = [
    VTColors.netWhite,
    VTColors.spikeGold,
    VTColors.dangerRed,
    VTColors.blockCyan,
    VTColors.pointGreen,
    const Color(0xFF5352ED),
    const Color(0xFF2F3542),
  ];

  void _startSession() {
    final jersey = _jerseyController.text.trim();
    if (jersey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a jersey number first')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackingView(
          jersey: jersey,
          playerName: _nameController.text.trim().isEmpty
              ? 'Player #$jersey'
              : _nameController.text.trim(),
          jerseyColor: _selectedColor,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _jerseyController.dispose();
    _nameController.dispose();
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

                  const SizedBox(height: 40),

                  // Headline
                  RichText(text: TextSpan(children: [
                    TextSpan(text: 'TRACK\nEVERY\n', style: GoogleFonts.bebasNeue(fontSize: 58, color: VTColors.netWhite, height: 0.95)),
                    TextSpan(text: 'SPIKE.',         style: GoogleFonts.bebasNeue(fontSize: 58, color: VTColors.spikeGold, height: 0.95)),
                  ])),
                  const SizedBox(height: 10),
                  Text(
                    'AI-powered player tracking.\nPoint the camera at the court and let it work.',
                    style: GoogleFonts.inter(fontSize: 13, color: VTColors.textDim, height: 1.6),
                  ),

                  const SizedBox(height: 40),

                  // Jersey number
                  _Label('Jersey Number'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _jerseyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    style: GoogleFonts.bebasNeue(fontSize: 32, color: VTColors.netWhite, letterSpacing: 3),
                    decoration: InputDecoration(
                      prefixText: '#  ',
                      prefixStyle: GoogleFonts.bebasNeue(fontSize: 32, color: VTColors.spikeGold),
                      hintText: '07',
                      hintStyle: GoogleFonts.bebasNeue(fontSize: 32, color: VTColors.muted, letterSpacing: 3),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Player name
                  _Label('Player Name (optional)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    style: GoogleFonts.inter(fontSize: 15, color: VTColors.netWhite),
                    decoration: InputDecoration(
                      hintText: 'e.g. Jamie Rodriguez',
                      hintStyle: GoogleFonts.inter(fontSize: 15, color: VTColors.muted),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Colour picker
                  _Label('Jersey Colour'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    children: _jerseyColors.map((color) => GestureDetector(
                      onTap: () => setState(() => _selectedColor = color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _selectedColor == color ? Colors.white : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    )).toList(),
                  ),

                  const SizedBox(height: 48),

                  // Start button
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

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: VTColors.blockCyan),
  );
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
