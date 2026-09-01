// PeerStudy's first page for a fresh or signed-out device.
// It uses one ordinary StatefulWidget and setState for the loading spinner.

// Material supplies Form, buttons, icons, SnackBar, and navigation widgets.
import 'package:flutter/material.dart';

// AppButton is the shared compact blue submit button.
import 'package:peerstudy/components/app_button.dart';

// AppFormField supplies consistent labels, icons, and password visibility.
import 'package:peerstudy/components/app_form_field.dart';

// AuthPageShell supplies the white/dark SafeArea and responsive form width.
import 'package:peerstudy/components/auth_page_shell.dart';

// AppUser supplies the exact Student and Admin role values.
import 'package:peerstudy/models/app_user.dart';

// Route names keep navigation lines readable for a Flutter beginner.
import 'package:peerstudy/routes/app_routes.dart';

// AuthService performs real Supabase login and saves the safe login marker.
import 'package:peerstudy/services/auth_service.dart';

// Shared validators accept a LIMU email or the exact Admin alias.
import 'package:peerstudy/utils/validators.dart';

// LoginScreen optionally receives one friendly message from a protected route.
class LoginScreen extends StatefulWidget {
  // The message is null during a normal application start.
  const LoginScreen({this.initialErrorMessage, super.key});

  // Raw backend messages are never passed here; only friendly app text is used.
  final String? initialErrorMessage;

  // Create the small local state for the two-field form.
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// This class deliberately uses setState and no state-management package.
class _LoginScreenState extends State<LoginScreen> {
  // The form key asks both visible validators to run together.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // This controller reads a LIMU email or the word admin.
  final TextEditingController _emailController = TextEditingController();

  // This controller reads the password entered by the user.
  final TextEditingController _passwordController = TextEditingController();

  // True disables actions while Supabase verifies the account.
  bool _isLoading = false;

  // Show an optional route message once the Scaffold is mounted.
  @override
  void initState() {
    // Flutter requires the parent initialization first.
    super.initState();

    // Trim the optional message so empty text is never displayed.
    final message = widget.initialErrorMessage?.trim();

    // A normal startup has no message to show.
    if (message == null || message.isEmpty) return;

    // SnackBar needs the first complete frame and a mounted Scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  // Validate, sign in, save the safe marker, and open the trusted role page.
  Future<void> _login() async {
    // Stop before networking when one field has a visible validation error.
    if (!_formKey.currentState!.validate()) return;

    // Close the keyboard so the result and spinner remain visible.
    FocusScope.of(context).unfocus();

    // One local state change disables duplicate requests.
    setState(() => _isLoading = true);

    // Use the single plain authentication object shared by the application.
    final auth = AuthService.instance;

    // AuthService normalizes the identifier and talks to real Supabase Auth.
    final message = await auth.signIn(
      _emailController.text.trim(),
      _passwordController.text,
    );

    // An old screen must not update after navigation removed it.
    if (!mounted) return;

    // Hide the spinner after the complete Auth and profile check.
    setState(() => _isLoading = false);

    // A returned String is safe, short user-facing error text.
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    // AuthService sets this only after validating the matching profile row.
    final user = auth.currentUser;

    // Fail safely if an SDK response ended without a usable profile.
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account could not be loaded.')),
      );
      return;
    }

    // Choose only a route allowed by the server-controlled account role.
    String? destination;

    // Active Students enter the normal study application.
    if (user.role == AppUser.studentRole) {
      destination = AppRoutes.studentShell;
    }

    // The pre-created Admin enters the management dashboard.
    if (user.role == AppUser.adminRole) {
      destination = AppRoutes.adminDashboard;
    }

    // Unknown roles cannot keep a partial or persisted session.
    if (destination == null) {
      await auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This account role is not supported.')),
      );
      return;
    }

    // Remove Login so the system Back button cannot reveal the password form.
    Navigator.pushNamedAndRemoveUntil(context, destination, (_) => false);
  }

  // Release native text controllers when Flutter removes this page.
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Build a compact blue-and-white login form inside the shared SafeArea.
  @override
  Widget build(BuildContext context) {
    // AuthPageShell prevents repeated layout code across account screens.
    return AuthPageShell(
      title: 'Welcome back',
      subtitle: 'Sign in with your LIMU account to continue.',
      icon: Icons.login_rounded,
      showBackButton: false,
      // AutofillGroup lets the phone safely suggest stored account details.
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Students enter university email; Admin may enter `admin`.
              AppFormField(
                label: 'Email or Admin name',
                controller: _emailController,
                hintText: 'name@limu.edu.ly or admin',
                prefixIcon: Icons.person_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                validator: (value) {
                  // Empty input cannot identify an account.
                  if (value == null || value.trim().isEmpty) {
                    return 'Email or Admin name is required.';
                  }

                  // Only a complete LIMU email or exact Admin alias is accepted.
                  if (normalizedLoginIdentifier(value) == null) {
                    return 'Use your full @limu.edu.ly email or admin.';
                  }

                  // Null tells Flutter this field passed validation.
                  return null;
                },
              ),

              // Keep the two fields distinct without creating a large gap.
              const SizedBox(height: 13),

              // The eye button can reveal or hide the password locally.
              AppFormField(
                label: 'Password',
                controller: _passwordController,
                hintText: 'Enter your password',
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) {
                  if (!_isLoading) _login();
                },
                validator: (value) {
                  // Every account requires a password.
                  if (value == null || value.isEmpty) {
                    return 'Password is required.';
                  }

                  // Six characters keeps the requested Admin login compatible.
                  if (!isValidPassword(value)) {
                    return 'Password must be at least 6 characters.';
                  }

                  // Null tells Flutter this field passed validation.
                  return null;
                },
              ),

              // Keep recovery next to the password without increasing noise.
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.pushNamed(
                          context,
                          AppRoutes.forgotPassword,
                        ),
                  child: const Text('Forgot password?'),
                ),
              ),

              // Submit the real account request.
              AppButton(
                label: 'Sign In',
                onPressed: _login,
                isLoading: _isLoading,
              ),

              // The secondary registration action stays visually quiet.
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.pushNamed(context, AppRoutes.signup),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Sign Up'),
              ),

              // Privacy remains available before an account signs in.
              const SizedBox(height: 4),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.pushNamed(context, AppRoutes.privacy),
                child: const Text('Privacy Policy'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
