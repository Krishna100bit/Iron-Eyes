import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/database/db_helper.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/user_profile_provider.dart';
import 'features/onboarding/view/onboarding_screen.dart';
import 'features/dashboard/view/dashboard_screen.dart';
import 'features/camera_workout/view/workout_screen.dart';
import 'features/library/view/library_screen.dart';
import 'features/profile/view/profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite database (creates tables on first launch)
  await DbHelper.instance.db;

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: IronEyeApp()));
}

class IronEyeApp extends ConsumerWidget {
  const IronEyeApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);

    return MaterialApp(
      title: 'Iron Eye',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme.copyWith(
        textTheme: GoogleFonts.outfitTextTheme(AppTheme.darkTheme.textTheme),
      ),
      home: profile == null
          ? const OnboardingScreen()
          : const MainNavigationShell(),
    );
  }
}

final navigationIndexProvider = StateProvider<int>((ref) => 0);

class MainNavigationShell extends ConsumerWidget {
  const MainNavigationShell({Key? key}) : super(key: key);

  final List<Widget> _screens = const [
    DashboardScreen(),
    WorkoutScreen(),
    LibraryScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navigationIndexProvider);

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1A1A1A), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (i) => ref.read(navigationIndexProvider.notifier).state = i,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.videocam_outlined),
              activeIcon: Icon(Icons.videocam_rounded),
              label: 'Workout',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_outlined),
              activeIcon: Icon(Icons.grid_view_rounded),
              label: 'Library',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
