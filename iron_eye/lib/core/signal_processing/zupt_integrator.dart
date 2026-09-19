/// ZUPT-constrained velocity integrator.
///
/// From 02_ARCHITECTURE.md Step 7:
/// "Integrate linear acceleration → velocity, v[n] = v[n-1] + a[n]·dt
///  At every detected STATIONARY window, force v = 0 — this is what prevents
///  open-loop drift. Barbell reps naturally pause at top/bottom which gives a
///  ZUPT point every rep."
class ZuptIntegrator {
  // Rolling variance threshold — samples below this are classed as stationary.
  // Tune: too tight → misses pauses; too loose → integrates noise.
  static const double _stationaryVarianceThreshold = 0.08; // (m/s²)²

  // Number of samples in the rolling window for variance detection (~100ms @100Hz)
  static const int _windowSize = 10;

  double _velocity = 0.0;
  double _displacement = 0.0;
  bool _isStationary = true;

  final List<double> _accelWindow = [];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Process one sample of linear acceleration (gravity already removed).
  /// [dt] is the timestep in seconds.
  /// Returns the current velocity estimate in m/s.
  double update(double linearAccelZ, double dt) {
    // 2nd-order Butterworth is overkill for prototype — apply simple EMA
    // to remove high-frequency sensor noise (cutoff ≈ 10 Hz).
    linearAccelZ = _lpf(linearAccelZ);

    // Outlier rejection: clip physically implausible accelerations (>30 m/s²)
    linearAccelZ = linearAccelZ.clamp(-30.0, 30.0);

    // Update rolling window
    _accelWindow.add(linearAccelZ);
    if (_accelWindow.length > _windowSize) _accelWindow.removeAt(0);

    // Stationary detection via rolling variance
    _isStationary = _rollingVariance() < _stationaryVarianceThreshold;

    if (_isStationary) {
      // ZUPT: zero-velocity update
      _velocity = 0.0;
      _displacement = 0.0; // also reset displacement at rest
    } else {
      _velocity += linearAccelZ * dt;
      _displacement += _velocity * dt;
    }

    return _velocity;
  }

  // ── Simple low-pass filter (EMA, α ≈ 0.8) ─────────────────────────────────
  double _prev = 0.0;
  static const double _alpha = 0.8;

  double _lpf(double x) {
    _prev = _alpha * _prev + (1.0 - _alpha) * x;
    return _prev;
  }

  // ── Rolling variance ───────────────────────────────────────────────────────
  double _rollingVariance() {
    if (_accelWindow.isEmpty) return 0.0;
    final n = _accelWindow.length;
    final mean = _accelWindow.fold(0.0, (s, x) => s + x) / n;
    return _accelWindow.fold(0.0, (s, x) => s + (x - mean) * (x - mean)) / n;
  }

  // ── Getters ───────────────────────────────────────────────────────────────
  bool get isStationary => _isStationary;
  double get velocity => _velocity;
  double get displacementM => _displacement;

  void reset() {
    _velocity = 0.0;
    _displacement = 0.0;
    _isStationary = true;
    _accelWindow.clear();
    _prev = 0.0;
  }
}
