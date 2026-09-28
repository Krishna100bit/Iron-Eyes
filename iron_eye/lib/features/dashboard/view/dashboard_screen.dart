import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/providers/workout_history_provider.dart';
import '../../../core/models/workout_session.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../main.dart';
import '../../camera_workout/view/workout_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final history = ref.watch(workoutHistoryProvider);

    final name = profile?.name ?? 'Athlete';
    final streak = history.streak;
    final todaysReps = history.todaysReps;
    final weeklyActivity = history.weeklyActivity;
    final recentSessions = history.recentSessions;

    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'GOOD MORNING' : hour < 17 ? 'GOOD AFTERNOON' : 'GOOD EVENING';
    final today = DateTime.now().weekday - 1; // 0 = Mon

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Subtle green radial glow at top-left
          Positioned(
            top: -100,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppTheme.primary.withOpacity(0.07), Colors.transparent],
                ),
              ),
            ),
          ),

          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(greeting,
                                style: GoogleFonts.outfit(
                                    color: AppTheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.5)),
                            Text('$name 👋',
                                style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.surface,
                            border: Border.all(
                                color: AppTheme.primary.withOpacity(0.5), width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'A',
                              style: GoogleFonts.outfit(
                                  color: AppTheme.primary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(
                      children: [
                        const Icon(Icons.local_fire_department_rounded,
                            color: AppTheme.primary, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          streak > 0 ? '$streak week streak' : '0 week streak',
                          style: GoogleFonts.outfit(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (i) {
                        final now = DateTime.now();
                        final day = DateTime(now.year, now.month, now.day)
                            .subtract(Duration(days: (now.weekday - 1 - i + 7) % 7));
                        final hadWorkout = history.sessions.any((s) =>
                            DateTime(s.date.year, s.date.month, s.date.day) == day);
                        final isToday = i == today;
                        return GestureDetector(
                          onTap: () => _showDaySummary(context, day, history.sessions),
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hadWorkout
                                  ? AppTheme.primary
                                  : isToday
                                      ? Colors.white.withValues(alpha: 0.1)
                                      : Colors.transparent,
                              border: Border.all(
                                color: isToday && !hadWorkout
                                    ? Colors.white54
                                    : hadWorkout
                                        ? AppTheme.primary
                                        : Colors.white.withValues(alpha: 0.12),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                ['S', 'M', 'T', 'W', 'T', 'F', 'S'][i],
                                style: GoogleFonts.outfit(
                                  color: hadWorkout
                                      ? Colors.black
                                      : isToday ? Colors.white : Colors.white38,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Row(
                      children: [
                        Expanded(child: _StatCard(
                          emoji: '🔥',
                          label: 'STREAK',
                          value: streak > 0 ? '$streak' : '0',
                          unit: 'days',
                          valueColor: AppTheme.primary,
                          borderColor: AppTheme.primary.withOpacity(0.2),
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: _StatCard(
                          emoji: '⚡',
                          label: 'TODAY',
                          value: '$todaysReps',
                          unit: 'reps',
                          valueColor: Colors.white,
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: _StatCard(
                          emoji: '⭐',
                          label: 'FORM',
                          value: history.avgFormGrade,
                          unit: 'avg',
                          valueColor: const Color(0xFF3EA6FF),
                        )),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      children: [
                        Expanded(child: _StatCard(
                          emoji: '💪',
                          label: 'MAX E1RM',
                          value: history.maxE1rm > 0 ? history.maxE1rm.toStringAsFixed(1) : '—',
                          unit: 'kg',
                          valueColor: const Color(0xFFC77DFF),
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: _StatCard(
                          emoji: '📦',
                          label: 'VOLUME',
                          value: history.totalVolume > 0 ? (history.totalVolume >= 1000 ? '${(history.totalVolume/1000).toStringAsFixed(1)}k' : history.totalVolume.toStringAsFixed(0)) : '—',
                          unit: 'kg',
                          valueColor: const Color(0xFF00E5FF),
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: _StatCard(
                          emoji: '🏋️',
                          label: 'SESSIONS',
                          value: '${history.totalWorkouts}',
                          unit: 'total',
                          valueColor: Colors.white70,
                        )),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.primary.withOpacity(0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.15),
                            blurRadius: 24,
                            spreadRadius: 0,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => ref.read(navigationIndexProvider.notifier).state = 1,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.play_arrow_rounded,
                                    color: AppTheme.primary, size: 24),
                                const SizedBox(width: 8),
                                Text('Start Workout',
                                    style: GoogleFonts.outfit(
                                        color: AppTheme.primary,
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Weekly Activity',
                                style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600)),
                            Text(
                              'this week · ${history.thisWeekReps} reps',
                              style: GoogleFonts.outfit(
                                  color: AppTheme.primary, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GlassContainer(
                          blur: 12,
                          opacity: 0.06,
                          borderColor: Colors.white.withOpacity(0.07),
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                          child: SizedBox(
                            height: 160,
                            child: weeklyActivity.every((v) => v == 0)
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.show_chart_rounded,
                                          color: Colors.white12, size: 36),
                                      const SizedBox(height: 8),
                                      Text('No workouts this week yet',
                                          style: GoogleFonts.outfit(
                                              color: Colors.white24, fontSize: 13)),
                                    ],
                                  )
                                : BarChart(
                                    BarChartData(
                                      alignment: BarChartAlignment.spaceAround,
                                      maxY: (weeklyActivity
                                                  .reduce((a, b) => a > b ? a : b) *
                                              1.4)
                                          .clamp(10, double.infinity),
                                      barTouchData: BarTouchData(enabled: false),
                                      titlesData: FlTitlesData(
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            getTitlesWidget: (v, _) {
                                              final labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                                              final i = v.toInt();
                                              if (i < 0 || i >= labels.length) {
                                                return const SizedBox();
                                              }
                                              return Text(labels[i],
                                                  style: GoogleFonts.outfit(
                                                      color: i == today
                                                          ? AppTheme.primary
                                                          : Colors.white24,
                                                      fontSize: 11,
                                                      fontWeight: i == today
                                                          ? FontWeight.bold
                                                          : FontWeight.normal));
                                            },
                                          ),
                                        ),
                                        leftTitles: const AxisTitles(
                                            sideTitles: SideTitles(showTitles: false)),
                                        topTitles: const AxisTitles(
                                            sideTitles: SideTitles(showTitles: false)),
                                        rightTitles: const AxisTitles(
                                            sideTitles: SideTitles(showTitles: false)),
                                      ),
                                      gridData: FlGridData(
                                        show: true,
                                        drawHorizontalLine: true,
                                        drawVerticalLine: false,
                                        getDrawingHorizontalLine: (_) =>
                                            const FlLine(color: Colors.white10, strokeWidth: 0.5),
                                      ),
                                      borderData: FlBorderData(show: false),
                                      barGroups: weeklyActivity.asMap().entries.map((e) {
                                        final isToday = e.key == today;
                                        return BarChartGroupData(
                                          x: e.key,
                                          barRods: [
                                            BarChartRodData(
                                              toY: e.value,
                                              gradient: isToday
                                                  ? const LinearGradient(
                                                      colors: [
                                                        Color(0xFF00E5FF),
                                                        Color(0xFF00B0FF)
                                                      ],
                                                      begin: Alignment.bottomCenter,
                                                      end: Alignment.topCenter,
                                                    )
                                                  : null,
                                              color: isToday
                                                  ? null
                                                  : AppTheme.primary.withOpacity(0.3),
                                              width: 18,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Workouts',
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600)),
                        Text('See all',
                            style: GoogleFonts.outfit(
                                color: AppTheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),

                recentSessions.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          child: GlassContainer(
                            blur: 10,
                            opacity: 0.05,
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              children: [
                                const Icon(Icons.fitness_center,
                                    color: Colors.white12, size: 36),
                                const SizedBox(height: 10),
                                Text('No workouts yet',
                                    style: GoogleFonts.outfit(
                                        color: Colors.white38, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text('Complete your first session to see it here',
                                    style: GoogleFonts.outfit(
                                        color: Colors.white24, fontSize: 11),
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Padding(
                            padding:
                                EdgeInsets.fromLTRB(20, index == 0 ? 12 : 6, 20, 0),
                            child: _SessionCard(session: recentSessions[index]),
                          ),
                          childCount: recentSessions.length,
                        ),
                      ),

                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        ],
      ),
    );
  }
  void _showDaySummary(BuildContext context, DateTime date, List<WorkoutSession> sessions) {
    final daySessions = sessions.where((s) => 
        DateTime(s.date.year, s.date.month, s.date.day) == date).toList();

    final dateLabel = '${date.day}/${date.month}/${date.year}';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Workouts on $dateLabel',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (daySessions.isEmpty)
                Text('No workouts recorded on this day.', style: GoogleFonts.outfit(color: Colors.white54))
              else
                ...daySessions.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SessionCard(session: s),
                )),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final WorkoutSession session;
  const _SessionCard({required this.session});

  Color _gradeColor(String g) {
    if (g.startsWith('A')) return const Color(0xFF00E5FF);
    if (g.startsWith('B')) return const Color(0xFF3EA6FF);
    if (g.startsWith('C')) return const Color(0xFFFFD700);
    if (g.startsWith('D')) return const Color(0xFFFF8C00);
    return const Color(0xFFFF3333);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        return Dismissible(
          key: Key(session.id.toString()),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          confirmDismiss: (_) async {
            return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A1A),
                title: Text('Delete Session?', style: GoogleFonts.outfit(color: Colors.white)),
                content: Text('Remove this session and all its reps?',
                    style: GoogleFonts.outfit(color: Colors.white70)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
                ],
              ),
            );
          },
          onDismissed: (_) {
            ref.read(workoutHistoryProvider.notifier).deleteSession(session.id.toString());
          },
          child: GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => SessionSummarySheet(session: session),
              );
            },
            child: GlassContainer(
              blur: 10,
              opacity: 0.07,
              borderColor: Colors.white.withValues(alpha: 0.07),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(Icons.fitness_center, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session.exercise,
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        Text(
                          '${session.totalReps} reps'
                          '${session.loadKg != null ? '  ·  ${session.loadKg} kg' : ''}'
                          '${session.targetRpe != null ? '  ·  RPE ${session.targetRpe}' : ''}'
                          '  ·  ${session.formattedDuration}',
                          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _gradeColor(session.avgFormGrade).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _gradeColor(session.avgFormGrade).withValues(alpha: 0.3)),
                        ),
                        child: Text(session.avgFormGrade,
                            style: GoogleFonts.outfit(
                                color: _gradeColor(session.avgFormGrade),
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 4),
                      Text(session.timeAgo,
                          style: GoogleFonts.outfit(color: Colors.white24, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
class _StatCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final String unit;
  final Color valueColor;
  final Color? borderColor;

  const _StatCard({
    required this.emoji,
    required this.label,
    required this.value,
    required this.unit,
    required this.valueColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      blur: 15,
      opacity: 0.08,
      borderColor: borderColor ?? Colors.white.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$emoji  $label',
              style: GoogleFonts.outfit(
                  color: Colors.white38, fontSize: 9, letterSpacing: 1)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: GoogleFonts.outfit(
                    color: valueColor,
                    fontSize: 30,
                    fontWeight: FontWeight.bold)),
          ),
          Text(unit,
              style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }
}