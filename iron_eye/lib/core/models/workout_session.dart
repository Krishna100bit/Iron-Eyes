import 'rep_card.dart';
import 'set_record.dart';

class WorkoutSession {
  final String id;
  final String exercise;
  final String exerciseType;
  final DateTime date;
  final int totalReps;
  final int avgFormScore;
  final int durationSeconds;
  final List<RepCard> reps; // flat rep list (for display)
  final List<SetRecord> sets; // structured set breakdown (for DB persistence)
  final double? loadKg; // load used (if barbell exercise)
  final double? targetRpe; // target RPE for this session

  WorkoutSession({
    required this.id,
    required this.exercise,
    required this.exerciseType,
    required this.date,
    required this.totalReps,
    required this.avgFormScore,
    required this.durationSeconds,
    required this.reps,
    this.sets = const [],
    this.loadKg,
    this.targetRpe,
  });

  String get avgFormGrade {
    if (avgFormScore >= 90) return 'A';
    if (avgFormScore >= 80) return 'B';
    if (avgFormScore >= 70) return 'C';
    if (avgFormScore >= 60) return 'D';
    return 'F';
  }

  String get formattedDuration {
    final m = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }
}