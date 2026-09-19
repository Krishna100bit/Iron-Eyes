/// Velocity Loss (VL%) calculator — from 02_ARCHITECTURE.md Part I.
///
/// VL% = (v_reference - v_current) / v_reference × 100
///
/// Reference = best (peak) mean concentric velocity in the set.
/// Minimum 3 reps required before displaying VL%.
/// Noisy reps (data_quality='low') excluded from both reference and current.
class VelocityLoss {
  static const int minRepsRequired = 3;

  // Configurable stop thresholds (from 02_ARCHITECTURE.md — user-adjustable sliders)
  // Labelled as training strategies, never as medical thresholds
  static const Map<String, double> thresholds = {
    'Conservative': 10.0, // ~10% VL → stop
    'Moderate': 20.0, // ~20% VL → stop
    'Aggressive': 30.0, // ~30% VL → stop
  };

  final List<_RepVelocity> _reps = [];
  late double _vReference;
  bool _referenceSet = false;

  /// Add a rep's mean concentric velocity and data quality.
  void addRep(double meanVelocity, {bool isGoodQuality = true}) {
    _reps.add(_RepVelocity(velocity: meanVelocity, goodQuality: isGoodQuality));

    // Update reference: best good-quality rep in the set
    final goodReps =
        _reps.where((r) => r.goodQuality && r.velocity > 0).toList();
    if (goodReps.isNotEmpty) {
      _vReference =
          goodReps.map((r) => r.velocity).reduce((a, b) => a > b ? a : b);
      _referenceSet = true;
    }
  }

  /// Returns VL% for the latest good-quality rep vs the reference rep.
  /// Returns null if fewer than [minRepsRequired] good reps are available.
  double? get velocityLossPercent {
    final goodReps = _reps.where((r) => r.goodQuality && r.velocity > 0).toList();
    if (goodReps.length < minRepsRequired || !_referenceSet) return null;

    final current = goodReps.last.velocity;
    if (_vReference <= 0) return null;

    final vl = (_vReference - current) / _vReference * 100.0;
    return vl.clamp(0.0, 100.0);
  }

  /// Returns the reference velocity (best rep in set), null if not enough data.
  double? get referenceVelocity =>
      _referenceSet ? _vReference : null;

  /// Good-quality reps used for this calculation.
  int get goodRepCount =>
      _reps.where((r) => r.goodQuality).length;

  /// Returns 'conservative', 'moderate', 'aggressive', or null if VL% is null.
  String? stopSignal(String thresholdName) {
    final vl = velocityLossPercent;
    if (vl == null) return null;
    final t = thresholds[thresholdName] ?? thresholds['Moderate']!;
    return vl >= t ? 'Target velocity loss reached — consider stopping' : null;
  }

  void reset() {
    _reps.clear();
    _referenceSet = false;
  }
}

class _RepVelocity {
  final double velocity;
  final bool goodQuality;
  const _RepVelocity({required this.velocity, required this.goodQuality});
}
