import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../models/game_event.dart';
import '../models/player_config.dart';
import '../theme.dart';
import 'setup_view.dart';

class MultiStatsView extends StatefulWidget {
  final List<PlayerStats> playerStats;
  final List<PlayerConfig> players;

  const MultiStatsView({
    super.key,
    required this.playerStats,
    required this.players,
  });

  @override
  State<MultiStatsView> createState() => _MultiStatsViewState();
}

class _MultiStatsViewState extends State<MultiStatsView> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VTColors.courtBlue,
      body: Column(
        children: [
          // Header
          Container(
            color: VTColors.courtMid,
            padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 16, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SESSION SUMMARY',
                  style: GoogleFonts.bebasNeue(fontSize: 14, letterSpacing: 3, color: VTColors.textDim)),
                const SizedBox(height: 4),
                Text('${widget.players.length} Players Tracked',
                  style: GoogleFonts.inter(fontSize: 13, color: VTColors.netWhite)),
                const SizedBox(height: 16),

                // Page indicator tabs
                Row(
                  children: widget.players.asMap().entries.map((entry) {
                    final i = entry.key;
                    final p = entry.value;
                    final isActive = _currentPage == i;
                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(i,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive ? p.color.withValues(alpha: 0.2) : VTColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isActive ? p.color : p.color.withValues(alpha: 0.3),
                            width: isActive ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          '#${p.jersey}',
                          style: GoogleFonts.bebasNeue(
                            fontSize: 16,
                            color: isActive ? p.color : VTColors.textDim,
                            height: 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // Swipeable player stats
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentPage = i),
              children: widget.players.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                final s = widget.playerStats[i];
                return _PlayerStatsPage(player: p, stats: s);
              }).toList(),
            ),
          ),

          // Bottom actions
          Container(
            color: VTColors.courtMid,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              children: [
                OutlinedButton(
                  onPressed: _shareAll,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: VTColors.blockCyan.withValues(alpha: 0.4), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.share, color: VTColors.blockCyan, size: 16),
                    const SizedBox(width: 8),
                    Text('SHARE ALL STATS', style: GoogleFonts.bebasNeue(fontSize: 16, letterSpacing: 1.5, color: VTColors.netWhite)),
                  ]),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const SetupView()),
                      (_) => false,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VTColors.spikeGold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text('NEW SESSION',
                      style: GoogleFonts.bebasNeue(fontSize: 18, letterSpacing: 2, color: Colors.black)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _shareAll() {
    final buffer = StringBuffer('🏐 VolleyTrack Session Summary\n\n');
    for (int i = 0; i < widget.players.length; i++) {
      final p = widget.players[i];
      final s = widget.playerStats[i];
      buffer.writeln('#${p.jersey} ${s.name}');
      buffer.writeln('Time: ${s.formattedTime} | Hits: ${s.hits} | Blocks: ${s.blocks} | Pt%: ${s.pointPercentage}%');
      buffer.writeln();
    }
    Share.share(buffer.toString());
  }
}

class _PlayerStatsPage extends StatefulWidget {
  final PlayerConfig player;
  final PlayerStats stats;

  const _PlayerStatsPage({required this.player, required this.stats});

  @override
  State<_PlayerStatsPage> createState() => _PlayerStatsPageState();
}

class _PlayerStatsPageState extends State<_PlayerStatsPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _barController;
  late Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    _barController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _barAnim = CurvedAnimation(parent: _barController, curve: Curves.easeOutCubic);
    Future.delayed(const Duration(milliseconds: 200), () => _barController.forward());
  }

  @override
  void dispose() { _barController.dispose(); super.dispose(); }

  PlayerConfig get p => widget.player;
  PlayerStats  get s => widget.stats;

  @override
  Widget build(BuildContext context) {
    final pct        = s.pointPercentage.toDouble();
    final attackRate = (s.hits   * 3).clamp(0, 100).toDouble();
    final blockRate  = (s.blocks * 5).clamp(0, 100).toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Player header
          Row(children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(color: p.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            RichText(text: TextSpan(children: [
              TextSpan(text: '#', style: GoogleFonts.bebasNeue(fontSize: 18, color: p.color)),
              TextSpan(text: p.jersey, style: GoogleFonts.bebasNeue(fontSize: 44, color: VTColors.netWhite, height: 1)),
            ])),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: GoogleFonts.inter(fontSize: 14, color: VTColors.netWhite, fontWeight: FontWeight.w600)),
              Text('Game time: ${s.formattedTime}', style: GoogleFonts.inter(fontSize: 12, color: VTColors.textDim)),
            ]),
          ]),

          const SizedBox(height: 16),

          // Stat cards
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.4,
            children: [
              _StatCard(label: 'Hits',    value: '${s.hits}',   sub: s.hits == 0 ? 'No attacks' : '${(s.hits / (s.gameTimeSeconds / 60)).toStringAsFixed(1)}/min', color: VTColors.spikeGold, accent: p.color),
              _StatCard(label: 'Blocks',  value: '${s.blocks}', sub: s.blocks == 0 ? 'No blocks' : '${s.blocks} stops', color: VTColors.blockCyan, accent: p.color),
              _StatCard(label: 'Point %', value: '${s.pointPercentage}%', sub: '${s.points} scored', color: VTColors.pointGreen, accent: p.color),
              _StatCard(label: 'Time',    value: s.formattedTime, sub: 'On court', color: VTColors.netWhite, accent: p.color, smallValue: true),
            ],
          ),

          const SizedBox(height: 16),

          // Performance bars
          Text('PERFORMANCE', style: GoogleFonts.bebasNeue(fontSize: 14, letterSpacing: 2, color: VTColors.textDim)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VTColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.color.withValues(alpha: 0.2)),
            ),
            child: Column(children: [
              _PerfBar(label: 'Attack',  pct: attackRate, color: VTColors.spikeGold,  anim: _barAnim),
              const SizedBox(height: 12),
              _PerfBar(label: 'Block',   pct: blockRate,  color: VTColors.blockCyan,  anim: _barAnim),
              const SizedBox(height: 12),
              _PerfBar(label: 'Pt Conv', pct: pct.clamp(0, 100), color: VTColors.pointGreen, anim: _barAnim),
            ]),
          ),

          const SizedBox(height: 16),

          // Event timeline
          if (s.events.isNotEmpty) ...[
            Text('EVENTS', style: GoogleFonts.bebasNeue(fontSize: 14, letterSpacing: 2, color: VTColors.textDim)),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: VTColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.color.withValues(alpha: 0.2)),
              ),
              clipBehavior: Clip.hardEdge,
              child: Column(
                children: s.events.reversed.take(10).map((e) {
                  final m = (e.timestampSeconds ~/ 60).toString().padLeft(2, '0');
                  final sec = (e.timestampSeconds % 60).toString().padLeft(2, '0');
                  final colors = {
                    EventType.hit: VTColors.spikeGold,
                    EventType.block: VTColors.blockCyan,
                    EventType.point: VTColors.pointGreen,
                  };
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: VTColors.blockCyan.withValues(alpha: 0.08)))),
                    child: Row(children: [
                      Container(width: 8, height: 8,
                        decoration: BoxDecoration(color: colors[e.type], shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text('${e.typeEmoji} ${e.typeName}',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: VTColors.netWhite)),
                      const Spacer(),
                      Text('$m:$sec',
                        style: GoogleFonts.jetBrainsMono(fontSize: 11, color: VTColors.textDim)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: VTColors.surface2, borderRadius: BorderRadius.circular(10)),
                        child: Text(e.isAutoDetected ? 'AI' : 'Manual',
                          style: GoogleFonts.inter(fontSize: 9, color: VTColors.textDim)),
                      ),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value, sub;
  final Color color, accent;
  final bool smallValue;

  const _StatCard({
    required this.label, required this.value, required this.sub,
    required this.color, required this.accent, this.smallValue = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
    decoration: BoxDecoration(
      color: VTColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border(top: BorderSide(color: color, width: 3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: VTColors.textDim)),
      const SizedBox(height: 4),
      Text(value, style: GoogleFonts.bebasNeue(fontSize: smallValue ? 26 : 38, color: color, height: 1)),
      const SizedBox(height: 2),
      Text(sub, style: GoogleFonts.inter(fontSize: 9, color: VTColors.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

class _PerfBar extends StatelessWidget {
  final String label;
  final double pct;
  final Color color;
  final Animation<double> anim;

  const _PerfBar({required this.label, required this.pct, required this.color, required this.anim});

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(width: 70, child: Text(label, style: GoogleFonts.inter(fontSize: 11, color: VTColors.textDim))),
    Expanded(child: AnimatedBuilder(
      animation: anim,
      builder: (_, __) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: (pct / 100) * anim.value,
          backgroundColor: VTColors.surface2,
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: 5,
        ),
      ),
    )),
    const SizedBox(width: 8),
    SizedBox(width: 34, child: Text('${pct.toStringAsFixed(0)}%',
      textAlign: TextAlign.right,
      style: GoogleFonts.jetBrainsMono(fontSize: 11, color: color))),
  ]);
}
