import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
final List<Map<String, dynamic>> _allExercises = [
  {'name': 'Squat', 'group': 'Lower Body', 'type': 'Barbell', 'muscles': 'Quads, Glutes, Hamstrings', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Deadlift', 'group': 'Lower Body', 'type': 'Barbell', 'muscles': 'Hamstrings, Glutes, Lower Back', 'icon': Icons.fitness_center},
  {'name': 'Bench Press', 'group': 'Upper Body', 'type': 'Barbell', 'muscles': 'Chest, Triceps, Shoulders', 'icon': Icons.fitness_center},
  {'name': 'Overhead Press', 'group': 'Upper Body', 'type': 'Barbell', 'muscles': 'Deltoids, Triceps', 'icon': Icons.fitness_center},
  {'name': 'Barbell Row', 'group': 'Upper Body', 'type': 'Barbell', 'muscles': 'Lats, Rhomboids, Biceps', 'icon': Icons.fitness_center},
  {'name': 'Front Squat', 'group': 'Lower Body', 'type': 'Barbell', 'muscles': 'Quads, Core, Glutes', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Romanian Deadlift', 'group': 'Lower Body', 'type': 'Barbell', 'muscles': 'Hamstrings, Glutes', 'icon': Icons.fitness_center},
  {'name': 'Incline Bench', 'group': 'Upper Body', 'type': 'Barbell', 'muscles': 'Upper Chest, Triceps, Deltoids', 'icon': Icons.fitness_center},
  {'name': 'Pull Up', 'group': 'Upper Body', 'type': 'Bodyweight', 'muscles': 'Lats, Biceps', 'icon': Icons.fitness_center},
  {'name': 'Chin Up', 'group': 'Upper Body', 'type': 'Bodyweight', 'muscles': 'Biceps, Lats', 'icon': Icons.fitness_center},
  {'name': 'Push Up', 'group': 'Upper Body', 'type': 'Bodyweight', 'muscles': 'Chest, Triceps, Shoulders', 'icon': Icons.fitness_center},
  {'name': 'Dips', 'group': 'Upper Body', 'type': 'Bodyweight', 'muscles': 'Triceps, Chest', 'icon': Icons.fitness_center},
  {'name': 'Bicep Curl', 'group': 'Upper Body', 'type': 'Bilateral', 'muscles': 'Biceps', 'icon': Icons.fitness_center},
  {'name': 'Hammer Curl', 'group': 'Upper Body', 'type': 'Bilateral', 'muscles': 'Brachialis, Biceps', 'icon': Icons.fitness_center},
  {'name': 'Tricep Extension', 'group': 'Upper Body', 'type': 'Bilateral', 'muscles': 'Triceps', 'icon': Icons.fitness_center},
  {'name': 'Skull Crusher', 'group': 'Upper Body', 'type': 'Barbell', 'muscles': 'Triceps', 'icon': Icons.fitness_center},
  {'name': 'Lateral Raise', 'group': 'Upper Body', 'type': 'Bilateral', 'muscles': 'Lateral Deltoids', 'icon': Icons.fitness_center},
  {'name': 'Front Raise', 'group': 'Upper Body', 'type': 'Bilateral', 'muscles': 'Front Deltoids', 'icon': Icons.fitness_center},
  {'name': 'Face Pull', 'group': 'Upper Body', 'type': 'Bilateral', 'muscles': 'Rear Deltoids, Traps', 'icon': Icons.fitness_center},
  {'name': 'Lat Pulldown', 'group': 'Upper Body', 'type': 'Bilateral', 'muscles': 'Lats, Biceps', 'icon': Icons.fitness_center},
  {'name': 'Seated Row', 'group': 'Upper Body', 'type': 'Bilateral', 'muscles': 'Rhomboids, Lats', 'icon': Icons.fitness_center},
  {'name': 'Shrugs', 'group': 'Upper Body', 'type': 'Barbell', 'muscles': 'Traps', 'icon': Icons.fitness_center},
  {'name': 'Leg Press', 'group': 'Lower Body', 'type': 'Bilateral', 'muscles': 'Quads, Glutes', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Leg Extension', 'group': 'Lower Body', 'type': 'Bilateral', 'muscles': 'Quads', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Leg Curl', 'group': 'Lower Body', 'type': 'Bilateral', 'muscles': 'Hamstrings', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Calf Raise', 'group': 'Lower Body', 'type': 'Bodyweight', 'muscles': 'Calves', 'icon': Icons.directions_walk_rounded},
  {'name': 'Lunge', 'group': 'Lower Body', 'type': 'Bilateral', 'muscles': 'Quads, Glutes', 'icon': Icons.directions_walk_rounded},
  {'name': 'Bulgarian Squat', 'group': 'Lower Body', 'type': 'Bilateral', 'muscles': 'Quads, Glutes', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Hip Thrust', 'group': 'Lower Body', 'type': 'Barbell', 'muscles': 'Glutes', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Glute Bridge', 'group': 'Lower Body', 'type': 'Bodyweight', 'muscles': 'Glutes', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Good Morning', 'group': 'Lower Body', 'type': 'Barbell', 'muscles': 'Hamstrings, Lower Back', 'icon': Icons.fitness_center},
  {'name': 'Kettlebell Swing', 'group': 'Full Body', 'type': 'Bilateral', 'muscles': 'Glutes, Hamstrings, Core', 'icon': Icons.fitness_center},
  {'name': 'Clean and Jerk', 'group': 'Full Body', 'type': 'Barbell', 'muscles': 'Full Body Power', 'icon': Icons.fitness_center},
  {'name': 'Snatch', 'group': 'Full Body', 'type': 'Barbell', 'muscles': 'Full Body Power', 'icon': Icons.fitness_center},
  {'name': 'Crunch', 'group': 'Core', 'type': 'Bodyweight', 'muscles': 'Abs', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Sit Up', 'group': 'Core', 'type': 'Bodyweight', 'muscles': 'Abs, Hip Flexors', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Russian Twist', 'group': 'Core', 'type': 'Bodyweight', 'muscles': 'Obliques', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Leg Raise', 'group': 'Core', 'type': 'Bodyweight', 'muscles': 'Lower Abs', 'icon': Icons.accessibility_new_rounded},
  {'name': 'Plank', 'group': 'Core', 'type': 'Duration', 'muscles': 'Core Stability', 'icon': Icons.timer_outlined},
  {'name': 'Wall Sit', 'group': 'Lower Body', 'type': 'Duration', 'muscles': 'Quads', 'icon': Icons.timer_outlined},
  {'name': 'Mountain Climber', 'group': 'Core', 'type': 'Cardio', 'muscles': 'Core, Cardio', 'icon': Icons.directions_run_rounded},
  {'name': 'High Knees', 'group': 'Full Body', 'type': 'Cardio', 'muscles': 'Cardio, Calves', 'icon': Icons.directions_run_rounded},
  {'name': 'Jumping Jack', 'group': 'Full Body', 'type': 'Cardio', 'muscles': 'Cardio, Full Body', 'icon': Icons.directions_run_rounded},
  {'name': 'Burpee', 'group': 'Full Body', 'type': 'Cardio', 'muscles': 'Full Body Conditioning', 'icon': Icons.directions_run_rounded},
  {'name': 'Box Jump', 'group': 'Lower Body', 'type': 'Bodyweight', 'muscles': 'Power, Quads, Calves', 'icon': Icons.directions_run_rounded},
];

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _searchQuery = '';
  final Set<String> _favorites = {'Squat', 'Deadlift', 'Push Up'};
  String _filter = 'All';

  List<Map<String, dynamic>> get _filtered {
    return _allExercises.where((e) {
      final matchesSearch = e['name'].toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesFilter = _filter == 'All' || e['group'] == _filter;
      return matchesSearch && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSearch(),
            _buildFilters(),
            Expanded(child: _buildGrid()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Exercise Library',
            style: GoogleFonts.outfit(
              color: AppTheme.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '18 exercises',
            style: GoogleFonts.outfit(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        style: GoogleFonts.outfit(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search exercises...',
          hintStyle: GoogleFonts.outfit(color: AppTheme.textSecondary),
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
          filled: true,
          fillColor: AppTheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final filters = ['All', 'Upper Body', 'Lower Body', 'Full Body'];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: filters.map((f) {
          final isSelected = _filter == f;
          return GestureDetector(
            onTap: () => setState(() => _filter = f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.primary : const Color(0xFF2A2A2A),
                ),
              ),
              child: Text(
                f,
                style: GoogleFonts.outfit(
                  color: isSelected ? Colors.black : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGrid() {
    if (_filtered.isEmpty) {
      return Center(
        child: Text(
          'No exercises found',
          style: GoogleFonts.outfit(color: AppTheme.textSecondary),
        ),
      );
    }
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final ex = _filtered[index];
        final isFav = _favorites.contains(ex['name']);
        return GestureDetector(
          onTap: () => _showExerciseDetail(context, ex),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(ex['icon'] as IconData, color: AppTheme.primary, size: 20),
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        if (isFav) _favorites.remove(ex['name']);
                        else _favorites.add(ex['name']);
                      }),
                      child: Icon(
                        isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isFav ? const Color(0xFFFF5252) : AppTheme.textSecondary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  ex['name'],
                  style: GoogleFonts.outfit(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ex['muscles'],
                  style: GoogleFonts.outfit(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                _TypeBadge(type: ex['type']),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showExerciseDetail(BuildContext context, Map<String, dynamic> ex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(ex['icon'] as IconData, color: AppTheme.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ex['name'],
                          style: GoogleFonts.outfit(
                              color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(ex['group'],
                          style: GoogleFonts.outfit(color: AppTheme.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                _TypeBadge(type: ex['type']),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow(label: 'Target Muscles', value: ex['muscles']),
            _DetailRow(label: 'Tracking Method', value: 'MediaPipe Pose Estimation'),
            _DetailRow(label: 'IMU Velocity', value: ex['type'] == 'Barbell' ? 'Enabled' : 'Not applicable'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  Color get _color {
    switch (type) {
      case 'Barbell': return const Color(0xFFFF8C00);
      case 'Bilateral': return const Color(0xFF3EA6FF);
      case 'Duration': return const Color(0xFFBB86FC);
      case 'Cardio': return const Color(0xFFFF5252);
      default: return const Color(0xFF00E5FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(type,
          style: GoogleFonts.outfit(color: _color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: GoogleFonts.outfit(color: AppTheme.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.outfit(
                    color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}