import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../models/session_model.dart';
import '../models/game_event.dart';
import '../theme.dart';
import 'setup_view.dart';

class StatsView extends StatefulWidget {
  final SessionModel session;
  const StatsView({super.key, required this.session});
  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> with SingleTickerProviderStateMixin {
  late AnimationController _barController;
  late Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    _barController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _barAnim = CurvedAnimation(parent: _barController, curve: Curves.easeOutCubic);
    Future.delayed(const Duration(milliseconds: 300), () => _barController.forward());
  }

  @override
  void dispose() { _barController.dispose(); super.dispose(); }

  SessionModel get s => widget.session;

  void _share() {
    Share.share(
      '🏐 VolleyTrack — #${s.jersey} ${s.playerName}\n'
      'Game time: ${s.formattedDuration}\n'
      'Hits: ${s.hits}  Blocks: ${s.blocks}  Pt%: ${s.pointPercentage.toStringAsFixed(0)}%\n\nTracked with VolleyTrack',
    );
  }

  @override
  Widget build(BuildContext context) {
    final pct         = s.pointPercentage;
    final attackRate  = (s.hits * 3).clamp(0, 100).toDouble();
    final blockRate   = (s.blocks * 5).clamp(0, 100).toDouble();

    return Scaffold(
      backgroundColor: VTColors.courtBlue,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: VTColors.courtMid,
            expandedHeight: 140,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: Row(
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                        RichText(text: TextSpan(children: [
                          TextSpan(text: '#',    style: GoogleFonts.bebasNeue(fontSize: 20, color: VTColors.spikeGold)),
                          TextSpan(text: s.jersey, style: GoogleFonts.bebasNeue(fontSize: 52, color: VTColors.netWhite, height: 1)),
                        ])),
                        Text(s.playerName, style: GoogleFonts.inter(fontSize: 13, color: VTColors.textDim)),
                      ]),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: VTColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: VTColors.blockCyan.withValues(alpha: 0.2)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                          Text(_formatDate(s.date), style: GoogleFonts.inter(fontSize: 11, color: VTColors.textDim)),
                          const SizedBox(height: 2),
                          Text(s.formattedDuration, style: GoogleFonts.jetBrainsMono(fontSize: 18, color: VTColors.blockCyan)),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(delegate: SliverChildListDelegate([

              // Stat cards
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _StatCard(label: 'Hits',      value: '${s.hits}',   sub: s.hits == 0 ? 'No attacks' : '${(s.hits / (s.durationSeconds / 60)).toStringAsFixed(1)}/min', color: VTColors.spikeGold),
                  _StatCard(label: 'Blocks',    value: '${s.blocks}', sub: s.blocks == 0 ? 'No blocks' : '${s.blocks} defensive stops', color: VTColors.blockCyan),
                  _StatCard(label: 'Point %',   value: '${pct.toStringAsFixed(0)}%', sub: '${s.points} points scored', color: VTColors.pointGreen),
                  _StatCard(label: 'Game Time', value: s.formattedDuration, sub: 'Active on court', color: VTColors.netWhite, smallValue: true),
                ],
              ),

              const SizedBox(height: 20),

              // Performance bars
              Text('PERFORMANCE BREAKDOWN', style: GoogleFonts.bebasNeue(fontSize: 16, letterSpacing: 2, color: VTColors.textDim)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: _cardDecor(),
                child: Column(children: [
                  _PerfBar(label: 'Attack Rate', pct: attackRate,        color: VTColors.spikeGold,  animation: _barAnim),
                  const SizedBox(height: 14),
                  _PerfBar(label: 'Block Rate',  pct: blockRate,         color: VTColors.blockCyan,  animation: _barAnim),
                  const SizedBox(height: 14),
                  _PerfBar(label: 'Point Conv.', pct: pct.clamp(0, 100).toDouble(), color: VTColors.pointGreen, animation: _barAnim),
                ]),
              ),

              const SizedBox(height: 20),

              // Timeline
              Text('EVENT TIMELINE', style: GoogleFonts.bebasNeue(fontSize: 16, letterSpacing: 2, color: VTColors.textDim)),
              const SizedBox(height: 12),
              Container(
                decoration: _cardDecor(),
                clipBehavior: Clip.hardEdge,
                child: s.events.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text('No events recorded',
                          style: GoogleFonts.inter(color: VTColors.textDim, fontSize: 13))),
                      )
                    : Column(children: s.events.reversed.map((e) => _EventRow(event: e)).toList()),
              ),

              const SizedBox(height: 20),

              // Buttons
              OutlinedButton(
                onPressed: _share,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: VTColors.blockCyan.withValues(alpha: 0.3), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('SHARE', style: GoogleFonts.bebasNeue(fontSize: 16, letterSpacing: 1.5, color: VTColors.netWhite)),
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
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text('NEW SESSION', style: GoogleFonts.bebasNeue(fontSize: 18, letterSpacing: 2, color: Colors.black)),
                ),
              ),
              const SizedBox(height: 40),
            ])),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]}';
  }

  BoxDecoration _cardDecor() => BoxDecoration(
    color: VTColors.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: VTColors.blockCyan.withValues(alpha: 0.15)),
  );
}

class _StatCard extends StatelessWidget {
  final String label, value, sub;
  final Color color;
  final bool smallValue;
  const _StatCard({required this.label, required this.value, required this.sub, required this.color, this.smallValue = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    decoration: BoxDecoration(
      color: VTColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border(top: BorderSide(color: color, width: 3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: VTColors.textDim)),
      const SizedBox(height: 6),
      Text(value, style: GoogleFonts.bebasNeue(fontSize: smallValue ? 30 : 44, color: color, height: 1)),
      const SizedBox(height: 4),
      Text(sub, style: GoogleFonts.inter(fontSize: 10, color: VTColors.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

class _PerfBar extends StatelessWidget {
  final String label;
  final double pct;
  final Color color;
  final Animation<double> animation;
  const _PerfBar({required this.label, required this.pct, required this.color, required this.animation});

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(width: 90, child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: VTColors.textDim))),
    Expanded(
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, __) => ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (pct / 100) * animation.value,
            backgroundColor: VTColors.surface2,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ),
    ),
    const SizedBox(width: 10),
    SizedBox(width: 36, child: Text('${pct.toStringAsFixed(0)}%', textAlign: TextAlign.right, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: color))),
  ]);
}

class _EventRow extends StatelessWidget {
  final GameEvent event;
  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final colors = {EventType.hit: VTColors.spikeGold, EventType.block: VTColors.blockCyan, EventType.point: VTColors.pointGreen};
    final m = (event.timestampSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (event.timestampSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: VTColors.blockCyan.withValues(alpha: 0.1)))),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[event.type], shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${event.typeEmoji} ${event.typeName}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: VTColors.netWhite)),
          Text('$m:$s into session', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: VTColors.textDim)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: VTColors.surface2, borderRadius: BorderRadius.circular(20)),
          child: Text(event.isAutoDetected ? 'AI' : 'Manual', style: GoogleFonts.inter(fontSize: 10, color: VTColors.textDim)),
        ),
      ]),
    );
  }
}
