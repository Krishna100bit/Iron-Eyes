import '../db_helper.dart';
import '../../models/user_profile.dart';

class AthleteDao {
  final _dbHelper = DbHelper.instance;

  Future<int> insert(UserProfile p) async {
    final db = await _dbHelper.db;
    return db.insert('ATHLETE', {
      'name': p.name,
      'bodyweight': p.weight,
      'height_cm': p.height,
      'age': p.age,
      'gender': p.gender,
      'training_level': p.trainingExperience,
      'goal': p.goal,
      'weekly_workout_target': p.weeklyWorkoutTarget,
      'weekly_rep_target': p.weeklyRepTarget,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> getFirst() async {
    final db = await _dbHelper.db;
    final rows = await db.query('ATHLETE', orderBy: 'id ASC', limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> update(int id, UserProfile p) async {
    final db = await _dbHelper.db;
    return db.update(
      'ATHLETE',
      {
        'name': p.name,
        'bodyweight': p.weight,
        'height_cm': p.height,
        'age': p.age,
        'gender': p.gender,
        'training_level': p.trainingExperience,
        'goal': p.goal,
        'weekly_workout_target': p.weeklyWorkoutTarget,
        'weekly_rep_target': p.weeklyRepTarget,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
