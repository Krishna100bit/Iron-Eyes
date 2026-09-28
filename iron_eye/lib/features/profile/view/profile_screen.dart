import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/providers/workout_history_provider.dart';
import '../../../core/providers/ble_provider.dart';
import '../../device/view/device_screen.dart';
import '../../../core/models/user_profile.dart';
import '../../onboarding/view/onboarding_screen.dart';
import '../../../main.dart';
import 'edit_profile_sheet.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final history = ref.watch(workoutHistoryProvider);
    final ble = ref.watch(bleProvider);

    if (profile == null) return const SizedBox();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(context, ref, profile),
              _buildLifetimeStats(history),
              _buildGoals(profile, history),
              _buildAchievements(history),
              _buildSettings(context, ref, ble),
              const SizedBox(height: 32),
              _buildDangerZone(context, ref),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, UserProfile profile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showEditProfileSheet(context, profile),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.primary, width: 2.5),
              ),
              child: Center(
                child: Text(
                  profile.avatar ?? '👦',
                  style: const TextStyle(fontSize: 40),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.name,
                    style: GoogleFonts.outfit(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                Text(
                    '${profile.genderDisplay}  ·  ${profile.age} yrs  ·  ${profile.weight.toStringAsFixed(0)} kg',
                    style: GoogleFonts.outfit(
                        color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                    '${profile.height.toStringAsFixed(0)} cm  ·  ${profile.experienceDisplay}',
                    style: GoogleFonts.outfit(
                        color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${profile.goalEmoji} Goal: ${profile.goalDisplay}',
                    style: GoogleFonts.outfit(
                        color: AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showEditProfileSheet(context, profile),
            icon: const Icon(Icons.edit_outlined,
                color: AppTheme.textSecondary, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildLifetimeStats(WorkoutHistoryState history) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('All-Time Stats',
              style: GoogleFonts.outfit(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _StatCard(
                      label: 'Workouts',
                      value: '${history.totalWorkouts}',
                      icon: Icons.fitness_center_rounded)),
              const SizedBox(width: 10),
              Expanded(
                  child: _StatCard(
                      label: 'Total Reps',
                      value: _formatNumber(history.totalReps),
                      icon: Icons.repeat_rounded)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _StatCard(
                      label: 'Best Streak',
                      value: '${history.streak} days',
                      icon: Icons.local_fire_department_rounded)),
              const SizedBox(width: 10),
              Expanded(
                  child: _StatCard(
                      label: 'Avg Form',
                      value: history.avgFormGrade,
                      icon: Icons.star_rounded)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGoals(UserProfile profile, WorkoutHistoryState history) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weekly Goals',
              style: GoogleFonts.outfit(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _GoalRow(
            label: 'Workouts',
            current: history.thisWeekWorkouts,
            target: profile.weeklyWorkoutTarget,
            unit: 'sessions',
            color: AppTheme.primary,
          ),
          const SizedBox(height: 10),
          _GoalRow(
            label: 'Total Reps',
            current: history.thisWeekReps,
            target: profile.weeklyRepTarget,
            unit: 'reps',
            color: const Color(0xFF3EA6FF),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievements(WorkoutHistoryState history) {
    final badges = [
      {
        'emoji': '🥇',
        'label': 'First Rep',
        'unlocked': history.totalReps >= 1,
        'req': '1 rep'
      },
      {
        'emoji': '💯',
        'label': '100 Reps',
        'unlocked': history.totalReps >= 100,
        'req': '100 reps'
      },
      {
        'emoji': '🔥',
        'label': '7-Day Streak',
        'unlocked': history.streak >= 7,
        'req': '7-day streak'
      },
      {
        'emoji': '⭐',
        'label': 'Perfect Form',
        'unlocked': history.avgFormGrade == 'A',
        'req': 'Avg grade A'
      },
      {
        'emoji': '🏋️',
        'label': '50 Workouts',
        'unlocked': history.totalWorkouts >= 50,
        'req': '50 sessions'
      },
      {
        'emoji': '⚡',
        'label': '1000 Reps',
        'unlocked': history.totalReps >= 1000,
        'req': '1,000 reps'
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Achievements',
              style: GoogleFonts.outfit(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: badges.length,
            itemBuilder: (context, i) {
              final badge = badges[i];
              final unlocked = badge['unlocked'] as bool;
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: unlocked
                          ? AppTheme.primary.withOpacity(0.4)
                          : const Color(0xFF2A2A2A)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(badge['emoji'] as String,
                        style: TextStyle(
                            fontSize: 28,
                            color: unlocked
                                ? null
                                : Colors.transparent.withOpacity(0))),
                    if (!unlocked)
                      const Icon(Icons.lock_outline_rounded,
                          color: Color(0xFF444444), size: 28),
                    const SizedBox(height: 4),
                    Text(badge['label'] as String,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                            color: unlocked
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary.withOpacity(0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettings(BuildContext context, WidgetRef ref, BleState ble) {
    final settings = [
      {
        'icon': Icons.bluetooth_rounded,
        'label': 'VBT DEVICE',
        'sub': ble.isConnected
            ? '${ble.deviceName} · ${ble.batteryPercent}% battery'
            : 'Not Connected',
        'color': const Color(0xFF3EA6FF),
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceScreen())),
      },
      {
        'icon': Icons.info_outline_rounded,
        'label': 'About Iron Eye',
        'sub': 'v1.0.0',
        'color': AppTheme.textSecondary,
        'onTap': () {},
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings',
              style: GoogleFonts.outfit(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Column(
              children: settings.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                return Column(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: Icon(s['icon'] as IconData,
                            color: s['color'] as Color, size: 22),
                        title: Text(s['label'] as String,
                            style: GoogleFonts.outfit(
                                color: AppTheme.textPrimary, fontSize: 14)),
                        subtitle: Text(s['sub'] as String,
                            style: GoogleFonts.outfit(
                                color: AppTheme.textSecondary, fontSize: 12)),
                        trailing: s['label'] == 'About Iron Eye' ? null : const Icon(Icons.chevron_right_rounded,
                            color: AppTheme.textSecondary, size: 18),
                        onTap: s['onTap'] as VoidCallback,
                      ),
                    ),
                    if (i < settings.length - 1)
                      const Divider(
                          color: Color(0xFF2A2A2A),
                          height: 1,
                          indent: 16,
                          endIndent: 16),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditProfileSheet(BuildContext context, UserProfile profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditProfileSheet(initialProfile: profile),
    );
  }

  void _showSnackbar(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.outfit()),
        backgroundColor: AppTheme.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildDangerZone(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Account',
              style: GoogleFonts.outfit(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _showLogoutDialog(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 8),
                  Text('Log Out',
                      style: GoogleFonts.outfit(
                          color: Colors.redAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Delete Profile?', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text('This will permanently delete your profile, all workout history, and reset the app. This cannot be undone.',
            style: GoogleFonts.outfit(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(userProfileProvider.notifier).clearProfile();
              if (context.mounted) {
                // Reset navigation to 0
                ref.read(navigationIndexProvider.notifier).state = 0;
                // It will automatically show OnboardingScreen since profile is null
              }
            },
            child: Text('Delete Everything',
                style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Avatar picker removed, handled by EditProfileSheet

  String _formatNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatCard(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: GoogleFonts.outfit(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text(label,
                    style: GoogleFonts.outfit(
                        color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  final String label;
  final int current;
  final int target;
  final String unit;
  final Color color;

  const _GoalRow({
    required this.label,
    required this.current,
    required this.target,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: GoogleFonts.outfit(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              Text('$current / $target $unit',
                  style: GoogleFonts.outfit(
                      color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFF2A2A2A),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          Text('${(progress * 100).toInt()}% completed',
              style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}