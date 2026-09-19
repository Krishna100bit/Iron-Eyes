import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../../../core/widgets/glass_container.dart';
import '../../../core/signal_processing/imu_pipeline.dart';
import '../../../core/signal_processing/velocity_loss.dart';
import '../../../core/signal_processing/load_velocity_model.dart';
import '../../device/view/device_screen.dart';
import '../../device/view/calibration_screen.dart' show calibrationSamplesProvider;

// All 18 exercises
final List<Map<String, dynamic>> exercises = [
  {'name': 'Squat',          'group': 'Lower Body', 'type': 'Barbell',    'icon': Icons.accessibility_new_rounded},
  {'name': 'Deadlift',       'group': 'Lower Body', 'type': 'Barbell',    'icon': Icons.fitness_center},
  {'name': 'Bench Press',    'group': 'Upper Body', 'type': 'Barbell',    'icon': Icons.fitness_center},
  {'name': 'Overhead Press', 'group': 'Upper Body', 'type': 'Barbell',    'icon': Icons.fitness_center},
  {'name': 'Barbell Row',    'group': 'Upper Body', 'type': 'Barbell',    'icon': Icons.fitness_center},
  {'name': 'Front Squat',    'group': 'Lower Body', 'type': 'Barbell',    'icon': Icons.accessibility_new_rounded},
  {'name': 'Romanian Deadlift','group':'Lower Body','type': 'Barbell',    'icon': Icons.fitness_center},
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

// ─────────────────────────────────────────────────────────────────────────────
// WORKOUT SCREEN  (Exercise Selector)
// ─────────────────────────────────────────────────────────────────────────────
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
    final session = ref.read(activeSessionProvider.notifier).stopSession();
    if (session != null) {
      ref.read(workoutHistoryProvider.notifier).addSession(session);
      _showSummary(session);
    }
    setState(() { _loadKg = null; _targetRpe = null; });
  }

  void _cancelSession() {
    ref.read(activeSessionProvider.notifier).cancelSession();
    setState(() { _loadKg = null; _targetRpe = null; });
  }

  void _showSummary(WorkoutSession s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SessionSummarySheet(session: s),
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

  // ── Pre-session modal: Load (kg) + RPE slider ─────────────────────────────
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


// ─────────────────────────────────────────────────────────────────────────────
// LIVE SESSION SCREEN  (gpath.gym style — premium glassmorphism)
// ─────────────────────────────────────────────────────────────────────────────
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

  // ── Signal processing pipeline ────────────────────────────────────────────
  ImuPipeline? _pipeline;
  VelocityLoss _vlCalc = VelocityLoss();
  LoadVelocityModel? _e1rmModel;
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
          if (!mounted) return;
          final poses = await _poseService.processCameraImage(
            image,
            camera.sensorOrientation,
            camera.lensDirection,
          );
          
          final validPoses = poses.where((p) => AngleCalculator.isValidHuman(p)).toList();

          if (mounted) {
            setState(() {
              _poses = validPoses;
            });
            _processPoses(validPoses);
          }
        });
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _teardownAndStop() async {
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

  int _trackingState = 0; // 0=idle, 1=ready, 2=bottom
  double? _smoothedAngle;
  DateTime? _lastStateChange;

  void _processPoses(List<Pose> poses) {
    if (poses.isEmpty) {
      return;
    }
    
    final session = ref.read(activeSessionProvider);
    if (session == null) return;
    
    final pose = poses.first;
    final exerciseName = session.exercise.toLowerCase();
    final now = DateTime.now();

    bool canChangeState() {
      if (_lastStateChange == null) return true;
      return now.difference(_lastStateChange!).inMilliseconds > 400; // 400ms debounce
    }

    if (exerciseName.contains('squat')) {
      final rawAngle = AngleCalculator.calculateKneeAngle(pose);
      if (rawAngle == null) return;
      _smoothedAngle = _smoothedAngle == null ? rawAngle : (_smoothedAngle! * 0.7 + rawAngle * 0.3);
      final kneeAngle = _smoothedAngle!;

      if (kneeAngle > 160 && _trackingState == 0) {
        _trackingState = 1; // Ready
        _lastStateChange = now;
      } else if (kneeAngle < 100 && _trackingState == 1 && canChangeState()) {
        _trackingState = 2; // Bottom
        _lastStateChange = now;
      } else if (kneeAngle > 160 && _trackingState == 2 && canChangeState()) {
        _trackingState = 1; // Back to ready
        _lastStateChange = now;
        _triggerAutoRep(session);
      }
    } else if (exerciseName.contains('bench press') || exerciseName.contains('push up')) {
      if (AngleCalculator.isStanding(pose)) {
        return; // Reject pushups/bench press if the user is standing up vertically
      }

      final rawAngle = AngleCalculator.calculateElbowAngle(pose);
      if (rawAngle == null) return;
      _smoothedAngle = _smoothedAngle == null ? rawAngle : (_smoothedAngle! * 0.7 + rawAngle * 0.3);
      final elbowAngle = _smoothedAngle!;

      if (elbowAngle > 140 && _trackingState == 0) {
        _trackingState = 1; // Ready
        _lastStateChange = now;
      } else if (elbowAngle < 100 && _trackingState == 1 && canChangeState()) {
        _trackingState = 2; // Bottom
        _lastStateChange = now;
      } else if (elbowAngle > 140 && _trackingState == 2 && canChangeState()) {
        _trackingState = 1;
        _lastStateChange = now;
        _triggerAutoRep(session);
      }
    }
  }

  void _triggerAutoRep(ActiveSessionState session) {
    final isBarbell = session.exerciseType == 'Barbell';
    
    ref.read(activeSessionProvider.notifier).addRep(
      formScore: 85 + _rng.nextInt(10),
      peakVelocity: isBarbell ? 0.8 : null,
      avgVelocity: isBarbell ? 0.6 : null,
      romMm: isBarbell ? 400 : null,
      flags: [],
    );
  }

  void _initPipeline() {
    final session = ref.read(activeSessionProvider);
    if (session == null) return;

    _pipeline = ImuPipeline(session.exercise);
    _vlCalc = VelocityLoss();

    if (session.loadKg != null) {
      _e1rmModel = LoadVelocityModel(exercise: session.exercise);
    }

    // Calibrate if calibration samples are available
    if (calibrationSamplesProvider.isNotEmpty) {
      _pipeline!.calibrate(calibrationSamplesProvider);
    }

    // Wire BLE sample stream → pipeline
    final bleNotifier = ref.read(bleProvider.notifier);
    _bleSub = bleNotifier.sampleStream.listen((sample) {
      _pipeline?.processSample(sample);
    });

    // Velocity updates → live gauge (unused currently)
    _velSub = _pipeline!.velocityStream.listen((v) {});

    // Rep completions from real IMU
    _repSub = _pipeline!.repStream.listen((event) {
      final session = ref.read(activeSessionProvider);
      if (session == null) return;
      final loadKg = session.loadKg;

      // Add to active session
      ref.read(activeSessionProvider.notifier).addRep(
        formScore: (event.dataQuality == 'good' ? 85 : 65) + _rng.nextInt(10),
        peakVelocity: double.parse(event.peakVelocity.toStringAsFixed(3)),
        avgVelocity: double.parse(event.meanConcentricVelocity.toStringAsFixed(3)),
        romMm: (event.displacementM * 1000).round(),
        flags: event.dataQuality == 'good' ? ['Good rep'] : ['Low quality signal'],
      );

      // VL% tracking
      _vlCalc.addRep(event.meanConcentricVelocity,
          isGoodQuality: event.dataQuality == 'good');

      // e1RM model update
      if (loadKg != null && _e1rmModel != null) {
        _e1rmModel!.addPoint(loadKg, event.meanConcentricVelocity,
            goodQuality: event.dataQuality == 'good');
      }

      if (mounted) {
        setState(() {
          _velocityLossPercent = _vlCalc.velocityLossPercent;
          _estimated1rm = _e1rmModel?.estimated1rm;
          _e1rmConfidence = _e1rmModel?.confidenceLabel ?? '';
        });
      }
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
          // ── Background gradient (camera feed placeholder) ────────────────
          if (_isCameraInitialized && _cameraController != null)
            Transform.scale(
              scale: 1.0,
              child: Center(
                child: CameraPreview(
                  _cameraController!,
                  child: _poses.isNotEmpty
                      ? CustomPaint(
                          painter: PosePainter(
                            _poses,
                            Size(
                              _cameraController!.value.previewSize?.width ?? 480,
                              _cameraController!.value.previewSize?.height ?? 640
                            ),
                            InputImageRotationValue.fromRawValue(_cameraController!.description.sensorOrientation) ?? InputImageRotation.rotation0deg,
                            _cameraDirection,
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
            ),

          // Subtle grid overlay
          CustomPaint(painter: _GridPainter()),


          SafeArea(
            child: Column(
              children: [
                // ── Top glass bar ────────────────────────────────────────────
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(session.exercise.toUpperCase(),
                                  style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2)),
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
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Feedback text glass card ────────────────────────────────
                if (session.lastRep != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GlassContainer(
                      blur: 10,
                      opacity: 0.1,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              color: _gradeColor(session.currentFormGrade), size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              session.lastRep!.flags.isNotEmpty
                                  ? session.lastRep!.flags.first
                                  : 'Great form! Keep going.',
                              style: GoogleFonts.outfit(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const Spacer(),

                // ── Velocity bar chart per rep ──────────────────────────────
                if (isBarbell && session.allReps.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _VelocityChart(
                        velocities: session.repVelocities,
                        gradeColors: session.allReps.map((r) => _gradeColor(r.formGrade)).toList()),
                  ),

                const SizedBox(height: 12),


                // ── Main rep card ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GlassContainer(
                    blur: 20,
                    opacity: 0.15,
                    borderColor: _gradeColor(session.currentFormGrade).withOpacity(0.3),
                    borderWidth: 1.5,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                    child: Row(
                      children: [
                        // Rep count
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
                                session.currentFormGrade,
                                style: GoogleFonts.outfit(
                                  color: _gradeColor(session.currentFormGrade),
                                  fontSize: 52,
                                  fontWeight: FontWeight.bold,
                                  height: 1,
                                ),
                              ),
                              Text('FORM',
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
                          child: isBarbell && session.lastRep?.peakVelocity != null
                              ? Column(
                                  children: [
                                    Text(
                                      session.lastRep!.peakVelocity!.toStringAsFixed(2),
                                      style: GoogleFonts.outfit(
                                          color: AppTheme.primary,
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
                                    Text(session.movementState,
                                        style: GoogleFonts.outfit(
                                            color: AppTheme.primary,
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold)),
                                    Text('STATE',
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

                // ── VL% and e1RM Analytics Panel ──────────────────────────────
                if (_velocityLossPercent != null || _estimated1rm != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: GlassContainer(
                      blur: 16,
                      opacity: 0.06,
                      borderColor: Colors.white.withOpacity(0.1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          // Velocity Loss
                          if (_velocityLossPercent != null) ...[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('VL%',
                                      style: GoogleFonts.outfit(
                                          color: Colors.white38,
                                          fontSize: 9,
                                          letterSpacing: 2)),
                                  Text(
                                    '${_velocityLossPercent!.toStringAsFixed(1)}%',
                                    style: GoogleFonts.outfit(
                                        color: _velocityLossPercent! > 20
                                            ? Colors.orange
                                            : _velocityLossPercent! > 10
                                                ? Colors.yellow
                                                : AppTheme.primary,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text('Velocity Loss',
                                      style: GoogleFonts.outfit(
                                          color: Colors.white38, fontSize: 10)),
                                ],
                              ),
                            ),
                          ],
                          // e1RM
                          if (_estimated1rm != null) ...[
                            if (_velocityLossPercent != null)
                              Container(
                                  width: 1,
                                  height: 40,
                                  color: Colors.white10,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('e1RM',
                                      style: GoogleFonts.outfit(
                                          color: Colors.white38,
                                          fontSize: 9,
                                          letterSpacing: 2)),
                                  Text(
                                    '${_estimated1rm!.toStringAsFixed(1)} kg',
                                    style: GoogleFonts.outfit(
                                        color: const Color(0xFF3EA6FF),
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(_e1rmConfidence,
                                      style: GoogleFonts.outfit(
                                          color: Colors.white38,
                                          fontSize: 9),
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
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

// ── Velocity mini bar chart ────────────────────────────────────────────────
class _VelocityChart extends StatefulWidget {
  final List<double?> velocities;
  final List<Color> gradeColors;
  const _VelocityChart({required this.velocities, required this.gradeColors});

  @override
  State<_VelocityChart> createState() => _VelocityChartState();
}

class _VelocityChartState extends State<_VelocityChart> {
  final ScrollController _scrollController = ScrollController();

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

  @override
  Widget build(BuildContext context) {
    final vals = widget.velocities.map((v) => v ?? 0.0).toList();
    if (vals.isEmpty) return const SizedBox();
    final maxV = vals.reduce((a, b) => a > b ? a : b).clamp(0.1, 2.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Velocity per Rep  (m/s)',
            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        SizedBox(
          height: 64,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(vals.length, (i) {
                final h = (vals[i] / maxV) * 36;
                final color = i < widget.gradeColors.length ? widget.gradeColors[i] : AppTheme.primary;
                return Container(
                  width: 24, // Fixed width so they never squish
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (vals[i] > 0)
                        Text(vals[i].toStringAsFixed(1),
                            style: GoogleFonts.outfit(
                                color: color, fontSize: 8, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Container(
                        height: h.clamp(4.0, 36.0),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Set history table row ──────────────────────────────────────────────────
class _SetRow extends StatelessWidget {
  final int setNumber;
  final int reps;
  final String grade;
  final double? velocity;
  final bool isBarbell;
  final bool isDone;
  final Color gradeColor;

  const _SetRow({
    required this.setNumber,
    required this.reps,
    required this.grade,
    required this.velocity,
    required this.isBarbell,
    required this.isDone,
    required this.gradeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDone ? Colors.transparent : AppTheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: isDone
            ? null
            : Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // Set number
          Expanded(
            flex: 1,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? gradeColor.withOpacity(0.2) : AppTheme.primary.withOpacity(0.15),
                border: Border.all(
                  color: isDone ? gradeColor.withOpacity(0.5) : AppTheme.primary.withOpacity(0.4),
                ),
              ),
              child: Text('$setNumber',
                  style: GoogleFonts.outfit(
                      color: isDone ? gradeColor : AppTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          // Reps
          Expanded(
            flex: 2,
            child: Text('$reps',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          // Velocity (barbell only)
          if (isBarbell)
            Expanded(
              flex: 2,
              child: Text(
                velocity != null ? '${velocity!.toStringAsFixed(2)} m/s' : '—',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: Colors.white70, fontSize: 12),
              ),
            ),
          // Status icon
          Expanded(
            flex: 1,
            child: Icon(
              isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: isDone ? gradeColor : AppTheme.primary.withOpacity(0.5),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  final int flex;
  const _TableHeader(this.text, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
              color: Colors.white24, fontSize: 10, letterSpacing: 1.5)),
    );
  }
}

// ── Grid background painter ────────────────────────────────────────────────
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

// ── Type badge ─────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// SESSION SUMMARY BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _SessionSummarySheet extends StatelessWidget {
  final WorkoutSession session;
  const _SessionSummarySheet({required this.session});

  Color _gradeColor(String g) {
    if (g.startsWith('A')) return const Color(0xFF00E5FF);
    if (g.startsWith('B')) return const Color(0xFF3EA6FF);
    if (g.startsWith('C')) return const Color(0xFFFFD700);
    if (g.startsWith('D')) return const Color(0xFFFF8C00);
    return const Color(0xFFFF3333);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D0D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.all(24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Session Complete 🎉',
                                style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            Text(session.exercise,
                                style: GoogleFonts.outfit(
                                    color: Colors.white54, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _SumStat('Total Reps', '${session.totalReps}', Icons.repeat_rounded),
                      const SizedBox(width: 10),
                      _SumStat('Avg Form', session.avgFormGrade, Icons.star_rounded,
                          valueColor: _gradeColor(session.avgFormGrade)),
                      const SizedBox(width: 10),
                      _SumStat('Duration', session.formattedDuration, Icons.timer_rounded),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (session.reps.isNotEmpty) ...[
                    Text('Rep Breakdown',
                        style: GoogleFonts.outfit(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    ...session.reps.map((rep) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Row(
                            children: [
                              Text('Rep ${rep.repNumber}',
                                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _gradeColor(rep.formGrade).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(rep.formGrade,
                                    style: GoogleFonts.outfit(
                                        color: _gradeColor(rep.formGrade),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ),
                              if (rep.peakVelocity != null) ...[
                                const SizedBox(width: 10),
                                Text('${rep.peakVelocity!.toStringAsFixed(2)} m/s',
                                    style: GoogleFonts.outfit(
                                        color: Colors.white54, fontSize: 12)),
                              ],
                            ],
                          ),
                        )),
                  ],
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: AppTheme.primary.withOpacity(0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: Text('Done',
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
          ],
        ),
      ),
    );
  }
}

class _SumStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  const _SumStat(this.label, this.value, this.icon, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary, size: 18),
            const SizedBox(height: 6),
            Text(value,
                style: GoogleFonts.outfit(
                    color: valueColor ?? Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
