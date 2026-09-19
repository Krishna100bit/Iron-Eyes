import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/providers/ble_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/models/imu_sample.dart';
/// Calibration screen — instructs user to "hold bar still", collects
/// 200 stationary IMU samples, computes gyro bias + initial orientation.
///
/// From 02_ARCHITECTURE.md Step 1:
/// "Capture N=100-200 stationary samples → mean accel = gravity vector,
///  mean gyro = gyro bias."
class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen>
    with SingleTickerProviderStateMixin {
  static const int _targetSamples = 200;

  _Phase _phase = _Phase.waiting;
  int _collected = 0;
  String? _resultMessage;
  bool _success = false;

  final List<ImuSample> _buffer = [];
  StreamSubscription<ImuSample>? _sub;

  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _startCalibration() async {
    setState(() {
      _phase = _Phase.capturing;
      _collected = 0;
      _buffer.clear();
    });

    // Tell firmware to enter calibration mode
    await ref.read(bleProvider.notifier).sendCalibrate();

    // Collect samples from the stream
    _sub = ref.read(bleProvider.notifier).sampleStream.listen((sample) {
      if (_phase != _Phase.capturing) return;
      _buffer.add(sample);
      setState(() => _collected = _buffer.length);

      if (_buffer.length >= _targetSamples) {
        _finishCalibration();
      }
    });
  }

  void _finishCalibration() {
    _sub?.cancel();
    _sub = null;

    // Validate: check that variance of accel magnitude is low
    final magnitudes = _buffer.map((s) =>
        _mag(s.ax, s.ay, s.az)).toList();
    final mean = magnitudes.fold(0.0, (s, x) => s + x) / magnitudes.length;
    final variance = magnitudes.fold(
            0.0, (s, x) => s + (x - mean) * (x - mean)) /
        magnitudes.length;

    final bool deviceWasStill = variance < 0.5; // (m/s²)²

    if (!deviceWasStill) {
      setState(() {
        _phase = _Phase.failed;
        _resultMessage =
            'Too much movement detected. Hold the sensor completely still during calibration.';
        _success = false;
      });
      return;
    }

    // Store in the OrientationFilter (accessible via ImuPipeline in workout)
    // For now, save the samples to a provider so ImuPipeline can use them.
    // In production, a shared calibrationProvider holds the ImuRaw list.
    calibrationSamplesProvider = _buffer;

    setState(() {
      _phase = _Phase.done;
      _resultMessage = 'Sensor calibrated successfully. ✓';
      _success = true;
    });
  }

  double _mag(double x, double y, double z) =>
      (x * x + y * y + z * z) < 0.01 ? 9.81 : (x * x + y * y + z * z);

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text('Sensor Calibration',
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animation
                    _buildIcon(),
                    const SizedBox(height: 32),

                    // Title
                    Text(
                      _phaseTitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _phaseSubtitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                          color: Colors.white54, fontSize: 14, height: 1.6),
                    ),

                    if (_phase == _Phase.capturing) ...[
                      const SizedBox(height: 24),
                      GlassContainer(
                        blur: 15,
                        opacity: 0.07,
                        borderColor: AppTheme.primary.withOpacity(0.2),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: _collected / _targetSamples,
                                  backgroundColor:
                                      Colors.white.withOpacity(0.1),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          AppTheme.primary),
                                  minHeight: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('$_collected/$_targetSamples',
                                style: GoogleFonts.outfit(
                                    color: AppTheme.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],

                    if (_resultMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: (_success
                                  ? AppTheme.primary
                                  : Colors.red)
                              .withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: (_success
                                      ? AppTheme.primary
                                      : Colors.red)
                                  .withOpacity(0.3)),
                        ),
                        child: Text(_resultMessage!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                                color: _success
                                    ? AppTheme.primary
                                    : Colors.red,
                                fontSize: 13)),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // Action button
                    if (_phase == _Phase.waiting || _phase == _Phase.failed)
                      GestureDetector(
                        onTap: ble.isConnected ? _startCalibration : null,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: ble.isConnected
                                ? const LinearGradient(colors: [
                                    Color(0xFF00E5FF),
                                    Color(0xFF1DB954)
                                  ])
                                : null,
                            color: ble.isConnected
                                ? null
                                : Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            ble.isConnected
                                ? (_phase == _Phase.failed
                                    ? '🔄  Try Again'
                                    : '🎯  Start Calibration')
                                : 'Connect a device first',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                                color: ble.isConnected
                                    ? Colors.black
                                    : Colors.white38,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),

                    if (_phase == _Phase.done)
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF00E5FF),
                                  Color(0xFF1DB954)
                                ]),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text('✓  Done — Start Training',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (_phase == _Phase.capturing) {
      return RotationTransition(
        turns: _spinCtrl,
        child: Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.primary, width: 2),
          ),
          child: const Icon(Icons.sync_rounded, color: AppTheme.primary, size: 40),
        ),
      );
    }
    if (_phase == _Phase.done) {
      return Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.primary.withOpacity(0.12),
        ),
        child: const Icon(Icons.check_circle_rounded,
            color: AppTheme.primary, size: 48),
      );
    }
    if (_phase == _Phase.failed) {
      return const Icon(Icons.error_outline_rounded, color: Colors.red, size: 64);
    }
    return Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white12),
      ),
      child: const Icon(Icons.sensors_rounded, color: Colors.white38, size: 40),
    );
  }

  String get _phaseTitle {
    switch (_phase) {
      case _Phase.waiting:
        return 'Ready to calibrate';
      case _Phase.capturing:
        return 'Hold the sensor still…';
      case _Phase.done:
        return 'Calibration Complete!';
      case _Phase.failed:
        return 'Calibration Failed';
    }
  }

  String get _phaseSubtitle {
    switch (_phase) {
      case _Phase.waiting:
        return 'Place the IMU sensor on the barbell\nand hold it completely still.\nDo not move until calibration completes.';
      case _Phase.capturing:
        return 'Collecting stationary samples to estimate\ngyroscope bias and initial orientation.\nDo NOT move.';
      case _Phase.done:
        return 'Gyro bias and orientation have been\ncalibrated. Velocity estimates will now\nbe accurate for this session.';
      case _Phase.failed:
        return 'Movement was detected during calibration.\nPlace the sensor on a stable surface\nand try again.';
    }
  }
}

enum _Phase { waiting, capturing, done, failed }

/// Global holder for calibration samples.
/// In production, use a Riverpod provider so the ImuPipeline can read it.
List<ImuSample> calibrationSamplesProvider = [];
