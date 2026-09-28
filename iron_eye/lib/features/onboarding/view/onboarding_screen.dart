import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/theme/app_theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final UserProfile? initialProfile;
  const OnboardingScreen({Key? key, this.initialProfile}) : super(key: key);

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  static const int _totalPages = 5;
  bool _nameError = false;

  // Page 1 — Name
  final _nameController = TextEditingController();

  // Page 2 — Body Metrics
  double _age = 22;
  double _weight = 70;
  double _height = 175;
  String _gender = 'male';

  // Page 3 — Training Experience
  String _trainingExperience = 'beginner';

  // Page 4 — Goal
  String _goal = 'strength';

  // Page 5 — Weekly Targets
  int _weeklyWorkouts = 5;
  int _weeklyReps = 300;

  @override
  void initState() {
    super.initState();
    if (widget.initialProfile != null) {
      final p = widget.initialProfile!;
      _nameController.text = p.name;
      _age = p.age.toDouble();
      _weight = p.weight;
      _height = p.height;
      _gender = p.gender;
      _trainingExperience = p.trainingExperience;
      _goal = p.goal;
      _weeklyWorkouts = p.weeklyWorkoutTarget;
      _weeklyReps = p.weeklyRepTarget;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _next() {
    // Validate name before leaving the name page
    if (_currentPage == 1) {
      if (_nameController.text.trim().isEmpty) {
        setState(() => _nameError = true);
        return;
      }
      setState(() => _nameError = false);
    }

    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final profile = UserProfile(
      name: _nameController.text.trim(),
      age: _age.round(),
      weight: double.parse(_weight.toStringAsFixed(1)),
      height: double.parse(_height.toStringAsFixed(1)),
      gender: _gender,
      trainingExperience: _trainingExperience,
      goal: _goal,
      weeklyWorkoutTarget: _weeklyWorkouts.round(),
      weeklyRepTarget: _weeklyReps.round(),
    );
    await ref.read(userProfileProvider.notifier).saveProfile(profile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressDots(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _WelcomePage(onNext: _next),
                  _NamePage(controller: _nameController, onNext: _next, hasError: _nameError),
                  _BodyPage(
                    age: _age,
                    weight: _weight,
                    height: _height,
                    gender: _gender,
                    onAgeChanged: (v) => setState(() => _age = v),
                    onWeightChanged: (v) => setState(() => _weight = v),
                    onHeightChanged: (v) => setState(() => _height = v),
                    onGenderChanged: (v) => setState(() => _gender = v),
                    onNext: _next,
                  ),
                  _ExperiencePage(
                    selected: _trainingExperience,
                    onSelected: (v) => setState(() => _trainingExperience = v),
                    onNext: _next,
                  ),
                  _GoalPage(
                    selectedGoal: _goal,
                    onGoalSelected: (g) => setState(() => _goal = g),
                    onNext: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressDots() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_totalPages, (i) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == _currentPage ? 28 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == _currentPage
                  ? AppTheme.primary
                  : i < _currentPage
                      ? AppTheme.primary.withOpacity(0.4)
                      : const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
// PAGE 0: WELCOME
class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withOpacity(0.1),
              border: Border.all(color: AppTheme.primary, width: 2),
            ),
            child: const Icon(Icons.remove_red_eye_rounded,
                color: AppTheme.primary, size: 50),
          ),
          const SizedBox(height: 32),
          Text('IRON EYE',
              style: GoogleFonts.outfit(
                  color: AppTheme.primary,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4)),
          const SizedBox(height: 12),
          Text('Your AI-Powered Gym Coach',
              style: GoogleFonts.outfit(
                  color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 10),
          Text(
            'Camera pose estimation + IMU velocity\nfused into one smart rep card.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
                color: Colors.white38, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 60),
          _GreenButton(text: 'Get Started', onTap: onNext),
        ],
      ),
    );
  }
}
// PAGE 1: NAME
class _NamePage extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onNext;
  final bool hasError;
  const _NamePage({required this.controller, required this.onNext, this.hasError = false});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text('What\'s your\nname?', style: _titleStyle),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: hasError
                ? Container(
                    key: const ValueKey('err'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Text('Please enter your name to continue',
                            style: GoogleFonts.outfit(
                                color: Colors.red, fontSize: 12)),
                      ],
                    ),
                  )
                : const SizedBox(key: ValueKey('ok')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 18),
            onChanged: (_) { /* clears error on typing — handled by parent */ },
            decoration: InputDecoration(
              hintText: 'e.g. Mahesh',
              hintStyle: GoogleFonts.outfit(color: Colors.white38),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: hasError ? Colors.red : const Color(0xFF2A2A2A))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: hasError
                          ? Colors.red.withOpacity(0.6)
                          : const Color(0xFF2A2A2A))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: hasError ? Colors.red : AppTheme.primary,
                      width: 2)),
            ),
          ),
          const SizedBox(height: 48),
          _GreenButton(text: 'Continue', onTap: onNext),
        ],
      ),
    );
  }
}
// PAGE 2: BODY METRICS (age, weight, height, gender)
class _BodyPage extends StatelessWidget {
  final double age, weight, height;
  final String gender;
  final ValueChanged<double> onAgeChanged, onWeightChanged, onHeightChanged;
  final ValueChanged<String> onGenderChanged;
  final VoidCallback onNext;

  const _BodyPage({
    required this.age, required this.weight, required this.height,
    required this.gender,
    required this.onAgeChanged, required this.onWeightChanged,
    required this.onHeightChanged, required this.onGenderChanged,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final genders = [
      {'key': 'male',   'label': '♂  Male'},
      {'key': 'female', 'label': '♀  Female'},
      {'key': 'other',  'label': '⚧  Other'},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tell us about\nyourself', style: _titleStyle),
          const SizedBox(height: 24),

          // Gender selector
          Text('Gender',
              style: GoogleFonts.outfit(
                  color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Row(
            children: genders.map((g) {
              final isSelected = gender == g['key'];
              return Expanded(
                child: GestureDetector(
                  onTap: () => onGenderChanged(g['key']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary.withOpacity(0.12)
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary
                            : const Color(0xFF2A2A2A),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      g['label']!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: isSelected ? AppTheme.primary : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          _SliderRow(
            label: 'Age',
            value: age,
            unit: 'yrs',
            min: 12,
            max: 80,
            onChanged: onAgeChanged,
          ),
          const SizedBox(height: 20),
          _SliderRow(
            label: 'Weight',
            value: weight,
            unit: 'kg',
            min: 30,
            max: 200,
            onChanged: onWeightChanged,
          ),
          const SizedBox(height: 20),
          _SliderRow(
            label: 'Height',
            value: height,
            unit: 'cm',
            min: 100,
            max: 250,
            onChanged: onHeightChanged,
          ),
          const SizedBox(height: 32),
          _GreenButton(text: 'Continue', onTap: onNext),
        ],
      ),
    );
  }
}
// PAGE 3: TRAINING EXPERIENCE
class _ExperiencePage extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onNext;

  const _ExperiencePage({
    required this.selected,
    required this.onSelected,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final levels = [
      {
        'key': 'beginner',
        'emoji': '🌱',
        'label': 'Beginner',
        'desc': 'Less than 1 year of training',
        'sub': 'Learning the basics, building habits',
      },
      {
        'key': 'intermediate',
        'emoji': '⚡',
        'label': 'Intermediate',
        'desc': '1–3 years of consistent training',
        'sub': 'Comfortable with compound movements',
      },
      {
        'key': 'advanced',
        'emoji': '🏆',
        'label': 'Advanced',
        'desc': '3+ years of serious training',
        'sub': 'Optimising for performance & PRs',
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Training\nExperience', style: _titleStyle),
          const SizedBox(height: 8),
          Text('This helps us calibrate form thresholds and coaching tips.',
              style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 28),
          ...levels.map((lvl) {
            final isSelected = selected == lvl['key'];
            return GestureDetector(
              onTap: () => onSelected(lvl['key']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primary.withOpacity(0.1)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : const Color(0xFF2A2A2A),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(
                          color: AppTheme.primary.withOpacity(0.15),
                          blurRadius: 16)]
                      : [],
                ),
                child: Row(
                  children: [
                    Text(lvl['emoji']!,
                        style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lvl['label']!,
                              style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          Text(lvl['desc']!,
                              style: GoogleFonts.outfit(
                                  color: Colors.white54, fontSize: 12)),
                          Text(lvl['sub']!,
                              style: GoogleFonts.outfit(
                                  color: Colors.white24, fontSize: 11)),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded,
                          color: AppTheme.primary),
                  ],
                ),
              ),
            );
          }).toList(),
          const SizedBox(height: 8),
          _GreenButton(text: 'Continue', onTap: onNext),
        ],
      ),
    );
  }
}
// PAGE 4: GOAL SELECTION
class _GoalPage extends StatelessWidget {
  final String selectedGoal;
  final ValueChanged<String> onGoalSelected;
  final VoidCallback onNext;

  const _GoalPage({
    required this.selectedGoal,
    required this.onGoalSelected,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final goals = [
      {
        'key': 'strength',
        'emoji': '💪',
        'label': 'Strength',
        'desc': 'Build muscle & lift heavier'
      },
      {
        'key': 'endurance',
        'emoji': '🏃',
        'label': 'Endurance',
        'desc': 'Improve cardio & stamina'
      },
      {
        'key': 'weight_loss',
        'emoji': '🔥',
        'label': 'Weight Loss',
        'desc': 'Burn fat & stay lean'
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What\'s your\ngoal?', style: _titleStyle),
          const SizedBox(height: 28),
          ...goals.map((g) {
            final isSelected = selectedGoal == g['key'];
            return GestureDetector(
              onTap: () => onGoalSelected(g['key']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primary.withOpacity(0.1)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : const Color(0xFF2A2A2A),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(g['emoji']!, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g['label']!,
                              style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          Text(g['desc']!,
                              style: GoogleFonts.outfit(
                                  color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded,
                          color: AppTheme.primary),
                  ],
                ),
              ),
            );
          }).toList(),
          const SizedBox(height: 8),
          _GreenButton(text: '🚀  Start Training', onTap: onNext),
        ],
      ),
    );
  }
}
// SHARED WIDGETS
final _titleStyle = GoogleFonts.outfit(
  color: Colors.white,
  fontSize: 30,
  fontWeight: FontWeight.bold,
  height: 1.2,
);

class _GreenButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _GreenButton({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
              color: Colors.black, fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final double min, max;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label, required this.value, required this.unit,
    required this.min, required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
            Text('${value.round()} $unit',
                style: GoogleFonts.outfit(
                    color: AppTheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: const Color(0xFF2A2A2A),
            thumbColor: AppTheme.primary,
            overlayColor: AppTheme.primary.withOpacity(0.15),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}