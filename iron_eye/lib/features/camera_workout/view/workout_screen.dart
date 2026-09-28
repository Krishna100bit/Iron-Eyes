import 'dart:async';
import 'dart:math' as math;
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../../core/cv/pose_detector_service.dart';
import '../../../core/cv/pose_painter.dart';
import '../../../core/cv/angle_calculator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/active_session_provider.dart';
import '../../../core/providers/workout_history_provider.dart';
import '../../../core/providers/ble_provider.dart';
import '../../../core/models/workout_session.dart';
import '../../../core/models/rep_card.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/signal_processing/imu_pipeline.dart';
import '../../../core/signal_processing/velocity_loss.dart';
import '../../../core/signal_processing/load_velocity_model.dart';
import '../../../core/signal_processing/fatigue_engine.dart';
import '../../device/view/device_screen.dart';
import '../../device/view/calibration_screen.dart' show calibrationSamplesProvider;

// All exercises
final List<Map<String, dynamic>> exercises = [
  {'name': 'Squat',          'group': 'Lower Body', 'type': 'Barbell',    'icon': Icons.accessibility_new_rounded},
  {'name': 'Dumbbell Squat', 'group': 'Lower Body', 'type': 'Bilateral',  'icon': Icons.accessibility_new_rounded},
  {'name': 'Goblet Squat',   'group': 'Lower Body', 'type': 'Bilateral',  'icon': Icons.accessibility_new_rounded},
  {'name': 'Front Squat',    'group': 'Lower Body', 'type': 'Barbell',    'icon': Icons.accessibility_new_rounded},
  {'name': 'Deadlift',       'group': 'Lower Body', 'type': 'Barbell',    'icon': Icons.fitness_center},
  {'name': 'Incline Bench',  'group': 'Upper Body', 'type': 'Barbell',    'icon': Icons.fitness_center},
  {'name': 'Pull Up',        'group': 'Upper Body', 'type': 'Bodyweight', 'icon': Icons.fitness_center},
  {'name': 'Chin Up',        'group': 'Upper Body', 'type': 'Bodyweight', 'icon': Icons.fitness_center},
  {'name': 'Push Up',        'group': 'Upper Body', 'type': 'Bodyweight', 'icon': Icons.fitness_center},
  {'name': 'Dips',           'group': 'Upper Body', 'type': 'Bodyweight', 'icon': Icons.fitness_center},
  {'name': 'Bicep Curl',     'group': 'Upper Body', 'type': 'Bilateral',  'icon': Icons.fitness_center},
  {'name': 'Hammer Curl',    'group': 'Upper Body', 'type': 'Bilateral',  'icon': Icons.fitness_center},
  {'name': 'Tricep Extension','group':'Upper Body', 'type': 'Bilateral',  'icon': Icons.fitness_center},
  {'name': 'Skull Crusher',  'group': 'Upper Body', 'type': 'Barbell',    'icon': Icons.fitness_center},
  {'name': 'Lateral Raise',  'group': 'Upper Body', 'type': 'Bilateral',  'icon': Icons.fitness_center},
  {'name': 'Front Raise',    'group': 'Upper Body', 'type': 'Bilateral',  'icon': Icons.fitness_center},
  {'name': 'Face Pull',      'group': 'Upper Body', 'type': 'Bilateral',  'icon': Icons.fitness_center},
  {'name': 'Lat Pulldown',   'group': 'Upper Body', 'type': 'Bilateral',  'icon': Icons.fitness_center},
  {'name': 'Seated Row',     'group': 'Upper Body', 'type': 'Bilateral',  'icon': Icons.fitness_center},
  {'name': 'Shrugs',         'group': 'Upper Body', 'type': 'Barbell',    'icon': Icons.fitness_center},
  {'name': 'Leg Press',      'group': 'Lower Body', 'type': 'Bilateral',  'icon': Icons.accessibility_new_rounded},
  {'name': 'Leg Extension',  'group': 'Lower Body', 'type': 'Bilateral',  'icon': Icons.accessibility_new_rounded},
  {'name': 'Leg Curl',       'group': 'Lower Body', 'type': 'Bilateral',  'icon': Icons.accessibility_new_rounded},
  {'name': 'Calf Raise',     'group': 'Lower Body', 'type': 'Bodyweight', 'icon': Icons.directions_walk_rounded},
  {'name': 'Lunge',          'group': 'Lower Body', 'type': 'Bilateral',  'icon': Icons.directions_walk_rounded},
  {'name': 'Bulgarian Squat','group': 'Lower Body', 'type': 'Bilateral',  'icon': Icons.accessibility_new_rounded},
  {'name': 'Hip Thrust',     'group': 'Lower Body', 'type': 'Barbell',    'icon': Icons.accessibility_new_rounded},
  {'name': 'Glute Bridge',   'group': 'Lower Body', 'type': 'Bodyweight', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Good Morning',   'group': 'Lower Body', 'type': 'Barbell',    'icon': Icons.fitness_center},
  {'name': 'Kettlebell Swing','group':'Full Body',  'type': 'Bilateral',  'icon': Icons.fitness_center},
  {'name': 'Clean and Jerk', 'group': 'Full Body',  'type': 'Barbell',    'icon': Icons.fitness_center},
  {'name': 'Snatch',         'group': 'Full Body',  'type': 'Barbell',    'icon': Icons.fitness_center},
  {'name': 'Crunch',         'group': 'Core',       'type': 'Bodyweight', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Sit Up',         'group': 'Core',       'type': 'Bodyweight', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Russian Twist',  'group': 'Core',       'type': 'Bodyweight', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Leg Raise',      'group': 'Core',       'type': 'Bodyweight', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Plank',          'group': 'Core',       'type': 'Duration',   'icon': Icons.timer_outlined},
  {'name': 'Wall Sit',       'group': 'Lower Body', 'type': 'Duration',   'icon': Icons.timer_outlined},
  {'name': 'Mountain Climber','group':'Core',       'type': 'Cardio',     'icon': Icons.directions_run_rounded},
  {'name': 'High Knees',     'group': 'Full Body',  'type': 'Cardio',     'icon': Icons.directions_run_rounded},
  {'name': 'Jumping Jack',   'group': 'Full Body',  'type': 'Cardio',     'icon': Icons.directions_run_rounded},
  {'name': 'Burpee',         'group': 'Full Body',  'type': 'Cardio',     'icon': Icons.directions_run_rounded},
  {'name': 'Box Jump',       'group': 'Lower Body', 'type': 'Bodyweight', 'icon': Icons.directions_run_rounded},
];
// WORKOUT SCREEN  (Exercise Selector)
class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  String? _selectedExercise;
  String? _selectedType;
  double? _loadKg;
  double? _targetRpe;
  bool _isCalibrating = false;
  bool _hasCalibrated = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider);
    if (session != null && session.isActive) {
      return _LiveSessionScreen(onStop: _stopSession, onCancel: _cancelSession);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildBLEStatus(),
            Expanded(child: _buildExerciseSelector()),
            _buildStartButton(),
          ],
        ),
      ),
    );
  }

  void _stopSession() {
    ref.read(bleProvider.notifier).sendStopSession();
    final session = ref.read(activeSessionProvider.notifier).stopSession();
    if (session != null) {
      if (session.totalReps > 0) {
        ref.read(workoutHistoryProvider.notifier).addSession(session);
      }
      _showSummary(session);
    }
    setState(() {
      _loadKg = null;
      _targetRpe = null;
      _isCalibrating = false;
      _hasCalibrated = false;
    });
  }

  void _cancelSession() {
    ref.read(bleProvider.notifier).sendStopSession();
    ref.read(activeSessionProvider.notifier).cancelSession();
    setState(() {
      _loadKg = null;
      _targetRpe = null;
      _isCalibrating = false;
      _hasCalibrated = false;
    });
  }

  void _showSummary(WorkoutSession s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SessionSummarySheet(session: s),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WORKOUT',
              style: GoogleFonts.outfit(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3)),
          Text('Select Exercise',
              style: GoogleFonts.outfit(
                  color: AppTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBLEStatus() {
    final ble = ref.watch(bleProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const DeviceScreen())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ble.isConnected
                  ? AppTheme.primary.withOpacity(0.4)
                  : const Color(0xFF2A2A2A),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ble.isConnected ? AppTheme.primary : const Color(0xFFFF3333),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ble.isConnected
                      ? '${ble.deviceName}  ·  Batt ${ble.batteryPercent}%  ·  ${ble.isDeviceCalibrated ? "Calibrated" : "Not Calibrated"}'
                      : ble.isScanning ? 'Scanning for IMU puck...' : 'IMU Puck Not Connected — Tap to Connect',
                  style: GoogleFonts.outfit(color: AppTheme.textSecondary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_selectedType == 'VBT' && ble.isConnected && !_hasCalibrated)
                GestureDetector(
                  onTap: () async {
                    if (_isCalibrating) return;
                    setState(() => _isCalibrating = true);
                    
                    // Send the 0x03 calibration command to the hardware
                    await ref.read(bleProvider.notifier).sendCalibrate();
                    
                    // Wait for the 3-second hardware calibration to finish
                    await Future.delayed(const Duration(seconds: 3));
                    
                    if (mounted) {
                      setState(() {
                         _isCalibrating = false;
                         _hasCalibrated = true;
                      });
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isCalibrating ? Colors.green.withOpacity(0.15) : AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _isCalibrating ? Colors.green : AppTheme.primary.withOpacity(0.4)),
                    ),
                    child: Text(
                      _isCalibrating ? '✅ Calibrating...' : 'Calibrate',
                      style: GoogleFonts.outfit(
                        color: _isCalibrating ? Colors.green : AppTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold
                      )
                    ),
                  ),
                )
              else if (!_hasCalibrated)
                Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseSelector() {
    final groups = ['All', 'Upper Body', 'Lower Body', 'Full Body'];
    return DefaultTabController(
      length: groups.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
            indicatorColor: AppTheme.primary,
            indicatorWeight: 2,
            dividerColor: Colors.transparent,
            padding: const EdgeInsets.only(left: 16),
            tabs: groups.map((g) => Tab(text: g)).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: groups.map((group) {
                final filtered = group == 'All'
                    ? exercises
                    : exercises.where((e) => e['group'] == group).toList();
                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final ex = filtered[i];
                    final isSelected = _selectedExercise == ex['name'];
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedExercise = ex['name'];
                        _selectedType = ex['type'];
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primary.withOpacity(0.1)
                              : AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? AppTheme.primary : const Color(0xFF232323),
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: AppTheme.primary.withOpacity(0.15), blurRadius: 12)]
                              : [],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primary.withOpacity(0.18)
                                    : const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(ex['icon'] as IconData,
                                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                                  size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ex['name'],
                                      style: GoogleFonts.outfit(
                                          color: AppTheme.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                  Text(ex['group'],
                                      style: GoogleFonts.outfit(
                                          color: AppTheme.textSecondary, fontSize: 12)),
                                ],
                              ),
                            ),
                            _TypeBadge(type: ex['type']),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.check_circle_rounded,
                                  color: AppTheme.primary, size: 20),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    final ready = _selectedExercise != null;
    final isBarbellExercise =
        _selectedExercise == 'Squat' || _selectedExercise == 'Bench Press';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: GestureDetector(
        onTap: ready
            ? () => _showPreSessionModal(
                _selectedExercise!, _selectedType ?? 'Bodyweight', isBarbellExercise)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: ready
                ? const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: ready ? null : AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: ready
                ? [BoxShadow(
                    color: AppTheme.primary.withOpacity(0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 6))]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.settings_rounded,
                  color: ready ? Colors.black : AppTheme.textSecondary, size: 22),
              const SizedBox(width: 8),
              Text(
                ready ? 'Set Up  \u203a  $_selectedExercise' : 'Select an Exercise',
                style: GoogleFonts.outfit(
                  color: ready ? Colors.black : AppTheme.textSecondary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  void _showPreSessionModal(
      String exercise, String type, bool isBarbellExercise) {
    final loadCtrl = TextEditingController(
        text: _loadKg != null ? _loadKg!.toStringAsFixed(1) : '');
    double rpe = _targetRpe ?? 7.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          margin: const EdgeInsets.only(top: 60),
          decoration: const BoxDecoration(
            color: Color(0xFF111111),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 20),
                  Text('Session Setup',
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  Text(exercise,
                      style: GoogleFonts.outfit(
                          color: AppTheme.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    isBarbellExercise
                        ? 'Enter load to enable e1RM tracking'
                        : 'Set your target RPE for this session',
                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 20),
                  if (isBarbellExercise) ...[
                    Text('Load (kg)',
                        style: GoogleFonts.outfit(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: loadCtrl,
                      onChanged: (_) => setModal(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'e.g. 100',
                        hintStyle: GoogleFonts.outfit(color: Colors.white24),
                        suffixText: 'kg',
                        suffixStyle: GoogleFonts.outfit(color: Colors.white38),
                        filled: true,
                        fillColor: AppTheme.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF2A2A2A))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF2A2A2A))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppTheme.primary, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text('Target RPE: ${rpe.toInt()}',
                      style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      activeTrackColor: AppTheme.primary,
                      inactiveTrackColor: const Color(0xFF2A2A2A),
                      thumbColor: AppTheme.primary,
                      overlayColor: AppTheme.primary.withOpacity(0.12),
                    ),
                    child: Slider(
                      value: rpe,
                      min: 5,
                      max: 10,
                      divisions: 10,
                      onChanged: (v) => setModal(() => rpe = v),
                    ),
                  ),
                  Row(
                    children: [
                      Text('5  Easy', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 10)),
                      const Spacer(),
                      Text('10  Max', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Builder(
                    builder: (context) {
                      final bool canStart = !isBarbellExercise || loadCtrl.text.trim().isNotEmpty;
                      return GestureDetector(
                        onTap: canStart ? () {
                          Navigator.pop(ctx);
                          final load = isBarbellExercise
                              ? double.tryParse(loadCtrl.text)
                              : null;
                          setState(() {
                            _loadKg = load;
                            _targetRpe = rpe;
                          });
                          ref.read(activeSessionProvider.notifier).startSession(
                            exercise, type,
                            loadKg: load,
                            targetRpe: rpe,
                          );
                          ref.read(bleProvider.notifier).sendStartSession();
                        } : null,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: canStart ? const LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)]) : null,
                            color: canStart ? null : AppTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text('\u25b6  Start Session',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                  color: canStart ? Colors.black : Colors.white24,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ),
                      );
                    }
                  ),
                ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// LIVE SESSION SCREEN  (gpath.gym style — premium glassmorphism)
class _LiveSessionScreen extends ConsumerStatefulWidget {
  final VoidCallback onStop;
  final VoidCallback onCancel;
  const _LiveSessionScreen({required this.onStop, required this.onCancel});

  @override
  ConsumerState<_LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends ConsumerState<_LiveSessionScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;
  final _rng = Random();
  ImuPipeline? _pipeline;
  VelocityLoss _vlCalc = VelocityLoss();
  LoadVelocityModel? _e1rmModel;
  FatigueEngine _fatigueEngine = FatigueEngine();
  FatigueResult? _fatigueResult;
  double? _velocityLossPercent;
  double? _estimated1rm;
  String _e1rmConfidence = '';

  StreamSubscription<dynamic>? _bleSub;
  StreamSubscription<RepEvent>? _repSub;
  StreamSubscription<double>? _velSub;

  CameraController? _cameraController;
  final _poseService = PoseDetectorService();
  List<Pose> _poses = [];
  bool _isCameraInitialized = false;
  bool _cameraEnabled = true;
  CameraLensDirection _cameraDirection = CameraLensDirection.back;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
          ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPipeline();
      _initCamera();
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      
      // Try to get requested camera
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == _cameraDirection,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      _isCameraInitialized = true;

      if (mounted) {
        setState(() {});
        _cameraController!.startImageStream((image) async {
          if (!mounted || !_cameraEnabled) return;
          final poses = await _poseService.processCameraImage(
            image,
            camera.sensorOrientation,
            camera.lensDirection,
          );
          
          // null means previous frame inference was still busy or skipped.
          // DO NOT clear or touch _poses so the skeleton never flickers!
          if (poses == null) return;

          final validPoses = poses.where((p) => AngleCalculator.isValidHuman(p)).toList();

          if (mounted) {
            if (validPoses.isNotEmpty) {
              _emptyPoseFrameCount = 0;
              _updateSmoothedLandmarks(validPoses.first);
              setState(() {
                _poses = validPoses;
              });
              _processPoses(validPoses);
            } else {
              _emptyPoseFrameCount++;
              // Only clear skeleton if person has genuinely left the view for 5+ completed inferences
              if (_emptyPoseFrameCount >= 5) {
                _smoothedLandmarks.clear();
                _smoothedLikelihoods.clear();
                setState(() {
                  _poses = [];
                });
                _resetTrackingState();
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _teardownAndStop() async {
    ref.read(bleProvider.notifier).sendStopSession();
    if (_cameraController != null) {
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      await _cameraController!.dispose();
      _cameraController = null;
    }
    widget.onStop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_cameraController != null) {
        if (_cameraController!.value.isStreamingImages) {
          _cameraController!.stopImageStream().then((_) {
            _cameraController!.dispose();
            _cameraController = null;
          }).catchError((_) {});
        } else {
          _cameraController!.dispose();
          _cameraController = null;
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null) {
        _initCamera();
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameraController == null) return;
    setState(() => _isCameraInitialized = false);
    
    if (_cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
    }
    await _cameraController!.dispose();
    _cameraController = null;
    
    _cameraDirection = _cameraDirection == CameraLensDirection.front 
        ? CameraLensDirection.back 
        : CameraLensDirection.front;
        
    await _initCamera();
  }

  int _trackingState = 0; // 0=idle/seeking, 1=armed/ready, 2=descending, 3=bottom/ascending, 4=lockout cooldown
  double? _smoothedAngle;
  DateTime? _lastStateChange;
  double _lowestAngleInRep = 180.0;
  DateTime? _bottomTime;
  DateTime? _descentStartTime;
  DateTime? _lastCameraRepTime;
  DateTime? _lastImuRepTime;
  double? _standingHipY;
  int _consecutiveStandingFrames = 0;
  int _consecutiveBottomFrames = 0;
  int _emptyPoseFrameCount = 0;

  final Map<PoseLandmarkType, Offset> _smoothedLandmarks = {};
  final Map<PoseLandmarkType, double> _smoothedLikelihoods = {};

  void _updateSmoothedLandmarks(Pose pose) {
    const alpha = 0.65;
    for (final entry in pose.landmarks.entries) {
      final type = entry.key;
      final landmark = entry.value;
      final currentPos = Offset(landmark.x, landmark.y);

      if (_smoothedLandmarks.containsKey(type)) {
        final prevPos = _smoothedLandmarks[type]!;
        _smoothedLandmarks[type] = Offset(
          prevPos.dx * (1.0 - alpha) + currentPos.dx * alpha,
          prevPos.dy * (1.0 - alpha) + currentPos.dy * alpha,
        );
        final prevLikelihood = _smoothedLikelihoods[type] ?? landmark.likelihood;
        _smoothedLikelihoods[type] = prevLikelihood * (1.0 - alpha) + landmark.likelihood * alpha;
      } else {
        _smoothedLandmarks[type] = currentPos;
        _smoothedLikelihoods[type] = landmark.likelihood;
      }
    }
  }

  void _resetTrackingState() {
    _trackingState = 0;
    _smoothedAngle = null;
    _lowestAngleInRep = 180.0;
    _descentStartTime = null;
    _bottomTime = null;
    _standingHipY = null;
    _consecutiveStandingFrames = 0;
    _consecutiveBottomFrames = 0;
  }

  // Live camera-tracked form metrics (attached to reps in hybrid mode)
  int? _liveCameraFormScore;
  String _liveCameraFormGrade = '—';
  List<String> _liveCameraFlags = [];

  void _processPoses(List<Pose> poses) {
    if (poses.isEmpty) {
      return;
    }
    
    final session = ref.read(activeSessionProvider);
    if (session == null) return;
    
    final pose = poses.first;
    final exerciseName = session.exercise.toLowerCase();
    final now = DateTime.now();

    if (exerciseName.contains('squat')) {
      final rawAngle = AngleCalculator.calculateSquatAngle(pose);
      if (rawAngle == null) return;

      // Silky smooth exponential moving average to eliminate sensor jitter
      _smoothedAngle = _smoothedAngle == null
          ? rawAngle
          : (_smoothedAngle! * 0.70 + rawAngle * 0.30);
      final angle = _smoothedAngle!;
      final currentHipY = AngleCalculator.getHipY(pose);

      // STATE 0: IDLE / SEEKING STANDING BASELINE
      if (_trackingState == 0) {
        if (angle >= 152.0) {
          _consecutiveStandingFrames++;
          if (_consecutiveStandingFrames >= 3) {
            _trackingState = 1; // Armed & Ready at Standing Lockout
            _standingHipY = currentHipY;
            _lowestAngleInRep = 180.0;
            _descentStartTime = null;
            _bottomTime = null;
            _consecutiveBottomFrames = 0;
            _lastStateChange = now;
          }
        } else {
          _consecutiveStandingFrames = 0;
        }
      }
      // STATE 1: ARMED & READY AT TOP LOCKOUT
      else if (_trackingState == 1) {
        if (angle >= 150.0 && currentHipY != null) {
          _standingHipY = (_standingHipY ?? currentHipY) * 0.92 + currentHipY * 0.08;
        }

        // Detect descent initiation: Knee angle bends below 138°
        if (angle < 138.0) {
          _descentStartTime = now;
          _lowestAngleInRep = angle;
          _trackingState = 2; // DESCENDING
          _lastStateChange = now;
          _consecutiveBottomFrames = 0;
        }
      }
      // STATE 2: DESCENDING TOWARDS DEPTH
      else if (_trackingState == 2) {
        if (angle < _lowestAngleInRep) {
          _lowestAngleInRep = angle;
        }

        // If user stood back up without reaching squat depth, abort cleanly
        if (angle >= 148.0 && _lowestAngleInRep > 115.0) {
          _trackingState = 1;
          _lowestAngleInRep = 180.0;
          _descentStartTime = null;
          _consecutiveBottomFrames = 0;
          return;
        }

        // Reaching valid squat depth:
        if (angle <= 112.0) {
          _consecutiveBottomFrames++;
          if (_consecutiveBottomFrames >= 2 || angle <= 104.0) {
            _trackingState = 3; // AT BOTTOM / ASCENDING
            _bottomTime = now;
            _lastStateChange = now;
          }
        } else {
          _consecutiveBottomFrames = 0;
        }
      }
      // STATE 3: AT BOTTOM / ASCENDING BACK TO LOCKOUT
      else if (_trackingState == 3) {
        if (angle < _lowestAngleInRep) {
          _lowestAngleInRep = angle;
          _bottomTime = now;
        }

        // Return to standing lockout:
        if (angle >= 148.0) {
          final totalMs = _descentStartTime != null
              ? now.difference(_descentStartTime!).inMilliseconds
              : 0;
          final concentricMs = _bottomTime != null
              ? now.difference(_bottomTime!).inMilliseconds
              : 0;
          final msSinceLastRep = _lastCameraRepTime != null
              ? now.difference(_lastCameraRepTime!).inMilliseconds
              : 9999;

          // STRICT 4-GATE VALIDATION CHECKS:
          // 1. Verified squat depth <= 115°
          // 2. Minimum total rep duration >= 750ms
          // 3. Minimum concentric drive >= 220ms
          // 4. Refractory lockout cooldown >= 800ms
          if (_lowestAngleInRep <= 115.0 &&
              totalMs >= 750 &&
              concentricMs >= 220 &&
              msSinceLastRep >= 800) {

            _lastCameraRepTime = now;

            int formScore;
            List<String> flags = [];
            if (_lowestAngleInRep <= 94.0) {
              formScore = 95 + _rng.nextInt(5);
              flags = ['Full Depth Squat', 'Excellent ROM'];
            } else if (_lowestAngleInRep <= 105.0) {
              formScore = 88 + _rng.nextInt(6);
              flags = ['Parallel Depth', 'Solid Drive'];
            } else if (_lowestAngleInRep <= 112.0) {
              formScore = 80 + _rng.nextInt(5);
              flags = ['Good Rep', 'Solid Depth'];
            } else {
              formScore = 72 + _rng.nextInt(6);
              flags = ['Slightly Shallow', 'Drive Higher'];
            }

            _liveCameraFormScore = formScore;
            _liveCameraFormGrade = formScore >= 90 ? 'A' : (formScore >= 80 ? 'B' : (formScore >= 70 ? 'C' : 'D'));

            final ble = ref.read(bleProvider);
            if (ble.isConnected) {
              // MODE 1: CAMERA + IMU
              // Camera tracks form AND drives the rep count!
              // Hardware IMU provides bottom-to-top concentric velocity!
              RepEvent? imuEvent = _pipeline?.getAndConsumeLatestRepEvent();
              imuEvent ??= _pipeline?.getActiveConcentricMetrics();

              double? peakVel;
              double? avgVel;
              int? romMm;
              if (imuEvent != null && imuEvent.peakVelocity > 0.05) {
                peakVel = double.parse(imuEvent.peakVelocity.toStringAsFixed(3));
                avgVel = double.parse(imuEvent.meanConcentricVelocity.toStringAsFixed(3));
                romMm = (imuEvent.displacementM * 1000).round();
                flags.add('IMU Velocity Verified');
              }

              _recordRep(
                session: session,
                formScore: formScore,
                peakVelocity: peakVel,
                avgVelocity: avgVel,
                romMm: romMm,
                flags: flags,
              );
            } else {
              // MODE 3: CAMERA ONLY (No IMU connected)
              // Camera performs Rep Counting and Form Tracking (NO VELOCITY MEASUREMENT)
              _recordRep(
                session: session,
                formScore: formScore,
                peakVelocity: null,
                avgVelocity: null,
                romMm: null,
                flags: flags,
              );
            }
          }

          _trackingState = 4; // Move to lockout cooldown
          _lastStateChange = now;
          _descentStartTime = null;
          _bottomTime = null;
          _lowestAngleInRep = 180.0;
          _consecutiveBottomFrames = 0;
        }
      }
      // STATE 4: LOCKOUT COOLDOWN
      else if (_trackingState == 4) {
        if (angle >= 146.0 && now.difference(_lastStateChange!).inMilliseconds >= 350) {
          _trackingState = 1; // Re-arm for next rep
          _lastStateChange = now;
        }
      }
    } else if (exerciseName.contains('bench press') || exerciseName.contains('push up')) {
      if (AngleCalculator.isStanding(pose)) {
        return;
      }

      final rawAngle = AngleCalculator.calculateElbowAngle(pose);
      if (rawAngle == null) return;
      _smoothedAngle = _smoothedAngle == null ? rawAngle : (_smoothedAngle! * 0.70 + rawAngle * 0.30);
      final elbowAngle = _smoothedAngle!;

      if (_trackingState == 0) {
        if (elbowAngle >= 145) {
          _trackingState = 1;
          _lastStateChange = now;
          _descentStartTime = null;
          _lowestAngleInRep = 180.0;
        }
      } else if (_trackingState == 1) {
        if (elbowAngle < 135) {
          _descentStartTime = now;
          _lowestAngleInRep = elbowAngle;
          _trackingState = 2;
        }
      } else if (_trackingState == 2) {
        if (elbowAngle < _lowestAngleInRep) {
          _lowestAngleInRep = elbowAngle;
        }
        if (elbowAngle >= 145 && _lowestAngleInRep > 105) {
          _trackingState = 1;
          return;
        }
        if (elbowAngle <= 95) {
          _trackingState = 3;
          _bottomTime = now;
        }
      } else if (_trackingState == 3) {
        if (elbowAngle < _lowestAngleInRep) {
          _lowestAngleInRep = elbowAngle;
          _bottomTime = now;
        }
        if (elbowAngle >= 145) {
          final totalMs = _descentStartTime != null ? now.difference(_descentStartTime!).inMilliseconds : 0;
          final concentricMs = _bottomTime != null ? now.difference(_bottomTime!).inMilliseconds : 0;
          final msSinceLastRep = _lastCameraRepTime != null ? now.difference(_lastCameraRepTime!).inMilliseconds : 9999;

          if (_lowestAngleInRep <= 98 && totalMs >= 750 && concentricMs >= 220 && msSinceLastRep >= 800) {
            _lastCameraRepTime = now;
            
            int formScore;
            List<String> flags = [];

            // 1. Evaluate Depth / ROM
            if (_lowestAngleInRep <= 70.0) {
              formScore = 95 + _rng.nextInt(5);
              flags = ['Full ROM (Chest Touch)', 'Excellent Extension'];
            } else if (_lowestAngleInRep <= 85.0) {
              formScore = 88 + _rng.nextInt(6);
              flags = ['Great Depth', 'Solid Lockout'];
            } else if (_lowestAngleInRep <= 98.0) {
              formScore = 80 + _rng.nextInt(5);
              flags = ['Acceptable ROM'];
            } else {
              formScore = 72 + _rng.nextInt(6);
              flags = ['Shallow Depth'];
            }

            // 2. Evaluate Eccentric Control (Bouncing)
            final eccentricMs = totalMs - concentricMs;
            if (eccentricMs < 350) {
              formScore -= 12;
              flags.add('Bouncing Bar / Dropped too fast');
            } else {
              flags.add('Controlled Descent');
            }

            // 3. Evaluate Asymmetry (Injury Risk)
            final asymmetry = AngleCalculator.checkElbowAsymmetry(pose);
            if (asymmetry != null && asymmetry > 20.0) {
              formScore -= 15;
              flags.add('Uneven Lockout (Injury Risk)');
            }

            _liveCameraFormScore = formScore;
            _liveCameraFlags = flags;
            _liveCameraFormGrade = formScore >= 90 ? 'A' : (formScore >= 80 ? 'B' : (formScore >= 70 ? 'C' : 'D'));
            
            final ble = ref.read(bleProvider);
            if (ble.isConnected) {
              RepEvent? imuEvent = _pipeline?.getAndConsumeLatestRepEvent();
              imuEvent ??= _pipeline?.getActiveConcentricMetrics();

              double? peakVel;
              double? avgVel;
              int? romMm;
              if (imuEvent != null && imuEvent.peakVelocity > 0.05) {
                peakVel = double.parse(imuEvent.peakVelocity.toStringAsFixed(3));
                avgVel = double.parse(imuEvent.meanConcentricVelocity.toStringAsFixed(3));
                romMm = (imuEvent.displacementM * 1000).round();
                flags.add('IMU Verified');
              }

              _recordRep(
                session: session,
                formScore: formScore,
                peakVelocity: peakVel,
                avgVelocity: avgVel,
                romMm: romMm,
                flags: flags,
              );
            } else {
              _recordRep(
                session: session,
                formScore: formScore,
                peakVelocity: null,
                avgVelocity: null,
                romMm: null,
                flags: flags,
              );
            }
          }
          _trackingState = 4;
          _lastStateChange = now;
          _lowestAngleInRep = 180.0;
          _descentStartTime = null;
        }
      } else if (_trackingState == 4) {
        if (elbowAngle >= 140 && now.difference(_lastStateChange!).inMilliseconds >= 350) {
          _trackingState = 1;
        }
      }
    }
  }

  void _recordRep({
    required ActiveSessionState session,
    required int formScore,
    required double? peakVelocity,
    required double? avgVelocity,
    required int? romMm,
    required List<String> flags,
  }) {
    final now = DateTime.now();

    ref.read(activeSessionProvider.notifier).addRep(
      formScore: formScore,
      peakVelocity: peakVelocity,
      avgVelocity: avgVelocity,
      romMm: romMm,
      flags: flags,
    );

    if (avgVelocity != null && peakVelocity != null) {
      _vlCalc.addRep(avgVelocity, isGoodQuality: true);

      final currentSession = ref.read(activeSessionProvider);
      _fatigueEngine.addRep(RepSnapshot(
        repNumber: currentSession?.currentRepCount ?? session.currentRepCount + 1,
        avgVelocity: avgVelocity,
        peakVelocity: peakVelocity,
        formScore: formScore > 0 ? formScore : 85,
        timestamp: now,
      ));

      if (session.loadKg != null && _e1rmModel != null) {
        _e1rmModel!.addPoint(session.loadKg!, avgVelocity, goodQuality: true);
      }

      if (mounted) {
        setState(() {
          _velocityLossPercent = _vlCalc.velocityLossPercent;
          _fatigueResult = _fatigueEngine.analyze();
          _estimated1rm = _e1rmModel?.estimated1rm;
          _e1rmConfidence = _e1rmModel?.confidenceLabel ?? '';
        });
      }
    }
  }

  void _initPipeline() {
    final session = ref.read(activeSessionProvider);
    if (session == null) return;

    _pipeline = ImuPipeline(session.exercise);
    _vlCalc = VelocityLoss();
    _fatigueEngine = FatigueEngine(
      trainingGoal: session.loadKg != null ? 'Strength' : 'Power',
    );
    _fatigueResult = null;
    if (session.loadKg != null) {
      _e1rmModel = LoadVelocityModel(exercise: session.exercise);
    }

    // Calibrate if calibration samples are available
    if (calibrationSamplesProvider.isNotEmpty) {
      _pipeline!.calibrate(calibrationSamplesProvider);
    }

    // Wire BLE sample stream → pipeline and arm hardware streaming
    final bleNotifier = ref.read(bleProvider.notifier);
    bleNotifier.sendStartSession();
    _bleSub = bleNotifier.sampleStream.listen((sample) {
      _pipeline?.processSample(sample);
    });

    // Velocity updates → live gauge (unused currently)
    _velSub = _pipeline!.velocityStream.listen((v) {});

    // Rep completions from real IMU
    _repSub = _pipeline!.repStream.listen((event) {
      _lastImuRepTime = DateTime.now();
      final session = ref.read(activeSessionProvider);
      if (session == null) return;

      // In MODE 1 (Camera + IMU):
      // The rep count is driven by the CAMERA. Do not double count here!
      if (_cameraEnabled) {
        return;
      }

      // MODE 2: IMU ONLY (Camera disabled / off).
      // Hardware IMU tracks rep count & bottom-to-top velocity. NO FORM.
      _recordRep(
        session: session,
        formScore: 0, // Renders as '—' and 'NO FORM'
        peakVelocity: double.parse(event.peakVelocity.toStringAsFixed(3)),
        avgVelocity: double.parse(event.meanConcentricVelocity.toStringAsFixed(3)),
        romMm: (event.displacementM * 1000).round(),
        flags: ['IMU Hardware Tracked'],
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      _cameraController!.stopImageStream().then((_) {
        _cameraController!.dispose();
      }).catchError((_) {});
    } else {
      _cameraController?.dispose();
    }
    _poseService.close();
    _pulseController.dispose();
    _bleSub?.cancel();
    _velSub?.cancel();
    _repSub?.cancel();
    _pipeline?.dispose();
    super.dispose();
  }

  Color _gradeColor(String grade) {
    if (grade == 'A') return const Color(0xFF00E5FF);
    if (grade == 'B') return const Color(0xFF3EA6FF);
    if (grade == 'C') return const Color(0xFFFFD700);
    if (grade == 'D') return const Color(0xFFFF8C00);
    if (grade == '—') return Colors.white38;
    return const Color(0xFFFF3333);
  }

  void _simulateRep() {
    final formScore = 72 + _rng.nextInt(28); // 72-100
    final vel = 0.5 + _rng.nextDouble() * 0.6; // 0.5-1.1 m/s
    final session = ref.read(activeSessionProvider);

    ref.read(activeSessionProvider.notifier).addRep(
          formScore: formScore,
          peakVelocity: double.parse(vel.toStringAsFixed(2)),
          avgVelocity: double.parse((vel * 0.8).toStringAsFixed(2)),
          romMm: 380 + _rng.nextInt(60),
          flags: formScore < 82 ? ['Watch your knee alignment'] : ['Great form!'],
        );

    // Also update VL% and e1RM for simulated reps
    _vlCalc.addRep(vel * 0.8);
    if (session?.loadKg != null && _e1rmModel != null) {
      _e1rmModel!.addPoint(session!.loadKg!, vel * 0.8);
    }

    setState(() {
      _velocityLossPercent = _vlCalc.velocityLossPercent;
      _estimated1rm = _e1rmModel?.estimated1rm;
      _e1rmConfidence = _e1rmModel?.confidenceLabel ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider);
    if (session == null) return const SizedBox();
    final ble = ref.watch(bleProvider);
    final isBarbell = session.exerciseType == 'Barbell';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraEnabled && _isCameraInitialized && _cameraController != null)
            Transform.scale(
              scale: 1.0,
              child: Center(
                child: CameraPreview(
                  _cameraController!,
                  child: _poses.isNotEmpty
                      ? CustomPaint(
                          painter: PosePainter(
                            _poses,
                            _poseService.lastImageSize ?? Size(
                              _cameraController!.value.previewSize?.width ?? 480,
                              _cameraController!.value.previewSize?.height ?? 640
                            ),
                            InputImageRotationValue.fromRawValue(_cameraController!.description.sensorOrientation) ?? InputImageRotation.rotation0deg,
                            _cameraDirection,
                            smoothedLandmarks: _smoothedLandmarks,
                            smoothedLikelihoods: _smoothedLikelihoods,
                          ),
                        )
                      : null,
                ),
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0xFF0A1A0A), Color(0xFF050505)],
                  center: Alignment.topCenter,
                  radius: 1.8,
                ),
              ),
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: ble.isConnected ? _pulseAnim.value : 1.0,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.primary.withOpacity(0.03),
                          boxShadow: ble.isConnected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.primary.withOpacity(0.15 * _pulseAnim.value),
                                    blurRadius: 40,
                                    spreadRadius: 20,
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.fitness_center_rounded,
                            size: 80,
                            color: ble.isConnected ? AppTheme.primary.withOpacity(0.8) : Colors.white24,
                          ),
                        ),
                      ),
                    );
                  }
                ),
              ),
            ),

          // Subtle grid overlay
          CustomPaint(painter: _GridPainter()),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: GlassContainer(
                    blur: 20,
                    opacity: 0.15,
                    borderColor: Colors.white.withOpacity(0.12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [

                        GestureDetector(
                          onTap: _teardownAndStop,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3333).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFF3333).withOpacity(0.3)),
                            ),
                            child: const Icon(Icons.stop_rounded,
                                color: Color(0xFFFF3333), size: 20),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _switchCamera,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: const Icon(Icons.cameraswitch_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(session.exercise.toUpperCase(),
                                    maxLines: 1,
                                    style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2)),
                              ),
                              Text('Set ${session.currentSetNumber}  ·  ${_elapsed(session.elapsedSeconds)}',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                        // BLE indicator
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: ble.isConnected
                                ? AppTheme.primary.withOpacity(0.12)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: ble.isConnected
                                  ? AppTheme.primary.withOpacity(0.4)
                                  : Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: ble.isConnected
                                      ? AppTheme.primary
                                      : const Color(0xFFFF3333),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text('IMU',
                                  style: GoogleFonts.outfit(
                                      color: ble.isConnected
                                          ? AppTheme.primary
                                          : Colors.white38,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                              if (ble.isConnected) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.battery_std, 
                                  size: 11, 
                                  color: ble.batteryPercent < 20 ? Colors.redAccent : AppTheme.primary
                                ),
                                const SizedBox(width: 2),
                                Text('${ble.batteryPercent}%',
                                  style: GoogleFonts.outfit(
                                    color: ble.batteryPercent < 20 ? Colors.redAccent : AppTheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (ble.isConnected)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _cameraEnabled = !_cameraEnabled;
                          });
                        },
                        child: GlassContainer(
                          blur: 15,
                          opacity: _cameraEnabled ? 0.1 : 0.2,
                          borderColor: _cameraEnabled ? Colors.white.withOpacity(0.2) : AppTheme.primary.withOpacity(0.4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                                  color: _cameraEnabled ? Colors.white : AppTheme.primary, size: 14),
                              const SizedBox(width: 6),
                              Text(_cameraEnabled ? 'HYBRID: CAM FORM + IMU VELOCITY' : 'IMU ONLY (NO FORM)',
                                  style: GoogleFonts.outfit(
                                      color: _cameraEnabled ? Colors.white : AppTheme.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.videocam_rounded, color: Color(0xFF00E5FF), size: 14),
                            const SizedBox(width: 6),
                            Text('CAM ONLY (REPS + FORM)',
                                style: GoogleFonts.outfit(
                                    color: const Color(0xFF00E5FF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (session.lastRep != null || !ble.isConnected)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GlassContainer(
                      blur: 10,
                      opacity: 0.1,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            !_cameraEnabled ? Icons.sensors_rounded : Icons.auto_awesome_rounded,
                            color: !_cameraEnabled ? AppTheme.primary : _gradeColor(session.currentFormGrade),
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              !_cameraEnabled
                                  ? 'IMU Hardware Tracking · Reps & Velocity Active · Form Off'
                                  : (!ble.isConnected
                                      ? (session.lastRep?.flags.isNotEmpty == true
                                          ? '${session.lastRep!.flags.first} · Reps & Form Active'
                                          : 'Camera Tracking · Reps & Form Active')
                                      : (session.lastRep?.flags.isNotEmpty == true
                                          ? session.lastRep!.flags.first
                                          : 'Camera Form Active · Tracking Depth & Alignment')),
                              style: GoogleFonts.outfit(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const Spacer(),
                if (session.allReps.isNotEmpty && session.repVelocities.any((v) => v != null && v > 0))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _VelocityChart(
                      velocities: session.repVelocities,
                      gradeColors: session.allReps
                          .map((r) => _gradeColor(r.formGrade))
                          .toList(),
                    ),
                  ),

                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GlassContainer(
                    blur: 20,
                    opacity: 0.15,
                    borderColor: (!_cameraEnabled ? AppTheme.primary : _gradeColor(session.currentFormGrade)).withOpacity(0.3),
                    borderWidth: 1.5,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                    child: Row(
                      children: [
                        // Rep count with rolling vertical slide animation
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              AnimatedBuilder(
                                animation: _pulseAnim,
                                builder: (_, __) => Transform.scale(
                                  scale: session.currentRepCount > 0
                                      ? _pulseAnim.value
                                      : 1.0,
                                  child: SizedBox(
                                    height: 74,
                                    child: ClipRect(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 380),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        transitionBuilder: (child, animation) {
                                          final isIncoming = (child.key as ValueKey<int>?)?.value == session.currentRepCount;
                                          final inTween = Tween<Offset>(
                                            begin: const Offset(0.0, 1.1),
                                            end: Offset.zero,
                                          );
                                          final outTween = Tween<Offset>(
                                            begin: const Offset(0.0, -1.1),
                                            end: Offset.zero,
                                          );
                                          return SlideTransition(
                                            position: (isIncoming ? inTween : outTween).animate(animation),
                                            child: FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Center(
                                          key: ValueKey<int>(session.currentRepCount),
                                          child: Text(
                                            '${session.currentRepCount}',
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontSize: 72,
                                              fontWeight: FontWeight.bold,
                                              height: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Text('REPS',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white38,
                                      fontSize: 11,
                                      letterSpacing: 2)),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 60, color: Colors.white10),
                        // Form grade
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              Text(
                                !_cameraEnabled ? '—' : session.currentFormGrade,
                                style: GoogleFonts.outfit(
                                  color: !_cameraEnabled
                                      ? Colors.white24
                                      : _gradeColor(session.currentFormGrade),
                                  fontSize: 52,
                                  fontWeight: FontWeight.bold,
                                  height: 1,
                                ),
                              ),
                              Text(!_cameraEnabled ? 'NO FORM' : 'FORM',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white38,
                                      fontSize: 11,
                                      letterSpacing: 2)),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 60, color: Colors.white10),
                        // State or velocity
                        Expanded(
                          flex: 2,
                          child: session.lastRep?.peakVelocity != null
                              ? Column(
                                  children: [
                                    Text(
                                      session.lastRep!.peakVelocity!.toStringAsFixed(2),
                                      style: GoogleFonts.outfit(
                                          color: const Color(0xFF00E5FF),
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text('m/s',
                                        style: GoogleFonts.outfit(
                                            color: Colors.white38, fontSize: 11)),
                                    Text('PEAK VEL.',
                                        style: GoogleFonts.outfit(
                                            color: Colors.white38,
                                            fontSize: 9,
                                            letterSpacing: 1)),
                                  ],
                                )
                              : Column(
                                  children: [
                                    Text(
                                      !ble.isConnected ? '—' : session.movementState,
                                      style: GoogleFonts.outfit(
                                          color: !ble.isConnected ? Colors.white24 : AppTheme.primary,
                                          fontSize: !ble.isConnected ? 52 : 22,
                                          fontWeight: FontWeight.bold,
                                          height: 1),
                                    ),
                                    Text(!ble.isConnected ? 'NO VEL.' : 'STATE',
                                        style: GoogleFonts.outfit(
                                            color: Colors.white38,
                                            fontSize: 11,
                                            letterSpacing: 2)),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                if (_fatigueResult != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _FatigueBanner(result: _fatigueResult!),
                  ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  String _elapsed(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
class _FatigueBanner extends StatelessWidget {
  final FatigueResult result;
  const _FatigueBanner({required this.result});

  Color get _zoneColor {
    switch (result.zone) {
      case FatigueZone.fresh:    return const Color(0xFF00FF88);
      case FatigueZone.moderate: return const Color(0xFFFFD700);
      case FatigueZone.high:     return const Color(0xFFFF8C00);
      case FatigueZone.critical: return const Color(0xFFFF3333);
    }
  }

  IconData get _icon {
    switch (result.zone) {
      case FatigueZone.fresh:    return Icons.check_circle_outline_rounded;
      case FatigueZone.moderate: return Icons.trending_down_rounded;
      case FatigueZone.high:     return Icons.warning_amber_rounded;
      case FatigueZone.critical: return Icons.dangerous_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _zoneColor;
    final score = result.score;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35), width: 1.2),
        boxShadow: result.zone == FatigueZone.critical
            ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12)]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(result.headline,
                    style: GoogleFonts.outfit(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
              Text('${score.toStringAsFixed(0)}/100',
                  style: GoogleFonts.outfit(color: color, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          // Composite fatigue score bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (score / 100).clamp(0.0, 1.0),
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 6),
          Text(result.advice,
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (result.velocityLossPct != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                _SignalPill(label: 'VL%', value: '${result.velocityLossPct!.toStringAsFixed(0)}%', color: color),
                const SizedBox(width: 6),
                if (result.trendScore != null)
                  _SignalPill(label: 'Trend', value: '${result.trendScore!.toStringAsFixed(0)}', color: Colors.white38),
                const SizedBox(width: 6),
                if (result.formDecayScore != null)
                  _SignalPill(label: 'Form', value: '${result.formDecayScore!.toStringAsFixed(0)}', color: Colors.white38),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SignalPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SignalPill({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text('$label: $value',
          style: GoogleFonts.outfit(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}
class _VelocityChart extends StatefulWidget {
  final List<double?> velocities;
  final List<Color> gradeColors;
  const _VelocityChart({required this.velocities, required this.gradeColors});

  @override
  State<_VelocityChart> createState() => _VelocityChartState();
}

class _VelocityChartState extends State<_VelocityChart> {
  final ScrollController _scrollController = ScrollController();
  bool _showList = false;

  @override
  void didUpdateWidget(_VelocityChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.velocities.length > oldWidget.velocities.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Color _getVelColor(double v, int i) {
    if (i < widget.gradeColors.length &&
        widget.gradeColors[i] != AppTheme.primary &&
        widget.gradeColors[i] != Colors.white) {
      return widget.gradeColors[i];
    }
    if (v <= 0) return const Color(0xFF00E5FF);
    if (v >= 0.75) return const Color(0xFF00E5FF); // Neon cyan / fast
    if (v >= 0.55) return const Color(0xFF00E676); // Bright green / good
    if (v >= 0.40) return const Color(0xFFFFD600); // Yellow/amber / moderate
    return const Color(0xFFFF5252);               // Coral red / fatigued
  }

  @override
  Widget build(BuildContext context) {
    final vals = widget.velocities.map((v) => v ?? 0.0).toList();
    if (vals.isEmpty) return const SizedBox();

    // Constant width for all boxes as requested
    const double barW = 24.0;
    // Dynamic height range
    const double minBarH = 14.0;
    const double maxBarH = 64.0;

    final validVals = vals.where((v) => v > 0).toList();
    final double maxObserved = validVals.isNotEmpty
        ? validVals.fold<double>(0.0, math.max)
        : 0.80;
    final double minObserved = validVals.isNotEmpty
        ? validVals.fold<double>(double.infinity, math.min)
        : 0.30;

    final double scaleMax = math.max(0.85, maxObserved * 1.10);
    final double scaleMin = math.max(0.15, minObserved * 0.70);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showList = !_showList),
          child: Row(
            children: [
              Text('Velocity per Rep  (m/s)',
                  style: GoogleFonts.outfit(
                      color: Colors.white38, fontSize: 11, letterSpacing: 0.5)),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: _showList ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: const Icon(Icons.expand_more_rounded,
                    color: Colors.white24, size: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: maxBarH + 34,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(vals.length, (i) {
                final double v = vals[i];
                final double norm = v > 0
                    ? ((v - scaleMin) / (scaleMax - scaleMin)).clamp(0.08, 1.0)
                    : 0.08;
                final double barH = (minBarH + (maxBarH - minBarH) * norm).clamp(minBarH, maxBarH);
                final Color color = _getVelColor(v, i);

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Exact velocity text above each bar
                      Text(
                        v > 0 ? v.toStringAsFixed(2) : '—',
                        style: GoogleFonts.outfit(
                          color: color,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Bar box: uniform width (24px), dynamic height!
                      Container(
                        height: barH,
                        width: barW,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              color.withValues(alpha: 0.45),
                              color.withValues(alpha: 0.95),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Rep number badge below each bar
                      Text(
                        'R${i + 1}',
                        style: GoogleFonts.outfit(
                          color: Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          child: _showList
              ? Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('REP BREAKDOWN',
                          style: GoogleFonts.outfit(
                              color: Colors.white24,
                              fontSize: 9,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...List.generate(vals.length, (i) {
                        final v = vals[i];
                        final Color color = _getVelColor(v, i);
                        final double ratio = v > 0
                            ? (v / scaleMax).clamp(0.05, 1.0)
                            : 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              // Rep number badge
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color.withValues(alpha: 0.15),
                                  border: Border.all(
                                      color: color.withValues(alpha: 0.4)),
                                ),
                                child: Text('${i + 1}',
                                    style: GoogleFonts.outfit(
                                        color: color,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 10),
                              // Inline mini bar
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    backgroundColor: Colors.white10,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                            color.withValues(alpha: 0.7)),
                                    minHeight: 5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Value
                              Text(
                                v > 0 ? '${v.toStringAsFixed(3)} m/s' : '—',
                                style: GoogleFonts.outfit(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 0.5;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  Color get _color {
    switch (type) {
      case 'Barbell':  return const Color(0xFFFF8C00);
      case 'Bilateral': return const Color(0xFF3EA6FF);
      case 'Duration': return const Color(0xFFBB86FC);
      case 'Cardio':   return const Color(0xFFFF5252);
      default:         return const Color(0xFF00E5FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Text(type,
          style: GoogleFonts.outfit(color: _color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
enum _SummaryTab { form, fatigue }

// SESSION SUMMARY BOTTOM SHEET (Stance App Style)
class SessionSummarySheet extends ConsumerStatefulWidget {
  final WorkoutSession session;
  const SessionSummarySheet({required this.session});

  @override
  ConsumerState<SessionSummarySheet> createState() => SessionSummarySheetState();
}

class SessionSummarySheetState extends ConsumerState<SessionSummarySheet> {
  _SummaryTab _currentTab = _SummaryTab.form;

  double _getSessAvg(WorkoutSession s) {
    if (s.reps.isEmpty) return 0.0;
    double sum = 0;
    int count = 0;
    for (final r in s.reps) {
      if (r.avgVelocity != null) {
        sum += r.avgVelocity!.abs();
        count++;
      }
    }
    return count > 0 ? sum / count : 0.0;
  }

  Color _getGradeColor(String grade) {
    switch (grade) {
      case 'A':
        return const Color(0xFF00E676);
      case 'B':
        return const Color(0xFF00E5FF);
      case 'C':
        return const Color(0xFFFFB300);
      case 'D':
      case 'F':
        return const Color(0xFFFF5252);
      default:
        return AppTheme.primary;
    }
  }

  void _showGuideDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Text('Form Grading Guide',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _guideItem('Grade A (90-100%)', 'Full depth squat, balanced drive & upright torso.', const Color(0xFF00E676)),
            const SizedBox(height: 10),
            _guideItem('Grade B (80-89%)', 'Solid lockout & steady tempo, minor depth variation.', const Color(0xFF00E5FF)),
            const SizedBox(height: 10),
            _guideItem('Grade C (70-79%)', 'Slight knee cave or inconsistent depth during ascent.', const Color(0xFFFFB300)),
            const SizedBox(height: 10),
            _guideItem('Grade D/F (<70%)', 'Incomplete range of motion, excessive forward lean.', const Color(0xFFFF5252)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('GOT IT', style: GoogleFonts.outfit(color: AppTheme.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _guideItem(String title, String desc, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.outfit(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(desc, style: GoogleFonts.outfit(color: Colors.white60, fontSize: 12)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(workoutHistoryProvider).sessions;

    final thisSessionAvg = _getSessAvg(widget.session);

    // Form spots
    final List<FlSpot> formSpots = [];
    if (widget.session.reps.isNotEmpty) {
      for (final r in widget.session.reps) {
        if (r.formScore > 0) {
          formSpots.add(FlSpot(r.repNumber.toDouble(), r.formScore.toDouble()));
        }
      }
    }

    // Fatigue (Velocity) spots -> E1RM Growth Profile
    final List<FlSpot> fatigueSpots = [];
    double fatigueMaxVel = 0.5;
    double peakVel = 0.0;
    double minLoad = 1000;
    double maxLoad = 0;
    
    final allSessions = [...history, widget.session];
    for (final s in allSessions.where((s) => s.exercise == widget.session.exercise && s.loadKg != null && s.reps.isNotEmpty)) {
      final sessionE1rm = s.loadKg! * (1 + 0.0333 * s.reps.length);
      for (final r in s.reps) {
        if (r.peakVelocity != null) {
          final pv = r.peakVelocity!.abs();
          fatigueSpots.add(FlSpot(sessionE1rm, pv));
          if (pv > fatigueMaxVel) fatigueMaxVel = pv;
          if (pv > peakVel) peakVel = pv;
          if (sessionE1rm < minLoad) minLoad = sessionE1rm;
          if (sessionE1rm > maxLoad) maxLoad = sessionE1rm;
        }
      }
    }
    fatigueSpots.sort((a, b) => a.x.compareTo(b.x));

    final hasForm = formSpots.isNotEmpty;
    final hasFatigue = fatigueSpots.isNotEmpty;

    final availableTabs = <_SummaryTab>[];
    if (hasForm) availableTabs.add(_SummaryTab.form);
    if (hasFatigue) availableTabs.add(_SummaryTab.fatigue);

    final activeTab = availableTabs.contains(_currentTab)
        ? _currentTab
        : (availableTabs.isNotEmpty ? availableTabs.first : _SummaryTab.form);

    double e1rm = 0.0;
    if (widget.session.loadKg != null && widget.session.reps.isNotEmpty) {
      e1rm = widget.session.loadKg! * (1 + 0.0333 * widget.session.reps.length);
    }

    final isCameraOnly = hasForm && !hasFatigue;
    final isDualMode = hasForm && hasFatigue;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D0D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                children: [
                  // Header Row
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.session.exercise,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              widget.session.date.toString().substring(0, 16),
                              style: GoogleFonts.outfit(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showGuideDialog(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, color: AppTheme.primary, size: 14),
                              const SizedBox(width: 6),
                              Text('Guide',
                                  style: GoogleFonts.outfit(
                                      color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Session Overview Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isDualMode
                                        ? Icons.hub_rounded
                                        : (isCameraOnly ? Icons.videocam_rounded : Icons.sensors_rounded),
                                    color: AppTheme.primary,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.session.loadKg != null ? '${widget.session.loadKg} kg' : 'Bodyweight',
                                      style: GoogleFonts.outfit(
                                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      isDualMode
                                          ? 'Camera + IMU Tracked'
                                          : (isCameraOnly ? 'Camera Vision Tracked' : 'IMU Hardware Tracked'),
                                      style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.timer_outlined, color: Colors.white54, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.session.formattedDuration,
                                    style: GoogleFonts.outfit(
                                        color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 14),

                        // Stats metrics
                        Row(
                          children: [
                            Expanded(
                              child: _metricBox(
                                label: 'TOTAL REPS',
                                value: '${widget.session.totalReps}',
                                unit: 'reps',
                                lineColor: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _metricBox(
                                label: 'AVG FORM',
                                value: widget.session.avgFormScore > 0
                                    ? '${widget.session.avgFormScore}%'
                                    : (isCameraOnly ? '0%' : '—'),
                                unit: widget.session.avgFormScore > 0
                                    ? 'Grade ${widget.session.avgFormGrade}'
                                    : (isCameraOnly ? 'No Score' : 'IMU Mode'),
                                lineColor: _getGradeColor(widget.session.avgFormGrade),
                              ),
                            ),
                            if (fatigueSpots.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: _metricBox(
                                  label: 'AVG VELOCITY',
                                  value: thisSessionAvg > 0 ? thisSessionAvg.toStringAsFixed(2) : '--',
                                  unit: 'm/s',
                                  lineColor: const Color(0xFF00E5FF),
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Secondary row if velocity / 1RM present
                        if (fatigueSpots.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _metricBox(
                                  label: 'PEAK VELOCITY',
                                  value: peakVel > 0 ? peakVel.toStringAsFixed(2) : '--',
                                  unit: 'm/s',
                                  lineColor: const Color(0xFFC77DFF),
                                ),
                              ),
                              if (widget.session.loadKg != null && widget.session.reps.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _metricBox(
                                    label: 'EST. 1RM',
                                    value: e1rm > 0 ? e1rm.toStringAsFixed(1) : '--',
                                    unit: 'kg',
                                    lineColor: const Color(0xFF00E5FF),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Graphs Section (if any spots available)
                  if (availableTabs.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    if (availableTabs.length > 1) ...[
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: availableTabs.map((tab) {
                            final isSelected = tab == activeTab;
                            final label = switch (tab) {
                              _SummaryTab.form => 'Form Score',
                              _SummaryTab.fatigue => 'Velocity Profile',
                            };
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _currentTab = tab),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primary.withValues(alpha: 0.15)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    label,
                                    style: GoogleFonts.outfit(
                                      color: isSelected ? AppTheme.primary : Colors.white54,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      Row(
                        children: [
                          Icon(
                            activeTab == _SummaryTab.form
                                ? Icons.auto_graph_rounded
                                : Icons.show_chart_rounded,
                            color: AppTheme.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            activeTab == _SummaryTab.form
                                ? 'Form Score Progression (%)'
                                : 'Velocity Profile',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Chart display
                    Container(
                      height: 210,
                      padding: const EdgeInsets.only(top: 8, right: 16, left: 0),
                      child: _buildChart(
                        activeTab: activeTab,
                        formSpots: formSpots,
                        fatigueSpots: fatigueSpots,
                        fatigueMaxVel: fatigueMaxVel,
                        minLoad: minLoad,
                        maxLoad: maxLoad,
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Reps & Form Breakdown Section Header
                  Row(
                    children: [
                      const Icon(Icons.format_list_bulleted_rounded, color: AppTheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Reps & Form Breakdown',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${widget.session.reps.length} Reps',
                          style: GoogleFonts.outfit(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // All reps breakdown cards
                  if (widget.session.reps.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.fitness_center_rounded, color: Colors.white24, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            'No Completed Reps Detected',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Make sure your full body is visible in the camera frame and perform full range of motion squats.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  else
                    ...widget.session.reps.map((rep) => _buildRepDetailCard(rep)),

                  const SizedBox(height: 24),

                  // Finish Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text(
                        'DONE',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart({
    required _SummaryTab activeTab,
    required List<FlSpot> formSpots,
    required List<FlSpot> fatigueSpots,
    required double fatigueMaxVel,
    required double minLoad,
    required double maxLoad,
  }) {
    if (activeTab == _SummaryTab.form) {
      if (formSpots.isEmpty) {
        return Center(
          child: Text('No form data recorded', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
        );
      }
      return LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            drawHorizontalLine: true,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white.withValues(alpha: 0.08),
              strokeWidth: 1,
              dashArray: const [5, 5],
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              axisNameWidget: Text('Rep Number', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10)),
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value % 1 == 0 && value >= 1 && value <= widget.session.reps.length) {
                    return Text(value.toInt().toString(), style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10));
                  }
                  return const SizedBox.shrink();
                },
                reservedSize: 22,
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: Text('%', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10)),
              sideTitles: SideTitles(
                showTitles: true,
                interval: 25,
                getTitlesWidget: (value, meta) => Text('${value.toInt()}%', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 9)),
                reservedSize: 30,
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 1,
          maxX: widget.session.reps.length > 1 ? widget.session.reps.length.toDouble() : 1.0,
          minY: 0,
          maxY: 105,
          lineBarsData: [
            LineChartBarData(
              spots: formSpots,
              isCurved: formSpots.length > 2,
              color: AppTheme.primary,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  Color dotColor = _getGradeColor(spot.y >= 90 ? 'A' : (spot.y >= 80 ? 'B' : (spot.y >= 70 ? 'C' : 'D')));
                  return FlDotCirclePainter(
                    radius: 4.5,
                    color: dotColor,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.22),
                    AppTheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      if (fatigueSpots.isEmpty) {
        return Center(
          child: Text('No velocity fatigue data', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
        );
      }
      return LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            drawHorizontalLine: true,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white.withValues(alpha: 0.08),
              strokeWidth: 1,
              dashArray: const [5, 5],
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              axisNameWidget: Text('Est. 1RM (kg)', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10)),
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) => Text('${value.toInt()}kg', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 9)),
                reservedSize: 22,
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: Text('m/s', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10)),
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(1), style: GoogleFonts.outfit(color: Colors.white38, fontSize: 9)),
                reservedSize: 28,
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: minLoad == maxLoad ? (minLoad - 10 > 0 ? minLoad - 10 : 0) : minLoad,
          maxX: minLoad == maxLoad ? maxLoad + 10 : maxLoad,
          minY: 0,
          maxY: fatigueMaxVel * 1.25,
          lineBarsData: [
            LineChartBarData(
              spots: fatigueSpots,
              isCurved: false,
              color: const Color(0xFF00E5FF),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                  radius: 4.5,
                  color: const Color(0xFF00E5FF),
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildRepDetailCard(RepCard r) {
    final gradeColor = _getGradeColor(r.formGrade);
    final isImuOnly = r.formScore <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isImuOnly ? Colors.white10 : gradeColor.withValues(alpha: 0.28),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Rep #, Grade Pill, Form Score %
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'REP #${r.repNumber}',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              if (!isImuOnly) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: gradeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: gradeColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    r.formGrade,
                    style: GoogleFonts.outfit(
                      color: gradeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'HARDWARE TRACKED',
                    style: GoogleFonts.outfit(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),


          // Flags / feedback chips
          if (r.flags.where((f) => !f.toLowerCase().contains('full depth squat') && !f.toLowerCase().contains('excellent rom') && !f.toLowerCase().contains('imu velocity verified')).isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: r.flags.where((f) => !f.toLowerCase().contains('full depth squat') && !f.toLowerCase().contains('excellent rom') && !f.toLowerCase().contains('imu velocity verified')).map((flag) {
                final isCaution = flag.toLowerCase().contains('cave') ||
                    flag.toLowerCase().contains('fast') ||
                    flag.toLowerCase().contains('incomplete') ||
                    flag.toLowerCase().contains('slow') ||
                    flag.toLowerCase().contains('loss') ||
                    flag.toLowerCase().contains('asymmetric');
                final tagColor = isCaution ? const Color(0xFFFFB300) : const Color(0xFF00E5FF);
                final tagIcon = isCaution ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: tagColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tagColor.withValues(alpha: 0.3), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tagIcon, size: 12, color: tagColor),
                      const SizedBox(width: 4),
                      Text(
                        flag,
                        style: GoogleFonts.outfit(
                          color: tagColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          // Velocity info if present on this rep
          if (r.peakVelocity != null || r.avgVelocity != null || r.romMm != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (r.avgVelocity != null || r.peakVelocity != null)
                  _metricPill('Velocity', '${(r.avgVelocity ?? r.peakVelocity!).toStringAsFixed(2)} m/s', const Color(0xFFC77DFF)),
                if (r.romMm != null) ...[
                  const SizedBox(width: 8),
                  _metricPill('ROM', '${r.romMm} mm', const Color(0xFF00E5FF)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricBox({
    required String label,
    required String value,
    required String unit,
    required Color lineColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                unit,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 10),
              ),
            ),
          ],
        ),
        Container(
          height: 2,
          width: double.infinity,
          color: lineColor,
          margin: const EdgeInsets.symmetric(vertical: 6),
        ),
        Text(label, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 10, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _metricPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 10)),
          Text(value, style: GoogleFonts.outfit(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}