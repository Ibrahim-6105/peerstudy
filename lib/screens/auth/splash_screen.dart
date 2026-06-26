// Splash screen shown while authentication is checked.
// This page is intentionally tiny: it shows loading, waits briefly, then decides
// whether the user should see landing, student, moderator, or admin screens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerstudy/components/loading_view.dart';
import 'package:peerstudy/providers/auth_provider.dart';
import 'package:peerstudy/routes/app_routes.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  // Creates the state that performs the first auth redirect.
  // ConsumerState gives this screen access to Riverpod providers through ref.
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  // Starts the auth check as soon as the splash screen appears.
  // initState is used because this work should happen once, not every rebuild.
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  // Waits briefly, checks auth, then sends the user to the right first screen.
  // The mounted check protects navigation if the splash screen was removed
  // before the async work finished.
  Future<void> _checkAuth() async {
    final authState = ref.read(authStateProvider);
    await Future.delayed(const Duration(milliseconds: 600));

    if (authState.isLoading) {
      // Wait for auth initialization before redirect.
      await ref.read(authNotifierProvider.notifier).initialize();
    }

    final user = ref.read(currentUserProvider);
    if (!mounted) return;

    if (user != null) {
      if (user.role == 'student') {
        Navigator.pushReplacementNamed(context, AppRoutes.studentShell);
      } else if (user.role == 'moderator') {
        Navigator.pushReplacementNamed(context, AppRoutes.moderatorDashboard);
      } else if (user.role == 'admin') {
        Navigator.pushReplacementNamed(context, AppRoutes.adminDashboard);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.landing);
      }
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.landing);
    }
  }

  // Shows a calm loading view while startup decides where to navigate.
  // The reusable LoadingView keeps this screen visually consistent with future
  // loading states elsewhere in the app.
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: LoadingView(message: 'Starting PeerStudy...'));
  }
}
