import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../database/dao/athlete_dao.dart';
import '../database/db_helper.dart';

class UserProfileNotifier extends StateNotifier<UserProfile?> {
  final _dao = AthleteDao();
  int? _athleteId;

  UserProfileNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final row = await _dao.getFirst();
    if (row != null) {
      _athleteId = row['id'] as int;
      state = UserProfile.fromMap(row);
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    if (_athleteId != null) {
      await _dao.update(_athleteId!, profile);
    } else {
      _athleteId = await _dao.insert(profile);
    }
    state = profile;
  }

  int? get athleteId => _athleteId;

  Future<void> refresh() => _load();

  Future<void> clearProfile() async {
    await DbHelper.instance.deleteEverything();
    _athleteId = null;
    state = null;
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile?>(
  (ref) => UserProfileNotifier(),
);