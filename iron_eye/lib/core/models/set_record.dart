import 'rep_card.dart';

/// A completed set — holds all its reps and computed stats.
/// Defined here (not in active_session_provider) to avoid circular imports.
class SetRecord {
  final int setNumber;
  final List<RepCard> reps;

  SetRecord({required this.setNumber, required this.reps});

  int get repCount => reps.length;

  int get avgFormScore {
    if (reps.isEmpty) return 0;
    return (reps.fold<int>(0, (s, r) => s + r.formScore) / reps.length).round();
  }

  String get avgFormGrade {
    final s = avgFormScore;
    if (s >= 90) return 'A';
    if (s >= 80) return 'B';
    if (s >= 70) return 'C';
    if (s >= 60) return 'D';
    return 'F';
  }

  double? get avgVelocity {
    final vels =
        reps.where((r) => r.avgVelocity != null).map((r) => r.avgVelocity!).toList();
    if (vels.isEmpty) return null;
    return vels.reduce((a, b) => a + b) / vels.length;
  }

  double? get peakVelocity {
    final vels =
        reps.where((r) => r.peakVelocity != null).map((r) => r.peakVelocity!).toList();
    if (vels.isEmpty) return null;
    return vels.reduce((a, b) => a > b ? a : b);
  }
}