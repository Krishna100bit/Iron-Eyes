import 'dart:math';

/// Mahony complementary filter for IMU orientation estimation.
///
class OrientationFilter {
  // Mahony gains — Kp drives fast correction, Ki prevents gyro bias drift
  static const double _kp = 2.0;
  static const double _ki = 0.005;

  // Quaternion state [q0=w, q1=x, q2=y, q3=z]
  double _q0 = 1.0, _q1 = 0.0, _q2 = 0.0, _q3 = 0.0;

  // Integral error accumulators
  double _ix = 0.0, _iy = 0.0, _iz = 0.0;

  // Gyroscope bias estimated during calibration
  double _gyroBiasX = 0.0, _gyroBiasY = 0.0, _gyroBiasZ = 0.0;

  bool _calibrated = false;
  bool get isCalibrated => _calibrated;

  /// Call this with N stationary samples captured during the CALIBRATE command.
  /// Computes gyro bias and initial orientation from gravity direction.
  void calibrate(List<ImuRaw> samples) {
    if (samples.isEmpty) return;

    // Gyro bias = mean stationary gyro reading
    _gyroBiasX =
        samples.map((s) => s.gx).reduce((a, b) => a + b) / samples.length;
    _gyroBiasY =
        samples.map((s) => s.gy).reduce((a, b) => a + b) / samples.length;
    _gyroBiasZ =
        samples.map((s) => s.gz).reduce((a, b) => a + b) / samples.length;

    // Initial orientation from mean accel (the direction of gravity in sensor frame)
    final ax = samples.map((s) => s.ax).reduce((a, b) => a + b) / samples.length;
    final ay = samples.map((s) => s.ay).reduce((a, b) => a + b) / samples.length;
    final az = samples.map((s) => s.az).reduce((a, b) => a + b) / samples.length;

    _initFromAccel(ax, ay, az);
    _calibrated = true;
  }

  void _initFromAccel(double ax, double ay, double az) {
    final norm = sqrt(ax * ax + ay * ay + az * az);
    if (norm < 0.1) return;
    final nx = ax / norm;
    final ny = ay / norm;
    final nz = az / norm;

    final pitch = atan2(-nx, sqrt(ny * ny + nz * nz));
    final roll = atan2(ny, nz);

    final cr = cos(roll * 0.5);
    final sr = sin(roll * 0.5);
    final cp = cos(pitch * 0.5);
    final sp = sin(pitch * 0.5);

    _q0 = cr * cp;
    _q1 = sr * cp;
    _q2 = cr * sp;
    _q3 = -sr * sp;
  }

  bool _autoAligned = false;
  final List<double> _initAx = [];
  final List<double> _initAy = [];
  final List<double> _initAz = [];
  final List<double> _initGx = [];
  final List<double> _initGy = [];
  final List<double> _initGz = [];

  /// Process one IMU sample. Call at the sample rate (dt in seconds).
  void update({
    required double gx,
    required double gy,
    required double gz,
    required double ax,
    required double ay,
    required double az,
    required double dt,
  }) {
    // If not manually calibrated, auto-align to the gravity vector during first resting samples
    if (!_calibrated && !_autoAligned) {
      final aNorm = sqrt(ax * ax + ay * ay + az * az);
      if (aNorm > 8.0 && aNorm < 11.5) {
        _initAx.add(ax);
        _initAy.add(ay);
        _initAz.add(az);
        _initGx.add(gx);
        _initGy.add(gy);
        _initGz.add(gz);

        if (_initAx.length >= 20) {
          final avgAx = _initAx.reduce((a, b) => a + b) / _initAx.length;
          final avgAy = _initAy.reduce((a, b) => a + b) / _initAy.length;
          final avgAz = _initAz.reduce((a, b) => a + b) / _initAz.length;

          _gyroBiasX = _initGx.reduce((a, b) => a + b) / _initGx.length;
          _gyroBiasY = _initGy.reduce((a, b) => a + b) / _initGy.length;
          _gyroBiasZ = _initGz.reduce((a, b) => a + b) / _initGz.length;

          _initFromAccel(avgAx, avgAy, avgAz);
          _autoAligned = true;
        }
      }
    }

    // Remove gyro bias
    gx -= _gyroBiasX;
    gy -= _gyroBiasY;
    gz -= _gyroBiasZ;

    // Normalize accelerometer — skip correction during high-dynamics periods
    final aNorm = sqrt(ax * ax + ay * ay + az * az);
    if (aNorm > 0.5 && aNorm < 20.0) {
      final nx = ax / aNorm;
      final ny = ay / aNorm;
      final nz = az / aNorm;

      // Estimated gravity direction in body frame from current quaternion
      final vx = 2.0 * (_q1 * _q3 - _q0 * _q2);
      final vy = 2.0 * (_q0 * _q1 + _q2 * _q3);
      final vz = _q0 * _q0 - _q1 * _q1 - _q2 * _q2 + _q3 * _q3;

      // Cross product error: measured gravity × estimated gravity
      final ex = ny * vz - nz * vy;
      final ey = nz * vx - nx * vz;
      final ez = nx * vy - ny * vx;

      // Integral feedback
      _ix += _ki * ex * dt;
      _iy += _ki * ey * dt;
      _iz += _ki * ez * dt;

      // Apply PI correction to gyro
      gx += _kp * ex + _ix;
      gy += _kp * ey + _iy;
      gz += _kp * ez + _iz;
    }

    _integrateGyro(gx, gy, gz, dt);
  }

  void _integrateGyro(double gx, double gy, double gz, double dt) {
    final h = 0.5 * dt;
    final q0 = _q0 + (-_q1 * gx - _q2 * gy - _q3 * gz) * h;
    final q1 = _q1 + (_q0 * gx + _q2 * gz - _q3 * gy) * h;
    final q2 = _q2 + (_q0 * gy - _q1 * gz + _q3 * gx) * h;
    final q3 = _q3 + (_q0 * gz + _q1 * gy - _q2 * gx) * h;

    final norm = 1.0 / sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3);
    _q0 = q0 * norm;
    _q1 = q1 * norm;
    _q2 = q2 * norm;
    _q3 = q3 * norm;
  }

  /// Returns the vertical (world Z) component of the acceleration vector [ax,ay,az]
  /// expressed in body frame. This is the only axis needed for barbell rep detection.
  double worldAccelZ(double ax, double ay, double az) {
    // Third row of rotation matrix R (body → world)
    final r20 = 2.0 * (_q1 * _q3 - _q0 * _q2);
    final r21 = 2.0 * (_q2 * _q3 + _q0 * _q1);
    final r22 = _q0 * _q0 - _q1 * _q1 - _q2 * _q2 + _q3 * _q3;
    return r20 * ax + r21 * ay + r22 * az;
  }

  void reset() {
    _q0 = 1.0;
    _q1 = 0.0;
    _q2 = 0.0;
    _q3 = 0.0;
    _ix = 0.0;
    _iy = 0.0;
    _iz = 0.0;
  }
}

/// Lightweight struct for passing raw IMU values to calibrate()
class ImuRaw {
  final double ax, ay, az, gx, gy, gz;
  const ImuRaw(
      {required this.ax,
      required this.ay,
      required this.az,
      required this.gx,
      required this.gy,
      required this.gz});
}