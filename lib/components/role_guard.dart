// This small widget checks a real Supabase session before protected content.
// It uses only StatefulWidget and setState, so beginners do not need Riverpod.

// Material supplies widgets, navigation, buttons, icons, and colors.
import 'package:flutter/material.dart';

// AppUser contains the two supported Student and Admin roles.
import 'package:peerstudy/models/app_user.dart';

// Route names keep redirects readable and free from repeated strings.
import 'package:peerstudy/routes/app_routes.dart';

// AuthService reads the current Supabase session and matching profile directly.
import 'package:peerstudy/services/auth_service.dart';

// This pure helper keeps the final access rule easy to read and test.
bool canAccessAnyRole(AppUser? user, Set<String> allowedRoles) {
  // The user must exist, be active, be supported, and match this route's role.
  return user != null &&
      user.canUseProtectedFeatures &&
      AppUser.supportedRoles.contains(user.role) &&
      allowedRoles.contains(user.role);
}

// RoleGuard waits for a real profile check before drawing its protected child.
class RoleGuard extends StatefulWidget {
  // Each protected route supplies its accepted roles and the real page widget.
  const RoleGuard({
    required this.allowedRoles,
    required this.child,
    this.testUser,
    super.key,
  });

  // A set supports Student-only, Admin-only, or shared account screens.
  final Set<String> allowedRoles;

  // The protected screen appears only after the server check succeeds.
  final Widget child;

  // Focused widget tests may supply a profile without contacting live Supabase.
  // Real application routes never set this value.
  @visibleForTesting
  final AppUser? testUser;

  // Create local loading/error state for this one route check.
  @override
  State<RoleGuard> createState() => _RoleGuardState();
}

// The guard has only three simple states: checking, allowed, or retry needed.
class _RoleGuardState extends State<RoleGuard> {
  // True while Supabase is checking the saved session and profile.
  bool _isChecking = true;

  // True only after the current user passes the route's role check.
  bool _isAllowed = false;

  // A network failure stays on a retry page instead of pretending signed-out.
  String? _connectionError;

  // This prevents two post-frame callbacks from redirecting at the same time.
  bool _redirectScheduled = false;

  // Check the route once when Flutter first creates it.
  @override
  void initState() {
    // Perform normal StatefulWidget initialization first.
    super.initState();

    // Start after the first frame so navigation is always safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A removed route does not need any asynchronous work.
      if (mounted) _checkAccess();
    });
  }

  // Verify the real persisted Auth session and current profile row.
  Future<void> _checkAccess() async {
    // Show the small progress view during first check and manual retries.
    setState(() {
      _isChecking = true;
      _isAllowed = false;
      _connectionError = null;
    });

    // A focused test can exercise the visual guard with no live backend.
    if (widget.testUser != null) {
      // Apply the exact same role decision used after a real profile query.
      if (canAccessAnyRole(widget.testUser, widget.allowedRoles)) {
        setState(() {
          _isChecking = false;
          _isAllowed = true;
        });
      }

      // The valid-user regression test needs no network or navigation.
      return;
    }

    // Read the one plain authentication service used by every screen.
    final auth = AuthService.instance;

    // Only a genuinely missing SDK session redirects straight to Login.
    if (!auth.hasSession) {
      _redirectTo(AppRoutes.login);
      return;
    }

    try {
      // Refresh the profile instead of trusting an old in-memory value.
      final user = await auth.refreshCurrentUser();

      // Stop if the route was removed while the network call was running.
      if (!mounted) return;

      // Missing or rejected profiles are signed out by AuthService.
      if (user == null) {
        _redirectTo(AppRoutes.login, message: auth.lastMessage);
        return;
      }

      // A valid user on the wrong dashboard returns to their own dashboard.
      if (!canAccessAnyRole(user, widget.allowedRoles)) {
        _redirectTo(_homeRouteFor(user.role));
        return;
      }

      // The complete server check passed, so protected content may be shown.
      setState(() {
        _isChecking = false;
        _isAllowed = true;
      });
    } catch (_) {
      // A temporary profile query error is not the same as being signed out.
      if (!mounted) return;

      // Keep the user on a useful Retry page without exposing SDK details.
      setState(() {
        _isChecking = false;
        _connectionError =
            'PeerStudy could not verify your account. Check your connection and try again.';
      });
    }
  }

  // Schedule one clean navigation after the current build frame.
  void _redirectTo(String route, {String? message}) {
    // Do not schedule the same route replacement twice.
    if (_redirectScheduled) return;

    // Remember that this guard is already leaving.
    _redirectScheduled = true;

    // Flutter navigation is safest after the current frame completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A removed guard has no Navigator to update.
      if (!mounted) return;

      // Replace the complete history so Back cannot reopen a protected page.
      Navigator.pushNamedAndRemoveUntil(
        context,
        route,
        (_) => false,
        arguments: message,
      );
    });
  }

  // Return the normal dashboard belonging to a verified role.
  String _homeRouteFor(String role) {
    // Admin accounts always return to the management dashboard.
    if (role == AppUser.adminRole) return AppRoutes.adminDashboard;

    // Active Student accounts return to the student navigation shell.
    if (role == AppUser.studentRole) return AppRoutes.studentShell;

    // An unexpected value fails closed to the public Login form.
    return AppRoutes.login;
  }

  // Let the user deliberately sign out if a connection problem continues.
  Future<void> _signOut() async {
    // Remove the Supabase session and the simple local AppUser value.
    await AuthService.instance.signOut();

    // Stop if the route disappeared while sign-out was finishing.
    if (!mounted) return;

    // Go to the normal Login start page.
    _redirectTo(AppRoutes.login);
  }

  // Build protected content, a progress view, or a small retry view.
  @override
  Widget build(BuildContext context) {
    // Show the real page only after this route's check succeeded.
    if (_isAllowed) return widget.child;

    // Show a calm progress screen during the server check and redirects.
    if (_isChecking || _connectionError == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Checking your account...'),
              ],
            ),
          ),
        ),
      );
    }

    // A network error receives Retry and Sign Out instead of a false auth error.
    return Scaffold(
      appBar: AppBar(title: const Text('Connection Check')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // This icon communicates a temporary connection problem.
                  const Icon(Icons.cloud_off_outlined, size: 56),

                  // Add space before the message.
                  const SizedBox(height: 16),

                  // Display only the friendly local text.
                  Text(_connectionError!, textAlign: TextAlign.center),

                  // Add space before the main retry action.
                  const SizedBox(height: 20),

                  // Retry repeats the exact real-session check.
                  FilledButton.icon(
                    onPressed: _checkAccess,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),

                  // Keep the secondary choice visually separate.
                  const SizedBox(height: 8),

                  // The user can intentionally return to a fresh Login form.
                  TextButton(
                    onPressed: _signOut,
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
