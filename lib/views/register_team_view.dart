import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../models/team_model.dart';
import '../services/database_service.dart';
import 'player_registration_view.dart';

class RegisterTeamView extends StatefulWidget {
  final TeamModel? existingTeam;
  const RegisterTeamView({super.key, this.existingTeam});

  @override
  State<RegisterTeamView> createState() => _RegisterTeamViewState();
}

class _RegisterTeamViewState extends State<RegisterTeamView> {
  final _teamNameController = TextEditingController();
  final DatabaseService _db = DatabaseService();
  List<PlayerRegistration> _players = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingTeam != null) {
      _teamNameController.text = widget.existingTeam!.name;
      _players = List.from(widget.existingTeam!.players);
    }
  }

  @override
  void dispose() {
    _teamNameController.dispose();
    super.dispose();
  }

  Future<void> _addPlayer() async {
    final result = await Navigator.push<PlayerRegistration>(
      context,
      MaterialPageRoute(builder: (_) => const PlayerRegistrationView()),
    );
    if (result != null) {
      setState(() => _players.add(result));
    }
  }

  Future<void> _editPlayer(int index) async {
    final result = await Navigator.push<PlayerRegistration>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PlayerRegistrationView(existing: _players[index]),
      ),
    );
    if (result != null) {
      setState(() => _players[index] = result);
    }
  }

  Future<void> _saveTeam() async {
    final name = _teamNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a team name')),
      );
      return;
    }
    if (_players.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one player')),
      );
      return;
    }

    setState(() => _saving = true);

    final team = TeamModel(
      id:        widget.existingTeam?.id,
      name:      name,
      createdAt: widget.existingTeam?.createdAt ?? DateTime.now(),
      players:   _players,
    );

    await _db.saveTeam(team);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VTColors.courtBlue,
      appBar: AppBar(
        backgroundColor: VTColors.courtMid,
        title: Text(
          widget.existingTeam != null ? 'EDIT TEAM' : 'REGISTER TEAM',
          style: GoogleFonts.bebasNeue(
              fontSize: 22, letterSpacing: 2, color: VTColors.netWhite),
        ),
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
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Team name
                  _Label('Team Name'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _teamNameController,
                    style: GoogleFonts.inter(
                        fontSize: 16, color: VTColors.netWhite),
                    decoration: InputDecoration(
                      hintText: 'e.g. Melbourne Volleyball Club',
                      hintStyle: GoogleFonts.inter(
                          fontSize: 16, color: VTColors.muted),
                    ),
                  ),

                  const SizedBox(height: 28),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Label('Players (${_players.length})'),
                      TextButton.icon(
                        onPressed: _addPlayer,
                        icon: const Icon(Icons.add,
                            color: VTColors.blockCyan, size: 18),
                        label: Text('ADD PLAYER',
                            style: GoogleFonts.bebasNeue(
                                fontSize: 14,
                                letterSpacing: 1.5,
                                color: VTColors.blockCyan)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Players list
                  if (_players.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: VTColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: VTColors.blockCyan.withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.person_add_outlined,
                              color: VTColors.textDim, size: 36),
                          const SizedBox(height: 12),
                          Text('No players yet',
                              style: GoogleFonts.inter(
                                  color: VTColors.textDim, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('Tap Add Player to register players',
                              style: GoogleFonts.inter(
                                  color: VTColors.muted, fontSize: 12)),
                        ],
                      ),
                    )
                  else
                    ...List.generate(_players.length, (i) {
                      final p = _players[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: VTColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: VTColors.blockCyan.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            // Jersey number badge
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: VTColors.spikeGold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: VTColors.spikeGold.withValues(alpha: 0.4)),
                              ),
                              child: Center(
                                child: Text('#${p.jersey}',
                                    style: GoogleFonts.bebasNeue(
                                        fontSize: 18,
                                        color: VTColors.spikeGold)),
                              ),
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: VTColors.netWhite)),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        p.photoPaths.length >= 3
                                            ? Icons.check_circle
                                            : Icons.camera_alt_outlined,
                                        size: 12,
                                        color: p.photoPaths.length >= 3
                                            ? VTColors.pointGreen
                                            : VTColors.spikeGold,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        p.photoPaths.length >= 3
                                            ? '3 photos registered'
                                            : '${p.photoPaths.length}/3 photos',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: p.photoPaths.length >= 3
                                              ? VTColors.pointGreen
                                              : VTColors.spikeGold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Action buttons
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: VTColors.textDim, size: 18),
                              onPressed: () => _editPlayer(i),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: VTColors.dangerRed, size: 18),
                              onPressed: () =>
                                  setState(() => _players.removeAt(i)),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),

          // Save button
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveTeam,
                style: ElevatedButton.styleFrom(
                  backgroundColor: VTColors.spikeGold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text('SAVE TEAM',
                        style: GoogleFonts.bebasNeue(
                            fontSize: 20,
                            letterSpacing: 2,
                            color: Colors.black)),
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
