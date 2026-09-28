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

class _ExerciseConfig {
  final double eccentricStartVel;
  final int minDurationMs;
  final double minPeakVel;
  final double minDisplacement;

  const _ExerciseConfig({
    required this.eccentricStartVel,
    required this.minDurationMs,
    required this.minPeakVel,
    required this.minDisplacement,
  });
}

/// Rep state machine: STATIONARY → ECCENTRIC → CONCENTRIC → STATIONARY → repeat.
class RepDetector {
  static const _defaultConfig = _ExerciseConfig(
    eccentricStartVel: -0.10,
    minDurationMs: 220,
    minPeakVel: 0.16,
    minDisplacement: 0.12,
  );

  static _ExerciseConfig _getConfig(String exercise) {
    final lower = exercise.toLowerCase();
    if (lower.contains('squat')) {
      return const _ExerciseConfig(
        eccentricStartVel: -0.10,
        minDurationMs: 220,
        minPeakVel: 0.16,
        minDisplacement: 0.12,
      );
    }
    if (lower.contains('bench') || lower.contains('push up')) {
      return const _ExerciseConfig(
        eccentricStartVel: -0.08,
        minDurationMs: 200,
        minPeakVel: 0.15,
        minDisplacement: 0.10,
      );
    }
    return _defaultConfig;
  }

  final _ExerciseConfig _cfg;
  final void Function(RepEvent) onRepCompleted;

  _Phase _phase = _Phase.stationary;
  int _repCount = 0;

  final List<double> _concentricVels = [];
  double _peakVelocity = 0.0;
  double _concentricDisplacement = 0.0;
  DateTime? _concentricStart;
  DateTime? _eccentricStart;
  DateTime? _lastRepCompletedTime;
  double _minEccentricVel = 0.0;
  double _maxDescentDepth = 0.0;

  double _referenceTopDisplacement = 0.0;
  bool _isArmedAtTop = false;
  int _stableTopSamples = 0;

  RepEvent? _lastCompletedRepEvent;
  RepEvent? get lastCompletedRepEvent => _lastCompletedRepEvent;

  RepEvent? getAndConsumeLatestRepEvent() {
    final e = _lastCompletedRepEvent;
    _lastCompletedRepEvent = null;
    return e;
  }

  RepEvent? getActiveConcentricMetrics() {
    if (_concentricVels.isEmpty) return null;
    final mean = _concentricVels.fold(0.0, (s, v) => s + v) / _concentricVels.length;
    final quality = (mean > 0.20 && _peakVelocity > 0.28) ? 'good' : 'low';
    return RepEvent(
      repNumber: _repCount + 1,
      meanConcentricVelocity: mean,
      peakVelocity: _peakVelocity,
      durationMs: _concentricStart != null ? DateTime.now().difference(_concentricStart!).inMilliseconds : 350,
      displacementM: _concentricDisplacement > 0 ? _concentricDisplacement : _maxDescentDepth,
      dataQuality: quality,
    );
  }

  RepDetector({required String exercise, required this.onRepCompleted})
      : _cfg = _getConfig(exercise);

  void addSample(
      double velocity, double displacementM, bool isStationary, DateTime ts,
      {double dt = 0.01}) {
    // 400ms refractory lockout after completing a rep to prevent double counting
    if (_lastRepCompletedTime != null &&
        ts.difference(_lastRepCompletedTime!).inMilliseconds < 400) {
      return;
    }

    switch (_phase) {
      case _Phase.stationary:
        // 1. First take the stable top starting position
        if (isStationary || velocity.abs() < 0.08) {
          _stableTopSamples++;
          if (_stableTopSamples >= 8) {
            _isArmedAtTop = true;
            _referenceTopDisplacement = displacementM;
          }
        } else {
          _stableTopSamples = 0;
        }

        // 2. Initiate downward movement (eccentric) only once stable position confirmed
        if (_isArmedAtTop && velocity < _cfg.eccentricStartVel) {
          _phase = _Phase.eccentric;
          _eccentricStart = ts;
          _minEccentricVel = velocity;
          _maxDescentDepth = 0.0;
          _concentricVels.clear();
          _peakVelocity = 0.0;
          _concentricDisplacement = 0.0;
          _stableTopSamples = 0;
        }
        break;

      case _Phase.eccentric:
        if (velocity < _minEccentricVel) {
          _minEccentricVel = velocity;
        }
        final currentDescent = (_referenceTopDisplacement - displacementM);
        if (currentDescent > _maxDescentDepth) {
          _maxDescentDepth = currentDescent;
        }

        // Timeout guard: if descent hangs > 5s, reset
        if (_eccentricStart != null &&
            ts.difference(_eccentricStart!).inMilliseconds > 5000) {
          _phase = _Phase.stationary;
          _isArmedAtTop = false;
          break;
        }

        // Reversal at bottom: must have achieved real downward velocity (<= -0.12 m/s)
        // and downward depth (>= 0.10 m), and velocity has now rebounded into positive drive (>= 0.05 m/s)!
        if (_minEccentricVel <= -0.12 &&
            _maxDescentDepth >= 0.10 &&
            velocity >= 0.05) {
          _phase = _Phase.concentric;
          _concentricStart = ts;
          _concentricVels.clear();
          _concentricVels.add(velocity);
          _peakVelocity = velocity;
          _concentricDisplacement = 0.0;
        }
        break;

      case _Phase.concentric:
        // Strictly record upward velocity (bottom to top)
        if (velocity > 0) {
          _concentricVels.add(velocity);
          _concentricDisplacement += velocity * dt;
          if (velocity > _peakVelocity) {
            _peakVelocity = velocity;
          }
        }

        final durationMs = _concentricStart != null
            ? ts.difference(_concentricStart!).inMilliseconds
            : 0;

        // Timeout guard: if concentric takes > 4.5s
        if (durationMs > 4500) {
          _phase = _Phase.stationary;
          _isArmedAtTop = false;
          break;
        }

        // Concentric completion conditions:
        // 1. Must have attained required peak upward velocity and minimal drive duration
        final bool hadGoodDrive = _peakVelocity >= _cfg.minPeakVel && durationMs >= _cfg.minDurationMs;

        // 2. Must have returned back to the top starting position
        final currentDistanceFromTop = (_referenceTopDisplacement - displacementM).abs();
        final bool returnedToTop = currentDistanceFromTop <= 0.15 || _concentricDisplacement >= _maxDescentDepth * 0.65;

        // 3. Finishes when decelerating back to stationary at the top lockout
        final bool reachedLockout = hadGoodDrive && returnedToTop &&
            (isStationary || velocity <= 0.08 || velocity < 0.0);

        if (reachedLockout) {
          // Bottom-to-top mean concentric velocity
          final mean = _concentricVels.isEmpty
              ? 0.0
              : _concentricVels.fold(0.0, (s, v) => s + v) / _concentricVels.length;

          _repCount++;
          _lastRepCompletedTime = ts;
          final quality = (mean > 0.20 && _peakVelocity > 0.28) ? 'good' : 'low';

          final event = RepEvent(
            repNumber: _repCount,
            meanConcentricVelocity: mean,
            peakVelocity: _peakVelocity,
            durationMs: durationMs,
            displacementM: _concentricDisplacement > 0 ? _concentricDisplacement : _maxDescentDepth,
            dataQuality: quality,
          );

          _lastCompletedRepEvent = event;
          onRepCompleted(event);

          _phase = _Phase.stationary;
          _isArmedAtTop = false;
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
    _eccentricStart = null;
    _lastRepCompletedTime = null;
    _minEccentricVel = 0.0;
    _maxDescentDepth = 0.0;
    _referenceTopDisplacement = 0.0;
    _isArmedAtTop = false;
    _stableTopSamples = 0;
    _lastCompletedRepEvent = null;
  }

  _Phase get phase => _phase;
  int get repCount => _repCount;
}

enum _Phase { stationary, eccentric, concentric }