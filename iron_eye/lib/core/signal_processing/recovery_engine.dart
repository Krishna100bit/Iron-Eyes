/// IRON EYE — RECOVERY ENGINE (ACWR + EWMA + Readiness Composite)
///
/// Based on validated sports science frameworks:
///   • Hulin et al. (2016) — ACWR and injury risk
///   • Williams et al. (2017) — EWMA method superiority over rolling average
///   • Buchheit (2014) — HRV-guided training principles
///
///  Method: EXPONENTIALLY WEIGHTED MOVING AVERAGE (EWMA) ACWR
///    EWMA gives more weight to recent sessions, capturing rapid load changes
///    better than a simple rolling 7/28-day average.
///
///  Metrics computed:
///    1. Daily Training Load (DTL) — reps × loadKg (bodyweight=50kg proxy)
///    2. EWMA Acute (λ=2/8)    — ~7-day weighted fatigue indicator
///    3. EWMA Chronic (λ=2/29) — ~28-day weighted fitness indicator
///    4. ACWR = Acute / Chronic
///    5. Readiness Score (0–100) — Gaussian ACWR + rest day bonus + trend bonus
///
///  ACWR Risk Zones (Hulin 2016 framework):
///    < 0.8  → Under-trained (low adaptation stimulus)
///    0.8–1.0 → Fresh (good recovery, maintain load)
///    1.0–1.3 → Optimal ("sweet spot")
///    1.3–1.5 → Caution (load spike risk)
///    > 1.5  → Danger (elevated injury risk)
///
library recovery_engine;

import 'dart:math' as math;
import '../models/workout_session.dart';
class TrainingLoadPoint {
  final DateTime date;
  final double load; // Arbitrary Training Units (ATU)
  const TrainingLoadPoint({required this.date, required this.load});
}
enum AcwrZone {
  undertrained, // ACWR < 0.8
  fresh,        // 0.8 – 1.0
  optimal,      // 1.0 – 1.3
  caution,      // 1.3 – 1.5
  danger,       // > 1.5
}
class RecoveryStatus {
  final double acwr;
  final double acuteLoad;
  final double chronicLoad;
  final AcwrZone zone;

  /// 0–100 readiness score (higher = more ready for intense training)
  final double readinessScore;

  /// Number of consecutive rest days immediately before today
  final int restDays;

  /// Linear slope of last-7-day daily loads (positive = ramping)
  final double weeklyLoadTrend;

  final String zoneLabel;
  final String zoneAdvice;
  final String readinessLabel;

  const RecoveryStatus({
    required this.acwr,
    required this.acuteLoad,
    required this.chronicLoad,
    required this.zone,
    required this.readinessScore,
    required this.restDays,
    required this.weeklyLoadTrend,
    required this.zoneLabel,
    required this.zoneAdvice,
    required this.readinessLabel,
  });
}
class WeeklyLoadBar {
  final String dayLabel;
  final double load;
  final bool isToday;
  const WeeklyLoadBar({
    required this.dayLabel,
    required this.load,
    required this.isToday,
  });
}
class RecoveryEngine {
  // EWMA decay constants  λ = 2 / (N + 1)
  static const double _lambdaAcute   = 2.0 / (7 + 1);   // ≈ 0.250
  static const double _lambdaChronic = 2.0 / (28 + 1);  // ≈ 0.067

  /// Convert sessions to daily Training Load Points
  static List<TrainingLoadPoint> sessionsToLoadPoints(
      List<WorkoutSession> sessions) {
    final Map<String, double> dayLoad = {};
    for (final s in sessions) {
      final key = _dateKey(s.date);
      final weight = s.loadKg ?? 50.0; // bodyweight proxy = 50 kg
      // ATU = total_reps × relative_weight (scaled to ~0–10 range)
      final atu = s.totalReps * weight * 0.01;
      dayLoad[key] = (dayLoad[key] ?? 0.0) + atu;
    }
    return dayLoad.entries
        .map((e) => TrainingLoadPoint(date: DateTime.parse(e.key), load: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Main entry point: returns null if there is no session data at all.
  static RecoveryStatus? analyze(List<WorkoutSession> sessions) {
    if (sessions.isEmpty) return null;

    final points = sessionsToLoadPoints(sessions);
    final Map<String, double> loadByDay = {
      for (final p in points) _dateKey(p.date): p.load
    };

    final today = DateTime.now();

    // EWMA calculation over the last 30 days (oldest → newest)
    double ewmaAcute   = 0.0;
    double ewmaChronic = 0.0;
    final List<double> last7Loads = [];

    for (int i = 29; i >= 0; i--) {
      final d       = today.subtract(Duration(days: i));
      final dayLoad = loadByDay[_dateKey(d)] ?? 0.0;

      // EWMA update rule:  EWMAₜ = λ × Loadₜ + (1 - λ) × EWMAₜ₋₁
      ewmaAcute   = _lambdaAcute   * dayLoad + (1 - _lambdaAcute)   * ewmaAcute;
      ewmaChronic = _lambdaChronic * dayLoad + (1 - _lambdaChronic) * ewmaChronic;

      if (i < 7) last7Loads.add(dayLoad);
    }

    // ACWR = Acute EWMA / Chronic EWMA  (default 1.0 if no chronic base yet)
    final acwr = ewmaChronic > 0 ? ewmaAcute / ewmaChronic : 1.0;

    // Consecutive rest days immediately before today
    int restDays = 0;
    for (int i = 1; i <= 14; i++) {
      final d = today.subtract(Duration(days: i));
      if ((loadByDay[_dateKey(d)] ?? 0.0) > 0) break;
      restDays++;
    }

    // 7-day load trend (linear regression slope)
    final weeklyLoadTrend =
        last7Loads.length >= 2 ? _slope(last7Loads) : 0.0;
    // Core: Gaussian curve peaked at ACWR = 1.1, σ = 0.22
    //   → gives 100 at sweet spot, falling off as ACWR deviates
    double readiness = _gaussianAcwrReadiness(acwr);

    // Modifiers
    if (restDays == 1 || restDays == 2) readiness += 10.0; // super-compensation window
    if (restDays == 0) readiness -= 5.0;                    // consecutive training
    if (restDays >= 5) readiness -= 12.0;                   // detraining risk

    // Small progressive-overload bonus
    if (weeklyLoadTrend > 0 && weeklyLoadTrend < 0.5) readiness += 5.0;
    // Tapering bonus
    if (weeklyLoadTrend < 0) readiness += 3.0;

    readiness = readiness.clamp(0.0, 100.0);

    final zone = _acwrZone(acwr);

    return RecoveryStatus(
      acwr:             acwr,
      acuteLoad:        ewmaAcute,
      chronicLoad:      ewmaChronic,
      zone:             zone,
      readinessScore:   readiness,
      restDays:         restDays,
      weeklyLoadTrend:  weeklyLoadTrend,
      zoneLabel:        _zoneLabel(zone),
      zoneAdvice:       _zoneAdvice(zone, restDays),
      readinessLabel:   _readinessLabel(readiness),
    );
  }

  /// 7-day bar chart data
  static List<WeeklyLoadBar> weeklyBars(List<WorkoutSession> sessions) {
    final points = sessionsToLoadPoints(sessions);
    final Map<String, double> loadByDay = {
      for (final p in points) _dateKey(p.date): p.load
    };
    final today = DateTime.now();
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return List.generate(7, (i) {
      final d    = today.subtract(Duration(days: 6 - i));
      final load = loadByDay[_dateKey(d)] ?? 0.0;
      return WeeklyLoadBar(
        dayLabel: dayNames[d.weekday - 1],
        load:     load,
        isToday:  i == 6,
      );
    });
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Gaussian readiness: peaks at 100 when ACWR=1.1, σ=0.22
  static double _gaussianAcwrReadiness(double acwr) {
    const mu    = 1.1;
    const sigma = 0.22;
    final diff  = acwr - mu;
    return 100.0 * math.exp(-(diff * diff) / (2.0 * sigma * sigma));
  }

  /// OLS slope via Sxy / Sxx
  static double _slope(List<double> values) {
    final n = values.length;
    if (n < 2) return 0.0;
    final xMean = (n - 1) / 2.0;
    final yMean = values.reduce((a, b) => a + b) / n;
    double sxy = 0.0, sxx = 0.0;
    for (int i = 0; i < n; i++) {
      sxy += (i - xMean) * (values[i] - yMean);
      sxx += (i - xMean) * (i - xMean);
    }
    return sxx == 0 ? 0.0 : sxy / sxx;
  }

  static AcwrZone _acwrZone(double acwr) {
    if (acwr < 0.8) return AcwrZone.undertrained;
    if (acwr < 1.0) return AcwrZone.fresh;
    if (acwr < 1.3) return AcwrZone.optimal;
    if (acwr < 1.5) return AcwrZone.caution;
    return AcwrZone.danger;
  }

  static String _zoneLabel(AcwrZone zone) {
    switch (zone) {
      case AcwrZone.undertrained: return 'Under-trained';
      case AcwrZone.fresh:        return 'Fresh';
      case AcwrZone.optimal:      return 'Optimal Load';
      case AcwrZone.caution:      return 'Load Spike';
      case AcwrZone.danger:       return 'High Risk';
    }
  }

  static String _zoneAdvice(AcwrZone zone, int restDays) {
    switch (zone) {
      case AcwrZone.undertrained:
        return 'Training load is well below your fitness base. Gradually increase volume to stimulate adaptation without a big spike.';
      case AcwrZone.fresh:
        return restDays >= 2
            ? 'You are well-rested after $restDays days off. A good window to push intensity.'
            : 'Recovery is solid. Maintain or slightly increase training load.';
      case AcwrZone.optimal:
        return 'Load is in the sweet spot for adaptation (ACWR 1.0–1.3). Continue progressive overload.';
      case AcwrZone.caution:
        return 'Recent load has spiked relative to your chronic baseline. Consider keeping today moderate to allow adaptation.';
      case AcwrZone.danger:
        return 'ACWR > 1.5 — this is the elevated-injury-risk zone (Hulin 2016). Reduce volume by 20–30% or take a full rest day.';
    }
  }

  static String _readinessLabel(double score) {
    if (score >= 80) return 'Go Hard 🔥';
    if (score >= 60) return 'Train Smart ✅';
    if (score >= 40) return 'Moderate Effort ⚡';
    if (score >= 20) return 'Active Recovery 🚶';
    return 'Rest Day 💤';
  }
}