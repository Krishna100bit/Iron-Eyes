/// Output from a completed rep.
class RepEvent {
  final int repNumber;
  final double meanConcentricVelocity; // m/s
  final double peakVelocity; // m/s
  final int durationMs;
  final double displacementM;
  final String dataQuality; // 'good' | 'low'

  const RepEvent({
    required this.repNumber,
    required this.meanConcentricVelocity,
    required this.peakVelocity,
    required this.durationMs,
    required this.displacementM,
    required this.dataQuality,
  });
}

/// Exercise-specific threshold config (from 02_ARCHITECTURE.md Part H).
class _ExerciseConfig {
  /// Velocity threshold (m/s, negative) to detect start of eccentric phase
  final double eccentricStartVel;

  /// Minimum concentric phase duration in ms (reject micro-adjustments)
  final double minDurationMs;

  const _ExerciseConfig({
    required this.eccentricStartVel,
    required this.minDurationMs,
  });
}

/// Rep state machine: STATIONARY → ECCENTRIC → CONCENTRIC → STATIONARY → repeat.
///
/// From 02_ARCHITECTURE.md Part H:
/// "Both lifts share a shape: stationary → eccentric (bar moving down) →
///  brief pause → concentric (bar moving up) → stationary."
class RepDetector {
  // Thresholds tuned per 02_ARCHITECTURE.md note on exercise-specific config
  static const _configs = {
    'Squat': _ExerciseConfig(eccentricStartVel: -0.12, minDurationMs: 500),
    'Bench Press':
        _ExerciseConfig(eccentricStartVel: -0.10, minDurationMs: 300),
  };
  static const _defaultConfig =
      _ExerciseConfig(eccentricStartVel: -0.10, minDurationMs: 350);

  final _ExerciseConfig _cfg;
  final void Function(RepEvent) onRepCompleted;

  _Phase _phase = _Phase.stationary;
  int _repCount = 0;

  final List<double> _concentricVels = [];
  double _peakVelocity = 0.0;
  double _concentricDisplacement = 0.0;
  DateTime? _concentricStart;

  RepDetector({required String exercise, required this.onRepCompleted})
      : _cfg = _configs[exercise] ?? _defaultConfig;

  /// Call with each new velocity sample and the ZUPT stationary flag.
  void addSample(
      double velocity, double displacementM, bool isStationary, DateTime ts) {
    switch (_phase) {
      case _Phase.stationary:
        // Detect start of eccentric (downward) motion
        if (!isStationary && velocity < _cfg.eccentricStartVel) {
          _phase = _Phase.eccentric;
          _concentricVels.clear();
          _peakVelocity = 0.0;
          _concentricDisplacement = 0.0;
        }
        break;

      case _Phase.eccentric:
        // Wait for velocity to cross zero → start of concentric phase
        if (velocity >= -0.02) {
          _phase = _Phase.concentric;
          _concentricStart = ts;
        }
        break;

      case _Phase.concentric:
        _concentricVels.add(velocity);
        _concentricDisplacement += displacementM.abs();
        if (velocity > _peakVelocity) _peakVelocity = velocity;

        // Rep ends when we return to stationary
        if (isStationary) {
          final durationMs =
              ts.difference(_concentricStart!).inMilliseconds;

          if (durationMs >= _cfg.minDurationMs) {
            // Valid rep
            final mean = _concentricVels.isEmpty
                ? 0.0
                : _concentricVels.fold(0.0, (s, v) => s + v) /
                    _concentricVels.length;

            _repCount++;
            final quality = mean > 0.25 ? 'good' : 'low';

            onRepCompleted(RepEvent(
              repNumber: _repCount,
              meanConcentricVelocity: mean,
              peakVelocity: _peakVelocity,
              durationMs: durationMs,
              displacementM: _concentricDisplacement,
              dataQuality: quality,
            ));
          }
          // Return to waiting — whether rep was valid or not
          _phase = _Phase.stationary;
        }
        break;
    }
  }

  void reset() {
    _phase = _Phase.stationary;
    _repCount = 0;
    _concentricVels.clear();
    _peakVelocity = 0.0;
    _concentricDisplacement = 0.0;
    _concentricStart = null;
  }

  _Phase get phase => _phase;
  int get repCount => _repCount;
}

enum _Phase { stationary, eccentric, concentric }
