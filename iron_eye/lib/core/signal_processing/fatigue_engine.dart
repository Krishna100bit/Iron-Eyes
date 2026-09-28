/// IRON EYE — FATIGUE ENGINE (Professional VBT-Grade Algorithm)
///
/// Based on validated sports science frameworks (Pareja-Blanco et al. 2020,
/// Weakley et al. 2021, Jidovtseff et al. 2011):
///
///  Signal 1 — Velocity Loss % (VL%)
///    VL% = (V_ref - V_current) / V_ref × 100
///    Thresholds: 10% (power), 20% (strength), 30% (hypertrophy)
///
///  Signal 2 — Velocity Decline Trend (linear regression slope on last 3 reps)
///    Detects accelerating decline not visible in raw VL%
///
///  Signal 3 — Form Score Decay
///    Monitors the rolling mean form score drop-off rep-over-rep
///
///  Signal 4 — Set-over-Set Peak Velocity Suppression
///    Compares each set's best rep to the baseline from the first set
///    A >15% inter-set drop suggests CNS/metabolic fatigue accumulation
///
///  Composite FatigueScore = weighted sum of all 4 signals (0–100)
///    Weight: VL% 50%, Trend 20%, Form 20%, Inter-set 10%
///
library fatigue_engine;

class RepSnapshot {
  final int repNumber;
  final double avgVelocity; // MCV
  final double peakVelocity;
  final int formScore;
  final DateTime timestamp;
  const RepSnapshot({
    required this.repNumber,
    required this.avgVelocity,
    required this.peakVelocity,
    required this.formScore,
    required this.timestamp,
  });
}

enum FatigueZone {
  fresh,     // < 20 — Optimal output
  moderate,  // 20–40 — Mild fatigue; maintain quality
  high,      // 40–65 — Significant fatigue; reduce load or volume
  critical,  // > 65  — Stop set immediately
}

class FatigueResult {
  /// 0–100 composite fatigue score
  final double score;
  final FatigueZone zone;

  /// Raw signals for UI display
  final double? velocityLossPct;   // VL% signal
  final double? trendScore;        // Velocity trend score contribution (0–100)
  final double? formDecayScore;    // Form decay contribution (0–100)
  final double? interSetScore;     // Inter-set suppression (0–100)

  final String headline;
  final String advice;
  final bool stopRecommended;

  const FatigueResult({
    required this.score,
    required this.zone,
    this.velocityLossPct,
    this.trendScore,
    this.formDecayScore,
    this.interSetScore,
    required this.headline,
    required this.advice,
    required this.stopRecommended,
  });
}

class FatigueEngine {
  static const double _wVl = 0.50;
  static const double _wTrend = 0.20;
  static const double _wForm = 0.20;
  static const double _wInterSet = 0.10;
  static const double _vlPower = 10.0;      // Power/speed training
  static const double _vlStrength = 20.0;   // Strength training
  static const double _vlHypertrophy = 30.0; // Hypertrophy training
  final List<RepSnapshot> _reps = [];
  double? _firstSetPeakVelocity; // Baseline from set 1

  /// The profile controls which VL% threshold is used
  String trainingGoal; // 'Power', 'Strength', 'Hypertrophy'

  FatigueEngine({this.trainingGoal = 'Strength'});

  void addRep(RepSnapshot rep) {
    _reps.add(rep);
    // Anchor the first rep's peak velocity as the inter-set baseline
    if (_reps.length == 1) {
      _firstSetPeakVelocity = rep.peakVelocity;
    }
  }

  void reset() {
    _reps.clear();
    _firstSetPeakVelocity = null;
  }

  /// Set the baseline from the very first set of the session (call at set boundary)
  void anchorInterSetBaseline(double peakVelocity) {
    _firstSetPeakVelocity ??= peakVelocity;
  }

  int get repCount => _reps.length;

  /// Main entry point — returns null if not enough data
  FatigueResult? analyze() {
    if (_reps.length < 2) return null;

    final goodReps = _reps.where((r) => r.avgVelocity > 0).toList();
    if (goodReps.length < 2) return null;
    final vRef = goodReps.map((r) => r.avgVelocity).reduce((a, b) => a > b ? a : b);
    final vCurrent = goodReps.last.avgVelocity;
    final vlPct = (vRef - vCurrent) / vRef * 100.0;

    final vlThreshold = _vlThresholdFor(trainingGoal);
    // Score: 0 at 0% VL, 100 at 2× threshold
    final vlScore = (vlPct / (vlThreshold * 2.0) * 100.0).clamp(0.0, 100.0);
    double trendScore = 0.0;
    if (goodReps.length >= 3) {
      final window = goodReps.length > 5 ? goodReps.sublist(goodReps.length - 5) : goodReps;
      final slope = _linearRegressionSlope(window.map((r) => r.avgVelocity).toList());
      // A slope of -0.1 m/s per rep = 100 trendScore
      trendScore = ((-slope / 0.1) * 100.0).clamp(0.0, 100.0);
    }
    double formDecayScore = 0.0;
    if (_reps.length >= 2) {
      final firstForm = _reps.first.formScore.toDouble();
      final lastForm = _reps.last.formScore.toDouble();
      final formDrop = firstForm - lastForm; // positive = decay
      // A 30-point drop maps to 100 score
      formDecayScore = (formDrop / 30.0 * 100.0).clamp(0.0, 100.0);
    }
    double interSetScore = 0.0;
    if (_firstSetPeakVelocity != null && _firstSetPeakVelocity! > 0) {
      final currentPeak = goodReps.map((r) => r.peakVelocity).reduce((a, b) => a > b ? a : b);
      final suppression = (_firstSetPeakVelocity! - currentPeak) / _firstSetPeakVelocity! * 100.0;
      // A 25% inter-set peak drop = 100 score
      interSetScore = (suppression / 25.0 * 100.0).clamp(0.0, 100.0);
    }
    final composite = (vlScore * _wVl)
        + (trendScore * _wTrend)
        + (formDecayScore * _wForm)
        + (interSetScore * _wInterSet);

    final zone = _zone(composite);
    final headline = _headline(zone, vlPct);
    final advice = _advice(zone, trainingGoal, vlPct, vlThreshold);

    return FatigueResult(
      score: composite,
      zone: zone,
      velocityLossPct: vlPct,
      trendScore: trendScore,
      formDecayScore: formDecayScore,
      interSetScore: interSetScore,
      headline: headline,
      advice: advice,
      stopRecommended: zone == FatigueZone.critical,
    );
  }

  double _vlThresholdFor(String goal) {
    switch (goal) {
      case 'Power': return _vlPower;
      case 'Hypertrophy': return _vlHypertrophy;
      default: return _vlStrength;
    }
  }

  /// Ordinary Least Squares slope via Sn / Sxx
  double _linearRegressionSlope(List<double> values) {
    if (values.length < 2) return 0.0;
    final n = values.length;
    final xMean = (n - 1) / 2.0;
    final yMean = values.reduce((a, b) => a + b) / n;
    double sxy = 0.0, sxx = 0.0;
    for (int i = 0; i < n; i++) {
      sxy += (i - xMean) * (values[i] - yMean);
      sxx += (i - xMean) * (i - xMean);
    }
    return sxx == 0 ? 0.0 : sxy / sxx;
  }

  FatigueZone _zone(double score) {
    if (score < 20) return FatigueZone.fresh;
    if (score < 40) return FatigueZone.moderate;
    if (score < 65) return FatigueZone.high;
    return FatigueZone.critical;
  }

  String _headline(FatigueZone zone, double vlPct) {
    switch (zone) {
      case FatigueZone.fresh:
        return 'Feeling Strong';
      case FatigueZone.moderate:
        return 'Mild Fatigue (${vlPct.toStringAsFixed(0)}% VL)';
      case FatigueZone.high:
        return 'High Fatigue (${vlPct.toStringAsFixed(0)}% VL)';
      case FatigueZone.critical:
        return '⚠ Stop Set Now (${vlPct.toStringAsFixed(0)}% VL)';
    }
  }

  String _advice(FatigueZone zone, String goal, double vlPct, double threshold) {
    switch (zone) {
      case FatigueZone.fresh:
        return 'Velocity is stable. CNS output optimal.';
      case FatigueZone.moderate:
        return 'VL is ${vlPct.toStringAsFixed(0)}% — approaching your ${threshold.toStringAsFixed(0)}% $goal threshold. Monitor closely.';
      case FatigueZone.high:
        return 'Velocity drop indicates significant fatigue. Consider stopping to preserve neural quality.';
      case FatigueZone.critical:
        return 'VL% exceeded $goal threshold. Continuing risks technique breakdown and injury. End set.';
    }
  }
}