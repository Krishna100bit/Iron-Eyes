import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/workout_session.dart';
import '../database/dao/athlete_dao.dart';
import '../database/dao/session_dao.dart';
import '../database/dao/set_dao.dart';
import '../database/dao/rep_dao.dart';

// ── State ─────────────────────────────────────────────────────────────────────
class WorkoutHistoryState {
  final List<WorkoutSession> sessions;
  final int totalWorkouts;
  final int totalReps;
  final int streak;
  final int thisWeekWorkouts;
  final int thisWeekReps;
  final List<double> weeklyActivity; // 7 values Mon-Sun
  final int todaysReps;

  const WorkoutHistoryState({
    this.sessions = const [],
    this.totalWorkouts = 0,
    this.totalReps = 0,
    this.streak = 0,
    this.thisWeekWorkouts = 0,
    this.thisWeekReps = 0,
    this.weeklyActivity = const [0, 0, 0, 0, 0, 0, 0],
    this.todaysReps = 0,
  });

  List<WorkoutSession> get recentSessions =>
      sessions.length > 10 ? sessions.sublist(0, 10) : sessions;

  String get avgFormGrade {
    if (sessions.isEmpty) return '—';
    final avg = sessions
            .where((s) => s.avgFormScore > 0)
            .fold<int>(0, (s, e) => s + e.avgFormScore) /
        sessions.where((s) => s.avgFormScore > 0).length.clamp(1, 9999);
    if (avg >= 90) return 'A';
    if (avg >= 80) return 'B';
    if (avg >= 70) return 'C';
    if (avg >= 60) return 'D';
    return 'F';
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────
class WorkoutHistoryNotifier extends StateNotifier<WorkoutHistoryState> {
  final _athleteDao = AthleteDao();
  final _sessionDao = SessionDao();
  final _setDao = SetDao();
  final _repDao = RepDao();

  WorkoutHistoryNotifier() : super(const WorkoutHistoryState()) {
    _refresh();
  }

  Future<void> _refresh() async {
    final athleteRow = await _athleteDao.getFirst();
    if (athleteRow == null) return;
    final athleteId = athleteRow['id'] as int;
    await _loadFromDb(athleteId);
  }

  Future<void> _loadFromDb(int athleteId) async {
    // 1. Session summaries list
    final summaryRows = await _sessionDao.getSessionSummaries(athleteId);
    final sessions = summaryRows.map(_rowToSession).toList();

    // 2. Lifetime totals
    final totals = await _sessionDao.getLifetimeTotals(athleteId);
    final totalWorkouts = ((totals['total_workouts'] as num?)?.toInt()) ?? 0;
    final totalReps = ((totals['total_reps'] as num?)?.toInt()) ?? 0;

    // 3. Today's reps
    final todaysReps = await _sessionDao.getTodayRepCount(athleteId);

    // 4. Weekly activity (Mon=0 ... Sun=6 in weekday-1 convention)
    final weekMap = await _sessionDao.getWeeklyRepCounts(athleteId);
    final now = DateTime.now();
    final weeklyActivity = List<double>.generate(7, (i) {
      final day = now.subtract(Duration(days: now.weekday - 1 - i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      return (weekMap[key] ?? 0).toDouble();
    });

    // 5. This-week totals
    final thisWeekReps = weeklyActivity.fold<double>(0, (a, b) => a + b).toInt();
    final thisWeekWorkouts = weekMap.length;

    // 6. Streak (consecutive days worked out up to today)
    final dates = await _sessionDao.getDistinctDates(athleteId);
    int streak = 0;
    if (dates.isNotEmpty) {
      final today = DateTime.now();
      DateTime check = DateTime(today.year, today.month, today.day);
      for (final dateStr in dates) {
        final d = DateTime.parse(dateStr);
        if (d.isAtSameMomentAs(check) ||
            d.isAtSameMomentAs(check.subtract(const Duration(days: 1)))) {
          streak++;
          check = check.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }
    }

    state = WorkoutHistoryState(
      sessions: sessions,
      totalWorkouts: totalWorkouts,
      totalReps: totalReps,
      streak: streak,
      thisWeekWorkouts: thisWeekWorkouts,
      thisWeekReps: thisWeekReps,
      weeklyActivity: weeklyActivity,
      todaysReps: todaysReps,
    );
  }

  WorkoutSession _rowToSession(Map<String, dynamic> row) {
    return WorkoutSession(
      id: row['id'].toString(),
      exercise: row['exercise'] as String? ?? '',
      exerciseType: 'Bodyweight',
      date: DateTime.parse(row['date'] as String),
      totalReps: (row['total_reps'] as int?) ?? 0,
      avgFormScore: ((row['avg_form_score'] as num?)?.toInt()) ?? 0,
      durationSeconds: ((row['duration_seconds'] as num?)?.toInt()) ?? 0,
      loadKg: (row['load_kg'] as num?)?.toDouble(),
      reps: const [],
    );
  }

  /// Called after a session finishes — persists all sets+reps to SQLite
  Future<void> addSession(WorkoutSession session) async {
    final athleteRow = await _athleteDao.getFirst();
    if (athleteRow == null) return;
    final athleteId = athleteRow['id'] as int;

    // Insert SESSION
    final sessionId = await _sessionDao.insertSession(
      athleteId: athleteId,
      exercise: session.exercise,
      date: session.date,
    );

    // Insert SET rows and their REPs
    if (session.sets.isNotEmpty) {
      for (int si = 0; si < session.sets.length; si++) {
        final setRecord = session.sets[si];
        final setId = await _setDao.insertSet(
          sessionId: sessionId,
          exercise: session.exercise,
          setIndex: si,
          loadKg: session.loadKg,
          targetRpe: session.targetRpe,
        );
        for (final rep in setRecord.reps) {
          await _repDao.insertRep(
            setId: setId,
            repIndex: rep.repNumber,
            timestamp: rep.timestamp,
            peakVelocity: rep.peakVelocity,
            meanConcentricVelocity: rep.avgVelocity,
            displacementM:
                rep.romMm != null ? rep.romMm! / 1000.0 : null,
            formScore: rep.formScore,
            dataQuality: rep.formScore >= 60 ? 'good' : 'low',
          );
        }
      }
    } else {
      // Flat list fallback (no set breakdown)
      final setId = await _setDao.insertSet(
        sessionId: sessionId,
        exercise: session.exercise,
        setIndex: 0,
        loadKg: session.loadKg,
      );
      for (final rep in session.reps) {
        await _repDao.insertRep(
          setId: setId,
          repIndex: rep.repNumber,
          timestamp: rep.timestamp,
          peakVelocity: rep.peakVelocity,
          meanConcentricVelocity: rep.avgVelocity,
          displacementM:
              rep.romMm != null ? rep.romMm! / 1000.0 : null,
          formScore: rep.formScore,
          dataQuality: rep.formScore >= 60 ? 'good' : 'low',
        );
      }
    }

    // Refresh state from DB
    await _loadFromDb(athleteId);
  }
}

final workoutHistoryProvider =
    StateNotifierProvider<WorkoutHistoryNotifier, WorkoutHistoryState>(
  (ref) => WorkoutHistoryNotifier(),
);
