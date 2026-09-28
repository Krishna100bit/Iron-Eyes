class UserProfile {
  final String name;
  final String? avatar;
  final int age;
  final double weight; // kg
  final double height; // cm
  final String gender; // 'male', 'female', 'other'
  final String trainingExperience; // 'beginner', 'intermediate', 'advanced'
  final String goal; // 'strength', 'endurance', 'weight_loss'
  final int weeklyWorkoutTarget;
  final int weeklyRepTarget;

  UserProfile({
    required this.name,
    this.avatar,
    required this.age,
    required this.weight,
    required this.height,
    this.gender = 'male',
    this.trainingExperience = 'beginner',
    required this.goal,
    this.weeklyWorkoutTarget = 5,
    this.weeklyRepTarget = 300,
  });

  String get goalDisplay {
    switch (goal) {
      case 'strength':    return 'Strength';
      case 'endurance':   return 'Endurance';
      case 'weight_loss': return 'Weight Loss';
      default:            return goal;
    }
  }

  String get goalEmoji {
    switch (goal) {
      case 'strength':    return '💪';
      case 'endurance':   return '🏃';
      case 'weight_loss': return '🔥';
      default:            return '🎯';
    }
  }

  String get experienceDisplay {
    switch (trainingExperience) {
      case 'beginner':     return 'Beginner';
      case 'intermediate': return 'Intermediate';
      case 'advanced':     return 'Advanced';
      default:             return trainingExperience;
    }
  }

  String get genderDisplay {
    switch (gender) {
      case 'male':   return 'Male';
      case 'female': return 'Female';
      default:       return 'Other';
    }
  }

  /// Keys match the ATHLETE table column names in db_helper.dart
  Map<String, dynamic> toMap() => {
    'name': name,
    'avatar': avatar,
    'bodyweight': weight,
    'height_cm': height,
    'age': age,
    'gender': gender,
    'training_level': trainingExperience,
    'goal': goal,
    'weekly_workout_target': weeklyWorkoutTarget,
    'weekly_rep_target': weeklyRepTarget,
  };

  /// Accepts both SQLite column names and old Hive key names for safety
  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
    name: map['name'] as String? ?? '',
    avatar: map['avatar'] as String?,
    age: (map['age'] as num?)?.toInt() ?? 22,
    weight: (map['bodyweight'] as num?)?.toDouble()
        ?? (map['weight'] as num?)?.toDouble() ?? 70,
    height: (map['height_cm'] as num?)?.toDouble()
        ?? (map['height'] as num?)?.toDouble() ?? 170,
    gender: map['gender'] as String? ?? 'male',
    trainingExperience: (map['training_level'] as String?)
        ?? (map['trainingExperience'] as String?) ?? 'beginner',
    goal: map['goal'] as String? ?? 'strength',
    weeklyWorkoutTarget:
        (map['weekly_workout_target'] as num?)?.toInt()
        ?? (map['weeklyWorkoutTarget'] as num?)?.toInt() ?? 5,
    weeklyRepTarget:
        (map['weekly_rep_target'] as num?)?.toInt()
        ?? (map['weeklyRepTarget'] as num?)?.toInt() ?? 300,
  );

  UserProfile copyWith({
    String? name,
    String? avatar,
    int? age,
    double? weight,
    double? height,
    String? gender,
    String? trainingExperience,
    String? goal,
    int? weeklyWorkoutTarget,
    int? weeklyRepTarget,
  }) =>
      UserProfile(
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        age: age ?? this.age,
        weight: weight ?? this.weight,
        height: height ?? this.height,
        gender: gender ?? this.gender,
        trainingExperience: trainingExperience ?? this.trainingExperience,
        goal: goal ?? this.goal,
        weeklyWorkoutTarget: weeklyWorkoutTarget ?? this.weeklyWorkoutTarget,
        weeklyRepTarget: weeklyRepTarget ?? this.weeklyRepTarget,
      );
}