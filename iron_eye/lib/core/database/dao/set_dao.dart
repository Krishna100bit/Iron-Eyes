import '../db_helper.dart';

class SetDao {
  final _dbHelper = DbHelper.instance;

  Future<int> insertSet({
    required int sessionId,
    required String exercise,
    required int setIndex,
    double? loadKg,
    double? targetRpe,
  }) async {
    final db = await _dbHelper.db;
    return db.insert('WORKOUT_SET', {
      'session_id': sessionId,
      'exercise': exercise,
      'set_index': setIndex,
      'load_kg': loadKg,
      'target_rpe': targetRpe,
    });
  }

  Future<List<Map<String, dynamic>>> getSetsForSession(int sessionId) async {
    final db = await _dbHelper.db;
    return db.query(
      'WORKOUT_SET',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'set_index ASC',
    );
  }
}