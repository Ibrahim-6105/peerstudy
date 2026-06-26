// Central router for PeerStudy.
// When a screen calls Navigator.pushNamed, Flutter comes here to decide which
// widget should be opened for that route name.

import 'package:flutter/material.dart';
import 'package:peerstudy/routes/app_routes.dart';
import 'package:peerstudy/screens/admin/admin_dashboard_screen.dart';
import 'package:peerstudy/screens/auth/forgot_password_screen.dart';
import 'package:peerstudy/screens/auth/landing_screen.dart';
import 'package:peerstudy/screens/auth/login_screen.dart';
import 'package:peerstudy/screens/auth/signup_screen.dart';
import 'package:peerstudy/screens/auth/splash_screen.dart';
import 'package:peerstudy/screens/moderator/moderator_dashboard_screen.dart';
import 'package:peerstudy/screens/profile/about_screen.dart';
import 'package:peerstudy/screens/profile/privacy_policy_screen.dart';
import 'package:peerstudy/screens/profile/settings_screen.dart';
import 'package:peerstudy/screens/profile/support_screen.dart';
import 'package:peerstudy/screens/profile/terms_screen.dart';
import 'package:peerstudy/screens/student/student_shell_screen.dart';

class AppRouter {
  // Builds the right screen for each named route.
  // If you add a new page later, add its route name in app_routes.dart and add a
  // matching case here so Flutter knows how to open it.
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
