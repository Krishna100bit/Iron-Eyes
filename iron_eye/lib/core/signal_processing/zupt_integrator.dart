/// ZUPT-constrained velocity integrator.
///
class ZuptIntegrator {
  // Rolling variance threshold — calibrated for human-held barbell/dumbbell stability
  static const double _stationaryVarianceThreshold = 0.18; // (m/s²)²
  static const int _windowSize = 14;

  double _velocity = 0.0;
  double _displacement = 0.0;
  bool _isStationary = true;

  final List<double> _accelWindow = [];

  /// Process one sample of linear acceleration (gravity already removed).
  /// [dt] is the timestep in seconds.
  /// [gyroMag] is optional gyroscope angular rate magnitude in rad/s.
  /// Returns the current velocity estimate in m/s.
  double update(double linearAccelZ, double dt, {double? gyroMag}) {
    // Low-pass filter to reject high-frequency sensor noise
    linearAccelZ = _lpf(linearAccelZ);

    // Outlier rejection
    linearAccelZ = linearAccelZ.clamp(-25.0, 25.0);

    // Deadband filter: zero out micro-accelerations from noise
    if (linearAccelZ.abs() < 0.06) {
      linearAccelZ = 0.0;
    }

    // Update rolling window
    _accelWindow.add(linearAccelZ);
    if (_accelWindow.length > _windowSize) _accelWindow.removeAt(0);

    // Stationary detection: variance + low absolute linear accel + low gyro rate
    final varA = _rollingVariance();
    final bool accelQuiet = varA < _stationaryVarianceThreshold && linearAccelZ.abs() < 0.50;
    final bool gyroQuiet = gyroMag == null || gyroMag < 0.38;

    _isStationary = accelQuiet && gyroQuiet;

    if (_isStationary) {
      // ZUPT: zero-velocity update
      _velocity = 0.0;
      // Gentle displacement decay when resting stationary to prevent drift
      _displacement *= 0.985;
    } else {
      _velocity += linearAccelZ * dt;
      // Damping factor prevents open-loop integration divergence
      _velocity *= 0.995;
      _displacement += _velocity * dt;
    }

    return _velocity;
  }
  double _prev = 0.0;
  static const double _alpha = 0.75;

  double _lpf(double x) {
    _prev = _alpha * _prev + (1.0 - _alpha) * x;
    return _prev;
  }
  double _rollingVariance() {
    if (_accelWindow.isEmpty) return 0.0;
    final n = _accelWindow.length;
    final mean = _accelWindow.fold(0.0, (s, x) => s + x) / n;
    return _accelWindow.fold(0.0, (s, x) => s + (x - mean) * (x - mean)) / n;
  }
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