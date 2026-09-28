import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/workout_history_provider.dart';
import '../../../core/signal_processing/recovery_engine.dart';
import '../../../core/widgets/glass_container.dart';

class RecoveryScreen extends ConsumerWidget {
  const RecoveryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(workoutHistoryProvider);
    final sessions = history.sessions;
    final status = RecoveryEngine.analyze(sessions);
    final bars = RecoveryEngine.weeklyBars(sessions);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RECOVERY',
                      style: GoogleFonts.outfit(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3)),
                  Text('Load Management',
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          if (status == null) ...[
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timeline_rounded,
                        color: Colors.white24, size: 64),
                    const SizedBox(height: 16),
                    Text('Not enough data',
                        style: GoogleFonts.outfit(
                            color: Colors.white38, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Complete a few sessions to\nunlock recovery analysis',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                            color: Colors.white24, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ] else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: _ReadinessGauge(status: status),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _AcwrCard(status: status),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _WeeklyLoadChart(bars: bars, status: status),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _MetricTile(
                        label: 'REST DAYS',
                        value: status.restDays.toString(),
                        unit: 'days',
                        icon: Icons.bedtime_outlined,
                        color: status.restDays >= 1 && status.restDays <= 2
                            ? const Color(0xFF00E5FF)
                            : Colors.white54,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricTile(
                        label: 'ACUTE LOAD',
                        value: status.acuteLoad.toStringAsFixed(1),
                        unit: 'ATU',
                        icon: Icons.bolt_rounded,
                        color: const Color(0xFFFF8C00),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricTile(
                        label: 'CHRONIC LOAD',
                        value: status.chronicLoad.toStringAsFixed(1),
                        unit: 'ATU',
                        icon: Icons.show_chart_rounded,
                        color: const Color(0xFF3EA6FF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _AdviceCard(status: status),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Text(
                  'ACWR computed via EWMA (Williams et al. 2017). Risk zones per Hulin et al. 2016. '
                  'ATU = training reps × relative load.',
                  style: GoogleFonts.outfit(
                      color: Colors.white24,
                      fontSize: 10,
                      fontStyle: FontStyle.italic),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
class _ReadinessGauge extends StatelessWidget {
  final RecoveryStatus status;
  const _ReadinessGauge({required this.status});

  Color get _color {
    final s = status.readinessScore;
    if (s >= 80) return const Color(0xFF00E5FF);
    if (s >= 60) return const Color(0xFF00FF88);
    if (s >= 40) return const Color(0xFFFFD700);
    if (s >= 20) return const Color(0xFFFF8C00);
    return const Color(0xFFFF3333);
  }

  @override
  Widget build(BuildContext context) {
    final score = status.readinessScore;
    return GlassContainer(
      blur: 20,
      opacity: 0.08,
      borderColor: _color.withOpacity(0.25),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // Arc gauge
          SizedBox(
            width: 110,
            height: 110,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _ArcGaugePainter(
                    value: score / 100.0,
                    color: _color,
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        score.toStringAsFixed(0),
                        style: GoogleFonts.outfit(
                            color: _color,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            height: 1),
                      ),
                      Text('/100',
                          style: GoogleFonts.outfit(
                              color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Readiness Score',
                    style: GoogleFonts.outfit(
                        color: Colors.white54, fontSize: 11, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(status.readinessLabel,
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                // Readiness bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: score / 100,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(_color),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(status.zoneAdvice,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                        color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _AcwrCard extends StatelessWidget {
  final RecoveryStatus status;
  const _AcwrCard({required this.status});

  Color _zoneColor(AcwrZone zone) {
    switch (zone) {
      case AcwrZone.undertrained: return const Color(0xFF3EA6FF);
      case AcwrZone.fresh:        return const Color(0xFF00FF88);
      case AcwrZone.optimal:      return const Color(0xFF00E5FF);
      case AcwrZone.caution:      return const Color(0xFFFFD700);
      case AcwrZone.danger:       return const Color(0xFFFF3333);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _zoneColor(status.zone);
    return GlassContainer(
      blur: 20,
      opacity: 0.08,
      borderColor: color.withOpacity(0.2),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined, color: color, size: 18),
              const SizedBox(width: 8),
              Text('ACWR — Acute:Chronic Workload Ratio',
                  style: GoogleFonts.outfit(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(status.acwr.toStringAsFixed(2),
                  style: GoogleFonts.outfit(
                      color: color,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      height: 1)),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Text(status.zoneLabel,
                      style: GoogleFonts.outfit(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Zone ruler
          _AcwrRuler(acwr: status.acwr, zoneColor: color),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0.0', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 9)),
              Text('0.8', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 9)),
              Text('1.0', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 9)),
              Text('1.3', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 9)),
              Text('1.5', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 9)),
              Text('2.0+', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AcwrRuler extends StatelessWidget {
  final double acwr;
  final Color zoneColor;
  const _AcwrRuler({required this.acwr, required this.zoneColor});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final totalWidth = constraints.maxWidth;
      // Map acwr 0–2 → 0–totalWidth
      final markerX =
          ((acwr / 2.0).clamp(0.0, 1.0) * totalWidth).clamp(0.0, totalWidth);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          // Gradient track
          Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(colors: [
                Color(0xFF3EA6FF), // Under-trained
                Color(0xFF00FF88), // Fresh
                Color(0xFF00E5FF), // Optimal
                Color(0xFFFFD700), // Caution
                Color(0xFFFF3333), // Danger
              ]),
            ),
          ),
          // Marker
          Positioned(
            left: markerX - 6,
            top: -4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: zoneColor,
                border: Border.all(color: Colors.black, width: 2),
                boxShadow: [
                  BoxShadow(
                      color: zoneColor.withOpacity(0.6),
                      blurRadius: 8)
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}
class _WeeklyLoadChart extends StatelessWidget {
  final List<WeeklyLoadBar> bars;
  final RecoveryStatus status;
  const _WeeklyLoadChart({required this.bars, required this.status});

  @override
  Widget build(BuildContext context) {
    final maxLoad = bars.map((b) => b.load).fold(0.0, (a, b) => a > b ? a : b);
    return GlassContainer(
      blur: 20,
      opacity: 0.08,
      borderColor: Colors.white.withOpacity(0.07),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  color: AppTheme.primary, size: 16),
              const SizedBox(width: 8),
              Text('7-DAY LOAD DISTRIBUTION',
                  style: GoogleFonts.outfit(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 140,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxLoad > 0 ? maxLoad * 1.3 : 10),
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= bars.length) {
                          return const SizedBox.shrink();
                        }
                        final bar = bars[idx];
                        return Text(
                          bar.dayLabel,
                          style: GoogleFonts.outfit(
                            color: bar.isToday
                                ? AppTheme.primary
                                : Colors.white38,
                            fontSize: 10,
                            fontWeight: bar.isToday
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: bars.asMap().entries.map((e) {
                  final i   = e.key;
                  final bar = e.value;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: bar.load,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                        gradient: bar.isToday
                            ? const LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter)
                            : null,
                        color: bar.isToday
                            ? null
                            : (bar.load > 0
                                ? AppTheme.primary.withOpacity(0.4)
                                : Colors.white10),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      blur: 15,
      opacity: 0.08,
      borderColor: color.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: GoogleFonts.outfit(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
          ),
          Text(unit,
              style: GoogleFonts.outfit(
                  color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.outfit(
                  color: Colors.white24,
                  fontSize: 9,
                  letterSpacing: 1)),
        ],
      ),
    );
  }
}
class _AdviceCard extends StatelessWidget {
  final RecoveryStatus status;
  const _AdviceCard({required this.status});

  Color get _zoneColor {
    switch (status.zone) {
      case AcwrZone.undertrained: return const Color(0xFF3EA6FF);
      case AcwrZone.fresh:        return const Color(0xFF00FF88);
      case AcwrZone.optimal:      return const Color(0xFF00E5FF);
      case AcwrZone.caution:      return const Color(0xFFFFD700);
      case AcwrZone.danger:       return const Color(0xFFFF3333);
    }
  }

  IconData get _icon {
    switch (status.zone) {
      case AcwrZone.undertrained: return Icons.trending_up_rounded;
      case AcwrZone.fresh:        return Icons.check_circle_outline_rounded;
      case AcwrZone.optimal:      return Icons.local_fire_department_rounded;
      case AcwrZone.caution:      return Icons.warning_amber_rounded;
      case AcwrZone.danger:       return Icons.dangerous_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _zoneColor;
    return GlassContainer(
      blur: 20,
      opacity: 0.08,
      borderColor: color.withOpacity(0.25),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Iron Eye Recommendation',
                    style: GoogleFonts.outfit(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
                const SizedBox(height: 6),
                Text(status.zoneAdvice,
                    style: GoogleFonts.outfit(
                        color: Colors.white70, fontSize: 13, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _ArcGaugePainter extends CustomPainter {
  final double value; // 0.0 – 1.0
  final Color color;
  const _ArcGaugePainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8;
    const startAngle = 2.35; // ~135°
    const sweepTotal = 5.65; // ~324°

    // Background track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      Paint()
        ..color = Colors.white10
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Value arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal * value,
      false,
      Paint()
        ..color = color
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_ArcGaugePainter old) =>
      old.value != value || old.color != color;
}