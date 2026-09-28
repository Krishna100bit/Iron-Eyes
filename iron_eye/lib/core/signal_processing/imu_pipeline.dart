import 'dart:async';
import 'dart:math' as math;
import '../models/imu_sample.dart';
import 'orientation_filter.dart';
import 'gravity_removal.dart';
import 'zupt_integrator.dart';
import 'rep_detector.dart';

export 'rep_detector.dart' show RepEvent;

/// Orchestrates the full signal processing pipeline for one exercise session.
///
class ImuPipeline {
  final OrientationFilter _orientation = OrientationFilter();
  final ZuptIntegrator _zupt = ZuptIntegrator();
  late final RepDetector _repDetector;

  final _velocityController = StreamController<double>.broadcast();
  final _repController = StreamController<RepEvent>.broadcast();

  Stream<double> get velocityStream => _velocityController.stream;
  Stream<RepEvent> get repStream => _repController.stream;

  /// Nominal sample interval in seconds (firmware transmits at ~100Hz)
  static const double _nominalDt = 0.01;

  int? _lastTimestampMs;

  ImuPipeline(String exercise) {
    _repDetector = RepDetector(
      exercise: exercise,
      onRepCompleted: (event) => _repController.add(event),
    );
  }

  /// Feed N stationary samples captured during the calibration command.
  /// Typically 100-200 samples (~1-2 seconds at 100Hz).
  void calibrate(List<ImuSample> staticSamples) {
    _orientation.calibrate(staticSamples
        .map((s) => ImuRaw(
              ax: s.ax, ay: s.ay, az: s.az,
              gx: s.gx, gy: s.gy, gz: s.gz,
            ))
        .toList());
  }

  bool get isCalibrated => _orientation.isCalibrated;

  /// Process a single IMU sample through the full pipeline.
  void processSample(ImuSample sample) {
    // Compute dt from consecutive timestamps, fall back to nominal
    double dt = _nominalDt;
    if (_lastTimestampMs != null) {
      final dtMs = sample.timestampMs - _lastTimestampMs!;
      if (dtMs > 0 && dtMs < 200) dt = dtMs / 1000.0;
    }
    _lastTimestampMs = sample.timestampMs;

    // 1. Update orientation (Mahony complementary filter)
    _orientation.update(
      gx: sample.gx, gy: sample.gy, gz: sample.gz,
      ax: sample.ax, ay: sample.ay, az: sample.az,
      dt: dt,
    );

    // 2. Project acceleration to world Z and remove gravity
    final worldAz = _orientation.worldAccelZ(sample.ax, sample.ay, sample.az);
    final linearAz = GravityRemoval.removeGravityVertical(worldAz);

    // 3. ZUPT-constrained velocity integration with gyro fusion
    final gyroMag = math.sqrt(sample.gx * sample.gx + sample.gy * sample.gy + sample.gz * sample.gz);
    final velocity = _zupt.update(linearAz, dt, gyroMag: gyroMag);
    _velocityController.add(velocity);

    // 4. Rep detection
    _repDetector.addSample(
      velocity,
      _zupt.displacementM,
      _zupt.isStationary,
      DateTime.fromMillisecondsSinceEpoch(sample.timestampMs),
      dt: dt,
    );
  }

  /// Reset between sets (keeps calibration)
  void resetSet() {
    _zupt.reset();
    _repDetector.reset();
    _lastTimestampMs = null;
  }

  /// Full reset including calibration (call when session ends)
  void resetFull() {
    _orientation.reset();
    _zupt.reset();
    _repDetector.reset();
    _lastTimestampMs = null;
  }

  void dispose() {
    _velocityController.close();
    _repController.close();
  }
  double get currentVelocity => _zupt.velocity;
  bool get isStationary => _zupt.isStationary;
  int get repCount => _repDetector.repCount;

  RepEvent? getAndConsumeLatestRepEvent() => _repDetector.getAndConsumeLatestRepEvent();
  RepEvent? getActiveConcentricMetrics() => _repDetector.getActiveConcentricMetrics();
  RepEvent? get lastCompletedRepEvent => _repDetector.lastCompletedRepEvent;
}