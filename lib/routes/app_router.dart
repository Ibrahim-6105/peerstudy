// Central router for PeerStudy.
// When a screen calls Navigator.pushNamed, Flutter comes here to decide which
// widget should be opened for that route name.
//
// Beginner note:
// A "route" is just the name of a page/screen. For example, `/login` means
// "open the login screen". This file connects those names to actual widgets.

// Material is needed for Route, MaterialPageRoute, Scaffold, Text, and colors.
import 'package:flutter/material.dart';

// RoleGuard stops protected screens from rendering for the wrong profile role.
import 'package:peerstudy/components/role_guard.dart';

// AppRoutes stores the route-name strings in one safe place.
import 'package:peerstudy/routes/app_routes.dart';

// Each screen import below is needed because this router creates those screens.
import 'package:peerstudy/screens/admin/admin_dashboard_screen.dart';
import 'package:peerstudy/screens/auth/forgot_password_screen.dart';
import 'package:peerstudy/screens/auth/login_screen.dart';
import 'package:peerstudy/screens/auth/reset_password_screen.dart';
import 'package:peerstudy/screens/auth/signup_screen.dart';
import 'package:peerstudy/screens/profile/about_screen.dart';
import 'package:peerstudy/screens/profile/community_guidelines_screen.dart';
import 'package:peerstudy/screens/profile/feedback_screen.dart';
import 'package:peerstudy/screens/profile/privacy_policy_screen.dart';
import 'package:peerstudy/screens/profile/settings_screen.dart';
import 'package:peerstudy/screens/profile/support_screen.dart';
import 'package:peerstudy/screens/profile/terms_screen.dart';
import 'package:peerstudy/screens/student/student_shell_screen.dart';

// AppRouter is a utility class; it is not a widget.
// It only contains the static onGenerateRoute method used by MaterialApp.
class AppRouter {
  // Builds the right screen for each named route.
  // If you add a new page later, add its route name in app_routes.dart and add a
  // matching case here so Flutter knows how to open it.
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    // `settings.name` is the route string requested by Navigator.
    // Example: Navigator.pushNamed(context, AppRoutes.login)
    // sends `/login` here.
    switch (settings.name) {
      case AppRoutes.login:
        // Login is shared by the corrected Student and Admin actors.
        final initialMessage = settings.arguments;
        return MaterialPageRoute(
          builder: (_) => LoginScreen(
            initialErrorMessage: initialMessage is String
                ? initialMessage
                : null,
          ),
        );
      case AppRoutes.signup:
        // Signup creates public student accounts only.
        return MaterialPageRoute(builder: (_) => const SignUpScreen());
      case AppRoutes.forgotPassword:
        // Forgot password sends a Supabase recovery email.
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());
      case AppRoutes.resetPassword:
        // A valid Supabase recovery deep link opens the new-password form.
        return MaterialPageRoute(builder: (_) => const ResetPasswordScreen());
      case AppRoutes.studentShell:
        // Student shell is the main student dashboard after login.
        return _roleProtectedRoute(
          allowedRoles: const {'student'},
          builder: (_) => const StudentShellScreen(),
        );
      case AppRoutes.adminDashboard:
        // Admin dashboard is separate because admins manage reports/users.
        return _roleProtectedRoute(
          allowedRoles: const {'admin'},
          builder: (_) => const AdminDashboardScreen(),
        );
      case AppRoutes.settings:
        // Settings is shared by active Students and Admins.
        return _roleProtectedRoute(
          allowedRoles: const {'student', 'admin'},
          builder: (_) => const SettingsScreen(),
        );
      case AppRoutes.privacy:
        // Static privacy information page.
        return MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen());
      case AppRoutes.terms:
        // Static terms information page.
        return MaterialPageRoute(builder: (_) => const TermsScreen());
      case AppRoutes.guidelines:
        // Community rules are shared by both active account roles.
        return _roleProtectedRoute(
          allowedRoles: const {'student', 'admin'},
          builder: (_) => const CommunityGuidelinesScreen(),
        );
      case AppRoutes.feedback:
        // Feedback uses the protected, rate-limited backend endpoint.
        return _roleProtectedRoute(
          allowedRoles: const {'student', 'admin'},
          builder: (_) => const FeedbackScreen(),
        );
      case AppRoutes.support:
        // Support/contact information page.
        return MaterialPageRoute(builder: (_) => const SupportScreen());
      case AppRoutes.about:
        // About page explaining PeerStudy.
        return MaterialPageRoute(builder: (_) => const AboutScreen());
      default:
        // Fallback screen for unknown routes.
        // This helps developers notice route-name mistakes during testing.
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            // SafeArea keeps the fallback message clear of phone system bars.
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    // Show the missing route name so it is easy to debug.
                    'Page not found: ${settings.name}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        );
    }
  }

  // Wraps one named route in the reusable UI guard. This is intentionally a
  // small helper so every protected case above reads the same way.
  static Route<dynamic> _roleProtectedRoute({
    required Set<String> allowedRoles,
    required WidgetBuilder builder,
  }) {
    return MaterialPageRoute(
      builder: (context) =>
          RoleGuard(allowedRoles: allowedRoles, child: builder(context)),
    );
  }
}
