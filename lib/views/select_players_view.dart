import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../models/team_model.dart';
import '../models/player_config.dart';
import 'tracking_view.dart';

class SelectPlayersView extends StatefulWidget {
  final TeamModel team;
  const SelectPlayersView({super.key, required this.team});

  @override
  State<SelectPlayersView> createState() => _SelectPlayersViewState();
}

class _SelectPlayersViewState extends State<SelectPlayersView> {
  final Set<int> _selectedIndices = {};

  void _togglePlayer(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        if (_selectedIndices.length < 3) {
          _selectedIndices.add(index);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Maximum 3 players can be tracked at once')),
          );
        }
      }
    });
  }

  void _startSession() {
    if (_selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one player')),
      );
      return;
    }

    final selectedPlayers = _selectedIndices.toList()
      ..sort();

    final players = selectedPlayers.asMap().entries.map((entry) {
      final player = widget.team.players[entry.value];
      return PlayerConfig(
        jersey:     player.jersey,
        name:       player.name,
        color:      PlayerColors.palette[entry.key],
        photoPaths: player.photoPaths,
      );
    }).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackingView(players: players),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VTColors.courtBlue,
      appBar: AppBar(
        backgroundColor: VTColors.courtMid,
        title: Text(
          widget.team.name.toUpperCase(),
          style: GoogleFonts.bebasNeue(
              fontSize: 20, letterSpacing: 2, color: VTColors.netWhite),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VTColors.netWhite),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Info bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            color: VTColors.courtMid,
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: VTColors.textDim, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Select up to 3 players to track in this session',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: VTColors.textDim),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: VTColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: VTColors.blockCyan.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${_selectedIndices.length}/3',
                    style: GoogleFonts.bebasNeue(
                        fontSize: 16, color: VTColors.blockCyan),
                  ),
                ),
              ],
            ),
          ),

          // Players list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: widget.team.players.length,
              itemBuilder: (_, i) {
                final player    = widget.team.players[i];
                final selected  = _selectedIndices.contains(i);
                final slotIndex = _selectedIndices.toList()..sort();
                final slot      = slotIndex.indexOf(i);
                final color     = selected
                    ? PlayerColors.palette[slot]
                    : VTColors.textDim;

                return GestureDetector(
                  onTap: () => _togglePlayer(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: selected
                          ? color.withValues(alpha: 0.1)
                          : VTColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? color
                            : VTColors.blockCyan.withValues(alpha: 0.15),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Selection indicator
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: selected
                                ? color
                                : VTColors.surface2,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? color
                                  : VTColors.blockCyan.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Center(
                            child: selected
                                ? Text(
                                    '${slot + 1}',
                                    style: GoogleFonts.bebasNeue(
                                        fontSize: 16,
                                        color: Colors.black),
                                  )
                                : const Icon(Icons.add,
                                    color: VTColors.textDim, size: 16),
                          ),
                        ),

                        const SizedBox(width: 14),

                        // Jersey badge
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: selected
                                ? color.withValues(alpha: 0.2)
                                : VTColors.spikeGold.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? color.withValues(alpha: 0.5)
                                  : VTColors.spikeGold.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '#${player.jersey}',
                              style: GoogleFonts.bebasNeue(
                                  fontSize: 16,
                                  color: selected
                                      ? color
                                      : VTColors.spikeGold),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Player info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                player.name,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? VTColors.netWhite
                                      : VTColors.netWhite,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    player.photoPaths.length >= 3
                                        ? Icons.check_circle
                                        : Icons.warning_amber,
                                    size: 11,
                                    color: player.photoPaths.length >= 3
                                        ? VTColors.pointGreen
                                        : VTColors.spikeGold,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    player.photoPaths.length >= 3
                                        ? '3 photos registered'
                                        : 'Photos incomplete',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: player.photoPaths.length >= 3
                                          ? VTColors.pointGreen
                                          : VTColors.spikeGold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Start session button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _selectedIndices.isNotEmpty ? _startSession : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedIndices.isNotEmpty
                      ? VTColors.spikeGold
                      : VTColors.muted,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  _selectedIndices.isEmpty
                      ? 'SELECT PLAYERS TO START'
                      : 'START SESSION WITH ${_selectedIndices.length} PLAYER${_selectedIndices.length == 1 ? '' : 'S'}',
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
