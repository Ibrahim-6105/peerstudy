// Central router that defines navigation for PeerStudy.
// This router handles page construction and route transitions.

import 'package:flutter/material.dart';

import '../../features/admin/presentation/screens/admin_dashboard_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/landing_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/student_shell_screen.dart';
import '../../features/moderator/presentation/screens/moderator_dashboard_screen.dart';
import '../../features/profile/presentation/screens/about_screen.dart';
import '../../features/profile/presentation/screens/privacy_policy_screen.dart';
import '../../features/profile/presentation/screens/settings_screen.dart';
import '../../features/profile/presentation/screens/support_screen.dart';
import '../../features/profile/presentation/screens/terms_screen.dart';
import '../constants/app_routes.dart';

class AppRouter {
  // Builds the right screen for each named route in one predictable place.
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case AppRoutes.landing:
        return MaterialPageRoute(builder: (_) => const LandingScreen());
      case AppRoutes.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case AppRoutes.signup:
        return MaterialPageRoute(builder: (_) => const SignUpScreen());
      case AppRoutes.forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());
      case AppRoutes.studentShell:
        return MaterialPageRoute(builder: (_) => const StudentShellScreen());
      case AppRoutes.moderatorDashboard:
        return MaterialPageRoute(
          builder: (_) => const ModeratorDashboardScreen(),
        );
      case AppRoutes.adminDashboard:
        return MaterialPageRoute(builder: (_) => const AdminDashboardScreen());
      case AppRoutes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case AppRoutes.privacy:
        return MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen());
      case AppRoutes.terms:
        return MaterialPageRoute(builder: (_) => const TermsScreen());
      case AppRoutes.support:
        return MaterialPageRoute(builder: (_) => const SupportScreen());
      case AppRoutes.about:
        return MaterialPageRoute(builder: (_) => const AboutScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text(
                'Page not found: ${settings.name}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        );
    }
  }
}
