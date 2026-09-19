import '../db_helper.dart';

class SessionDao {
  final _dbHelper = DbHelper.instance;

  Future<int> insertSession({
    required int athleteId,
    required String exercise,
    required DateTime date,
    String? notes,
  }) async {
    final db = await _dbHelper.db;
    return db.insert('SESSION', {
      'athlete_id': athleteId,
      'exercise': exercise,
      'date': date.toIso8601String(),
      'notes': notes,
    });
  }

  /// All sessions for an athlete, newest first
  Future<List<Map<String, dynamic>>> getSessionsForAthlete(int athleteId,
      {int? limit}) async {
    final db = await _dbHelper.db;
    return db.query(
      'SESSION',
      where: 'athlete_id = ?',
      whereArgs: [athleteId],
      orderBy: 'date DESC',
      limit: limit,
    );
  }

  /// Sessions in the past N days
  Future<List<Map<String, dynamic>>> getSessionsSince(
      int athleteId, DateTime since) async {
    final db = await _dbHelper.db;
    return db.query(
      'SESSION',
      where: 'athlete_id = ? AND date >= ?',
      whereArgs: [athleteId, since.toIso8601String()],
      orderBy: 'date DESC',
    );
  }

  /// Distinct session dates for streak calculation
  Future<List<String>> getDistinctDates(int athleteId) async {
    final db = await _dbHelper.db;
    final rows = await db.rawQuery('''
      SELECT DISTINCT substr(date, 1, 10) as day
      FROM SESSION
      WHERE athlete_id = ?
      ORDER BY day DESC
    ''', [athleteId]);
    return rows.map((r) => r['day'] as String).toList();
  }

  /// Aggregate summary for each session (used for history list)
  Future<List<Map<String, dynamic>>> getSessionSummaries(int athleteId,
      {int limit = 20}) async {
    final db = await _dbHelper.db;
    return db.rawQuery('''
      SELECT
        s.id,
        s.exercise,
        s.date,
        COUNT(r.id)                    AS total_reps,
        COALESCE(AVG(r.form_score), 0) AS avg_form_score,
        (strftime('%s', MAX(r.timestamp)) - strftime('%s', MIN(r.timestamp)))
                                       AS duration_seconds,
        MAX(ws.load_kg)                AS load_kg
      FROM SESSION s
      LEFT JOIN WORKOUT_SET ws ON ws.session_id = s.id
      LEFT JOIN REP r          ON r.set_id = ws.id
      WHERE s.athlete_id = ?
      GROUP BY s.id
      ORDER BY s.date DESC
      LIMIT ?
    ''', [athleteId, limit]);
  }

  /// Rep count for today
  Future<int> getTodayRepCount(int athleteId) async {
    final db = await _dbHelper.db;
    final rows = await db.rawQuery('''
      SELECT COUNT(r.id) AS cnt
      FROM REP r
      JOIN WORKOUT_SET ws ON r.set_id = ws.id
      JOIN SESSION s      ON ws.session_id = s.id
      WHERE s.athlete_id = ?
        AND substr(s.date, 1, 10) = date('now', 'localtime')
    ''', [athleteId]);
    return ((rows.first['cnt'] as num?)?.toInt()) ?? 0;
  }

  /// Per-day rep counts for the past 7 days (Mon→Sun of current week)
  Future<Map<String, int>> getWeeklyRepCounts(int athleteId) async {
    final db = await _dbHelper.db;
    final rows = await db.rawQuery('''
      SELECT substr(s.date, 1, 10) AS day, COUNT(r.id) AS cnt
      FROM REP r
      JOIN WORKOUT_SET ws ON r.set_id = ws.id
      JOIN SESSION s      ON ws.session_id = s.id
      WHERE s.athlete_id = ?
        AND substr(s.date, 1, 10) >= date('now', '-6 days', 'localtime')
      GROUP BY substr(s.date, 1, 10)
    ''', [athleteId]);
    return {for (final r in rows) r['day'] as String: ((r['cnt'] as num?)?.toInt()) ?? 0};
  }

  /// Lifetime totals
  Future<Map<String, dynamic>> getLifetimeTotals(int athleteId) async {
    final db = await _dbHelper.db;
    final row = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT s.id)           AS total_workouts,
        COUNT(r.id)                    AS total_reps,
        COALESCE(AVG(r.form_score), 0) AS avg_form_score
      FROM SESSION s
      LEFT JOIN WORKOUT_SET ws ON ws.session_id = s.id
      LEFT JOIN REP r          ON r.set_id = ws.id
      WHERE s.athlete_id = ?
    ''', [athleteId]);
    return row.first;
  }
}
