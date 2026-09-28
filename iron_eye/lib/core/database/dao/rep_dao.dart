import '../db_helper.dart';

class RepDao {
  final _dbHelper = DbHelper.instance;

  Future<int> insertRep({
    required int setId,
    required int repIndex,
    required DateTime timestamp,
    double? meanConcentricVelocity,
    double? peakVelocity,
    double? displacementM,
    int? durationMs,
    int? formScore,
    String dataQuality = 'good',
  }) async {
    final db = await _dbHelper.db;
    return db.insert('REP', {
      'set_id': setId,
      'rep_index': repIndex,
      'mean_concentric_velocity': meanConcentricVelocity,
      'peak_velocity': peakVelocity,
      'displacement_m': displacementM,
      'duration_ms': durationMs,
      'form_score': formScore,
      'data_quality': dataQuality,
      'algorithm_version': '1.0',
      'timestamp': timestamp.toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getRepsForSet(int setId) async {
    final db = await _dbHelper.db;
    return db.query(
      'REP',
      where: 'set_id = ?',
      whereArgs: [setId],
      orderBy: 'rep_index ASC',
    );
  }

  /// All reps in a session joined with their set (for charts)
  Future<List<Map<String, dynamic>>> getRepsForSession(int sessionId) async {
    final db = await _dbHelper.db;
    return db.rawQuery('''
      SELECT r.*, ws.load_kg, ws.set_index
      FROM REP r
      JOIN WORKOUT_SET ws ON r.set_id = ws.id
      WHERE ws.session_id = ?
      ORDER BY ws.set_index ASC, r.rep_index ASC
    ''', [sessionId]);
  }

  /// Good-quality load-velocity pairs for e1RM regression
  Future<List<Map<String, dynamic>>> getLoadVelocityPairs(
      int athleteId, String exercise) async {
    final db = await _dbHelper.db;
    return db.rawQuery('''
      SELECT
        ws.load_kg,
        AVG(r.mean_concentric_velocity) AS avg_velocity,
        COUNT(r.id)                     AS rep_count
      FROM REP r
      JOIN WORKOUT_SET ws ON r.set_id = ws.id
      JOIN SESSION s      ON ws.session_id = s.id
      WHERE s.athlete_id = ?
        AND ws.exercise = ?
        AND ws.load_kg IS NOT NULL
        AND r.mean_concentric_velocity IS NOT NULL
        AND r.data_quality = 'good'
        AND s.date >= date('now', '-56 days')
      GROUP BY ws.load_kg
      HAVING rep_count >= 2
      ORDER BY ws.load_kg ASC
    ''', [athleteId, exercise]);
  }
}