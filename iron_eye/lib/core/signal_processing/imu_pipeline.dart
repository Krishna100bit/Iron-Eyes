import 'dart:async';
import '../models/imu_sample.dart';
import 'orientation_filter.dart';
import 'gravity_removal.dart';
import 'zupt_integrator.dart';
import 'rep_detector.dart';

export 'rep_detector.dart' show RepEvent;

/// Orchestrates the full signal processing pipeline for one exercise session.
///
/// Data flow (per sample, from 02_ARCHITECTURE.md Part D):
///   ImuSample → OrientationFilter → GravityRemoval → ZuptIntegrator
///               → RepDetector → RepEvent
///
/// Usage:
///   1. Call [calibrate] with stationary samples to set gyro bias + orientation.
///   2. Call [processSample] for each incoming IMU sample during the session.
///   3. Listen to [velocityStream] for real-time velocity (for live gauge).
///   4. Listen to [repStream] for completed rep events (to call addRep).
///   5. Call [reset] between sets if desired, or [dispose] when session ends.
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

  // ── Calibration ───────────────────────────────────────────────────────────

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

  // ── Processing ────────────────────────────────────────────────────────────

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

    // 3. ZUPT-constrained velocity integration
    final velocity = _zupt.update(linearAz, dt);
    _velocityController.add(velocity);

    // 4. Rep detection
    _repDetector.addSample(
      velocity,
      _zupt.displacementM,
      _zupt.isStationary,
      DateTime.fromMillisecondsSinceEpoch(sample.timestampMs),
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

  // ── Live state ────────────────────────────────────────────────────────────
  double get currentVelocity => _zupt.velocity;
  bool get isStationary => _zupt.isStationary;
  int get repCount => _repDetector.repCount;
}
