import 'dart:math';

/// e1RM estimator via linear regression on Load-Velocity pairs.
///
/// From 02_ARCHITECTURE.md Part J:
/// - Model: simple linear regression (velocity vs. load) per exercise per athlete.
/// - Minimum ≥4 distinct load-velocity pairs before regression is trusted.
/// - Reports R² alongside e1RM; low R² → flagged as low-confidence.
/// - NOT called "AI" anywhere — it is a deterministic linear fit.
class LoadVelocityModel {
  static const int minPoints = 4;

  // 1RM velocity profile (the velocity at true 1RM, exercise specific)
  // Used to extrapolate the regression line to find 1RM load.
  static const Map<String, double> _v1rmDefaults = {
    'Squat': 0.30, // m/s — typical squat at maximal load
    'Bench Press': 0.15, // m/s — bench typically slower at max
    'default': 0.25,
  };

  final String exercise;
  final List<_LoadVelocityPair> _pairs = [];

  // Regression result cache
  double? _slope; // Δvelocity / Δload
  double? _intercept; // predicted velocity at load=0
  double? _rSquared;
  double? _estimated1rm;

  LoadVelocityModel({required this.exercise});

  // ── Data ingestion ─────────────────────────────────────────────────────────

  /// Add or update a load-velocity pair (average velocity for a given load).
  void addPoint(double loadKg, double avgVelocity,
      {bool goodQuality = true}) {
    if (!goodQuality) return; // exclude noisy reps per spec

    // Upsert: if same load exists (within 1 kg), average them
    final existing = _pairs.where(
        (p) => (p.load - loadKg).abs() < 1.0).toList();
    if (existing.isNotEmpty) {
      final idx = _pairs.indexOf(existing.first);
      _pairs[idx] = _LoadVelocityPair(
        load: loadKg,
        velocity: (existing.first.velocity + avgVelocity) / 2.0,
      );
    } else {
      _pairs.add(_LoadVelocityPair(load: loadKg, velocity: avgVelocity));
    }

    _recompute();
  }

  /// Load all historical pairs at once (from RepDao.getLoadVelocityPairs)
  void loadHistoricalPairs(List<({double loadKg, double avgVelocity})> data) {
    _pairs.clear();
    for (final d in data) {
      _pairs.add(_LoadVelocityPair(load: d.loadKg, velocity: d.avgVelocity));
    }
    _recompute();
  }

  // ── Regression ─────────────────────────────────────────────────────────────

  void _recompute() {
    if (_pairs.length < minPoints) {
      _slope = _intercept = _rSquared = _estimated1rm = null;
      return;
    }

    // Outlier rejection: remove points >2 std-dev from initial fit line
    final pruned = _outlierRejection(_pairs);
    if (pruned.length < minPoints) {
      _slope = _intercept = _rSquared = _estimated1rm = null;
      return;
    }

    final n = pruned.length.toDouble();
    final sumX = pruned.fold(0.0, (s, p) => s + p.load);
    final sumY = pruned.fold(0.0, (s, p) => s + p.velocity);
    final sumXY = pruned.fold(0.0, (s, p) => s + p.load * p.velocity);
    final sumX2 = pruned.fold(0.0, (s, p) => s + p.load * p.load);

    final denom = n * sumX2 - sumX * sumX;
    if (denom.abs() < 1e-9) {
      _slope = _intercept = _rSquared = _estimated1rm = null;
      return;
    }

    _slope = (n * sumXY - sumX * sumY) / denom;
    _intercept = (sumY - _slope! * sumX) / n;

    // R²
    final meanY = sumY / n;
    final ssTot = pruned.fold(0.0, (s, p) => s + pow(p.velocity - meanY, 2));
    final ssRes = pruned.fold(
        0.0, (s, p) => s + pow(p.velocity - (_slope! * p.load + _intercept!), 2));
    _rSquared = ssTot > 0 ? 1.0 - ssRes / ssTot : 0.0;

    // Extrapolate to 1RM: load at which predicted velocity = v1RM
    final v1rm = _v1rmDefaults[exercise] ?? _v1rmDefaults['default']!;
    if (_slope!.abs() > 1e-9) {
      _estimated1rm = (v1rm - _intercept!) / _slope!;
      if (_estimated1rm! < 0) _estimated1rm = null; // sanity check
    }
  }

  List<_LoadVelocityPair> _outlierRejection(List<_LoadVelocityPair> pts) {
    // Quick first-pass fit
    final n = pts.length.toDouble();
    final sx = pts.fold(0.0, (s, p) => s + p.load);
    final sy = pts.fold(0.0, (s, p) => s + p.velocity);
    final sxy = pts.fold(0.0, (s, p) => s + p.load * p.velocity);
    final sx2 = pts.fold(0.0, (s, p) => s + p.load * p.load);
    final denom = n * sx2 - sx * sx;
    if (denom.abs() < 1e-9) return pts;
    final m = (n * sxy - sx * sy) / denom;
    final b = (sy - m * sx) / n;

    // Residuals and std-dev
    final residuals = pts.map((p) => (p.velocity - (m * p.load + b)).abs()).toList();
    final meanRes = residuals.fold(0.0, (s, r) => s + r) / residuals.length;
    final stdRes = sqrt(residuals.fold(0.0, (s, r) => s + pow(r - meanRes, 2)) /
        residuals.length);

    // Keep points within 2 std-dev
    return [
      for (int i = 0; i < pts.length; i++)
        if (residuals[i] <= meanRes + 2 * stdRes) pts[i]
    ];
  }

  // ── Results ────────────────────────────────────────────────────────────────

  /// Estimated 1RM in kg. Null if fewer than [minPoints] pairs.
  double? get estimated1rm => _estimated1rm;

  /// R² confidence of the linear fit (0–1). Always show alongside 1RM.
  double? get rSquared => _rSquared;

  /// Human-readable confidence label.
  String get confidenceLabel {
    final r2 = _rSquared;
    if (r2 == null) return 'Insufficient data (need ${minPoints}+ loads)';
    if (r2 >= 0.90) return 'High confidence (R²=${r2.toStringAsFixed(2)})';
    if (r2 >= 0.75) return 'Moderate confidence (R²=${r2.toStringAsFixed(2)})';
    return 'Low confidence (R²=${r2.toStringAsFixed(2)})';
  }

  bool get hasEnoughData => _pairs.length >= minPoints;
  int get pairCount => _pairs.length;

  /// Predict velocity for a given load (for load-velocity chart)
  double? predictVelocity(double loadKg) {
    if (_slope == null || _intercept == null) return null;
    return (_slope! * loadKg + _intercept!).clamp(0.0, 3.0);
  }

  List<_LoadVelocityPair> get pairs => List.unmodifiable(_pairs);
}

class _LoadVelocityPair {
  final double load; // kg
  final double velocity; // m/s
  const _LoadVelocityPair({required this.load, required this.velocity});
}
