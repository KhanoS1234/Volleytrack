import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../models/team_model.dart';
import '../services/database_service.dart';
import 'register_team_view.dart';
import 'select_players_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final DatabaseService _db = DatabaseService();
  List<TeamModel> _teams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final teams = await _db.getAllTeams();
    setState(() {
      _teams   = teams;
      _loading = false;
    });
  }

  Future<void> _deleteTeam(TeamModel team) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VTColors.surface,
        title: Text('Delete ${team.name}?',
            style: GoogleFonts.inter(color: VTColors.netWhite)),
        content: Text('This cannot be undone.',
            style: GoogleFonts.inter(color: VTColors.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: VTColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete',
                style: GoogleFonts.inter(color: VTColors.dangerRed)),
          ),
        ],
      ),
    );

    if (confirm == true && team.id != null) {
      await _db.deleteTeam(team.id!);
      _loadTeams();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          CustomPaint(painter: _GridPainter(), size: Size.infinite),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
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
                          child: const Center(
                              child: Text('🏐',
                                  style: TextStyle(fontSize: 24))),
                        ),
                        const SizedBox(width: 12),
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(
                                text: 'VOLLEY',
                                style: GoogleFonts.bebasNeue(
                                    fontSize: 26,
                                    color: VTColors.netWhite,
                                    letterSpacing: 2)),
                            TextSpan(
                                text: 'TRACK',
                                style: GoogleFonts.bebasNeue(
                                    fontSize: 26,
                                    color: VTColors.blockCyan,
                                    letterSpacing: 2)),
                          ]),
                        ),
                      ]),

                      const SizedBox(height: 32),

                      Text(
                        'TEAMS',
                        style: GoogleFonts.bebasNeue(
                          fontSize: 42,
                          color: VTColors.netWhite,
                          letterSpacing: 1,
                          height: 1,
                        ),
                      ),
                      Text(
                        'Register a new team or select an existing one.',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: VTColors.textDim,
                            height: 1.5),
                      ),

                      const SizedBox(height: 24),

                      // Register new team button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const RegisterTeamView()),
                            );
                            _loadTeams();
                          },
                          icon: const Icon(Icons.add, color: Colors.black),
                          label: Text('REGISTER NEW TEAM',
                              style: GoogleFonts.bebasNeue(
                                  fontSize: 18,
                                  letterSpacing: 2,
                                  color: Colors.black)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: VTColors.spikeGold,
                            foregroundColor: Colors.black,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Text(
                        'EXISTING TEAMS',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: VTColors.blockCyan,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Teams list
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: VTColors.blockCyan))
                      : _teams.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20),
                              itemCount: _teams.length,
                              itemBuilder: (_, i) =>
                                  _TeamCard(
                                    team: _teams[i],
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              SelectPlayersView(
                                                  team: _teams[i]),
                                        ),
                                      );
                                    },
                                    onEdit: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              RegisterTeamView(
                                                  existingTeam:
                                                      _teams[i]),
                                        ),
                                      );
                                      _loadTeams();
                                    },
                                    onDelete: () => _deleteTeam(_teams[i]),
                                  ),
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🏐',
              style: const TextStyle(fontSize: 48).copyWith(
                  color: VTColors.textDim.withValues(alpha: 0.5))),
          const SizedBox(height: 16),
          Text('No teams yet',
              style: GoogleFonts.bebasNeue(
                  fontSize: 24, color: VTColors.textDim, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text('Register your first team above',
              style:
                  GoogleFonts.inter(fontSize: 13, color: VTColors.textDim)),
        ],
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final TeamModel team;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TeamCard({
    required this.team,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: VTColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: VTColors.blockCyan.withValues(alpha: 0.2), width: 1),
        ),
        child: Row(
          children: [
            // Team icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: VTColors.spikeGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: VTColors.spikeGold.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text('🏐',
                    style: const TextStyle(fontSize: 22)),
              ),
            ),

            const SizedBox(width: 14),

            // Team info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.name,
                    style: GoogleFonts.bebasNeue(
                        fontSize: 20,
                        color: VTColors.netWhite,
                        letterSpacing: 1),
                  ),
                  Text(
                    '${team.players.length} player${team.players.length == 1 ? '' : 's'} registered',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: VTColors.textDim),
                  ),
                  const SizedBox(height: 4),
                  // Player jersey numbers preview
                  Wrap(
                    spacing: 4,
                    children: team.players.take(6).map((p) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: VTColors.surface2,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: VTColors.blockCyan.withValues(alpha: 0.2)),
                      ),
                      child: Text('#${p.jersey}',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: VTColors.blockCyan)),
                    )).toList(),
                  ),
                ],
              ),
            ),

            // Action buttons
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: VTColors.textDim, size: 20),
                  onPressed: onEdit,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(height: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: VTColors.dangerRed, size: 20),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
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
    for (double x = 0; x < size.width; x += 80) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 80) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
