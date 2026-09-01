// This page creates a real public Student account in Supabase.
// It uses one StatefulWidget and setState with no state-management package.

// Material supplies Form, icons, SnackBar, and navigation widgets.
import 'package:flutter/material.dart';

// AppButton gives the submit action a compact loading spinner.
import 'package:peerstudy/components/app_button.dart';

// AppFormField keeps all labels, icons, and password controls consistent.
import 'package:peerstudy/components/app_form_field.dart';

// AuthPageShell provides the responsive SafeArea and blue/white form surface.
import 'package:peerstudy/components/auth_page_shell.dart';

// The Student role constant protects the public signup result.
import 'package:peerstudy/models/app_user.dart';

// Route constants keep navigation statements simple for beginners.
import 'package:peerstudy/routes/app_routes.dart';

// AuthService creates the account, validates its profile, and saves its marker.
import 'package:peerstudy/services/auth_service.dart';

// Shared validators enforce the same LIMU and password rules everywhere.
import 'package:peerstudy/utils/validators.dart';

// SignUpScreen stores only four controllers and one loading boolean.
class SignUpScreen extends StatefulWidget {
  // Public Student registration needs no constructor values.
  const SignUpScreen({super.key});

  // Create the normal local form state.
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

// setState is sufficient because no other page needs this loading value.
class _SignUpScreenState extends State<SignUpScreen> {
  // The form key runs every validator before a network request.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // These controllers hold only the values typed on this visible screen.
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmationController = TextEditingController();

  // True prevents duplicate account requests while Supabase responds.
  bool _isLoading = false;

  // Validate, create the account, and enter the Student application.
  Future<void> _signUp() async {
    // Stop immediately if one visible input is invalid.
    if (!_formKey.currentState!.validate()) return;

    // Close the keyboard so progress and messages remain visible.
    FocusScope.of(context).unfocus();

    // Show progress using this page's ordinary local state.
    setState(() => _isLoading = true);

    // Read the one plain AuthService shared by every application page.
    final auth = AuthService.instance;

    // Supabase receives only the clean name, LIMU email, and chosen password.
    final message = await auth.signUp(
      _nameController.text,
      _emailController.text,
      _passwordController.text,
    );

    // Do not call setState after navigation removed this page.
    if (!mounted) return;

    // Hide progress after Auth and profile setup both finish.
    setState(() => _isLoading = false);

    // A returned String is safe, short account feedback.
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    // Confirmation-enabled Supabase projects cannot sign in immediately.
    if (auth.requiresEmailConfirmation) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.login,
        (_) => false,
        arguments:
            auth.lastMessage ??
            'Account created. Check your LIMU email, then sign in.',
      );
      return;
    }

    // A successful response must contain a verified active Student profile.
    final user = auth.currentUser;
    if (user == null || user.role != AppUser.studentRole) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The Student account session could not be loaded.'),
        ),
      );
      return;
    }

    // Remove public forms and open the complete Student experience.
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.studentShell,
      (_) => false,
    );
  }

  // Release all native text resources when Flutter removes the form.
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  // Build one compact signup form inside the shared phone-safe shell.
  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      title: 'Create Student account',
      subtitle: 'Use your official LIMU email. You will continue after signup.',
      icon: Icons.person_add_alt_1_rounded,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The profile shows this clean full name to other students.
              AppFormField(
                label: 'Full name',
                controller: _nameController,
                hintText: 'Your full name',
                prefixIcon: Icons.badge_outlined,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: (value) {
                  // Match the exact normalization used by AuthService.
                  if (normalizedRegistrationFullName(value) == null) {
                    return 'Use a full name between 2 and 100 characters.';
                  }
                  return null;
                },
              ),

              // Compact spacing keeps the four-field form calm.
              const SizedBox(height: 12),

              // Only an official university address may register publicly.
              AppFormField(
                label: 'LIMU email',
                controller: _emailController,
                hintText: 'name@limu.edu.ly',
                prefixIcon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Email is required.';
                  }
                  if (!isValidLimuEmail(value.trim().toLowerCase())) {
                    return 'Please use your LIMU email address.';
                  }
                  return null;
                },
              ),

              // Keep the next private input visually separate.
              const SizedBox(height: 12),

              // New accounts use the stronger eight-character password rule.
              AppFormField(
                label: 'Password',
                controller: _passwordController,
                hintText: '8+ characters, with a letter and number',
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) {
                  if (!isValidNewPassword(value)) {
                    return 'Use 8-128 characters with a letter and number.';
                  }
                  return null;
                },
              ),

              // Confirmation catches typing mistakes before account creation.
              const SizedBox(height: 12),
              AppFormField(
                label: 'Confirm password',
                controller: _confirmationController,
                hintText: 'Type the same password again',
                prefixIcon: Icons.lock_reset_rounded,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) {
                  if (!_isLoading) _signUp();
                },
                validator: (value) {
                  if (value != _passwordController.text) {
                    return 'The two passwords must match.';
                  }
                  return null;
                },
              ),

              // The one primary action performs real registration.
              const SizedBox(height: 18),
              AppButton(
                label: 'Create Account',
                onPressed: _signUp,
                isLoading: _isLoading,
              ),

              // Existing users can return without creating route duplicates.
              const SizedBox(height: 4),
              TextButton(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                child: const Text('Already registered? Sign In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
