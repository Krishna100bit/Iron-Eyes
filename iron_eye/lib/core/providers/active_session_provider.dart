import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rep_card.dart';
import '../models/set_record.dart';
import '../models/workout_session.dart';

// ── Active Session State ───────────────────────────────────────────────────────
class ActiveSessionState {
  final bool isActive;
  final String exercise;
  final String exerciseType;
  final List<SetRecord> completedSets;
  final List<RepCard> currentSetReps;
  final DateTime startTime;
  final String movementState; // 'START', 'UP', 'DOWN'
  final double? loadKg;
  final double? targetRpe;

  ActiveSessionState({
    required this.isActive,
    required this.exercise,
    required this.exerciseType,
    required this.completedSets,
    required this.currentSetReps,
    required this.startTime,
    required this.movementState,
    this.loadKg,
    this.targetRpe,
  });

  // ── Derived values ─────────────────────────────────────────────────────────

  int get currentSetNumber => completedSets.length + 1;
  int get currentRepCount => currentSetReps.length;

  List<RepCard> get allReps => [
        ...completedSets.expand((s) => s.reps),
        ...currentSetReps,
      ];

  int get totalReps => allReps.length;

  int get avgFormScore {
    final all = allReps;
    if (all.isEmpty) return 0;
    return (all.fold<int>(0, (s, r) => s + r.formScore) / all.length).round();
  }

  String get avgFormGrade {
    final s = avgFormScore;
    if (s >= 90) return 'A';
    if (s >= 80) return 'B';
    if (s >= 70) return 'C';
    if (s >= 60) return 'D';
    return 'F';
  }

  String get currentFormGrade {
    if (currentSetReps.isEmpty && completedSets.isEmpty) return '—';
    final last = currentSetReps.isNotEmpty
        ? currentSetReps.last
        : completedSets.last.reps.last;
    return last.formGrade;
  }

  int get currentFormScore =>
      currentSetReps.isNotEmpty ? currentSetReps.last.formScore : 0;

  int get elapsedSeconds =>
      DateTime.now().difference(startTime).inSeconds;

  RepCard? get lastRep =>
      currentSetReps.isNotEmpty ? currentSetReps.last : null;

  List<double?> get repVelocities =>
      allReps.map((r) => r.peakVelocity).toList();

  ActiveSessionState copyWith({
    bool? isActive,
    String? exercise,
    String? exerciseType,
    List<SetRecord>? completedSets,
    List<RepCard>? currentSetReps,
    DateTime? startTime,
    String? movementState,
    double? loadKg,
    double? targetRpe,
  }) =>
      ActiveSessionState(
        isActive: isActive ?? this.isActive,
        exercise: exercise ?? this.exercise,
        exerciseType: exerciseType ?? this.exerciseType,
        completedSets: completedSets ?? this.completedSets,
        currentSetReps: currentSetReps ?? this.currentSetReps,
        startTime: startTime ?? this.startTime,
        movementState: movementState ?? this.movementState,
        loadKg: loadKg ?? this.loadKg,
        targetRpe: targetRpe ?? this.targetRpe,
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────────
class ActiveSessionNotifier extends StateNotifier<ActiveSessionState?> {
  ActiveSessionNotifier() : super(null);

  void startSession(String exercise, String exerciseType,
      {double? loadKg, double? targetRpe}) {
    state = ActiveSessionState(
      isActive: true,
      exercise: exercise,
      exerciseType: exerciseType,
      completedSets: [],
      currentSetReps: [],
      startTime: DateTime.now(),
      movementState: 'START',
      loadKg: loadKg,
      targetRpe: targetRpe,
    );
  }

  void addRep({
    required int formScore,
    double? peakVelocity,
    double? avgVelocity,
    int? romMm,
    List<String> flags = const [],
  }) {
    if (state == null) return;
    final newRep = RepCard(
      repNumber: state!.currentRepCount + 1,
      formScore: formScore,
      peakVelocity: peakVelocity,
      avgVelocity: avgVelocity,
      romMm: romMm,
      flags: flags,
      timestamp: DateTime.now(),
    );
    final nextMovement = state!.movementState == 'UP' ? 'DOWN' : 'UP';
    state = state!.copyWith(
      currentSetReps: [...state!.currentSetReps, newRep],
      movementState: nextMovement,
    );
  }

  void completeSet() {
    if (state == null || state!.currentSetReps.isEmpty) return;
    final newSet = SetRecord(
      setNumber: state!.currentSetNumber,
      reps: List.unmodifiable(state!.currentSetReps),
    );
    state = state!.copyWith(
      completedSets: [...state!.completedSets, newSet],
      currentSetReps: [],
      movementState: 'START',
    );
  }

  /// Stop session — auto-completes current set, returns a WorkoutSession
  /// (includes the sets breakdown for SQLite persistence).
  WorkoutSession? stopSession() {
    if (state == null) return null;

    if (state!.currentSetReps.isNotEmpty) completeSet();

    if (state!.allReps.isEmpty) {
      state = null;
      return null;
    }

    final session = WorkoutSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      exercise: state!.exercise,
      exerciseType: state!.exerciseType,
      date: state!.startTime,
      totalReps: state!.totalReps,
      avgFormScore: state!.avgFormScore,
      durationSeconds: state!.elapsedSeconds,
      reps: state!.allReps,
      sets: state!.completedSets, // full set breakdown for DB
      loadKg: state!.loadKg,
      targetRpe: state!.targetRpe,
    );
    state = null;
    return session;
  }

  void cancelSession() => state = null;
}

final activeSessionProvider =
    StateNotifierProvider<ActiveSessionNotifier, ActiveSessionState?>(
  (ref) => ActiveSessionNotifier(),
);
