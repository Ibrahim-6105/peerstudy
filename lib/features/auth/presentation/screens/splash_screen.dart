// Splash screen shown while Firebase initializes and auth state is checked.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  // Creates the state that performs the first auth redirect.
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  // Starts the auth check as soon as the splash screen appears.
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  // Waits briefly, checks auth, then sends the user to the right first screen.
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
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: LoadingView(message: 'Starting PeerStudy...'));
  }
}
