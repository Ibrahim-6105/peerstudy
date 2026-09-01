// This page opens after a valid Supabase password-recovery deep link.
// It uses a normal StatefulWidget and setState for one loading value.

// Material supplies Form, icons, SnackBar, and navigation widgets.
import 'package:flutter/material.dart';

// AppButton displays compact progress during the secure password update.
import 'package:peerstudy/components/app_button.dart';

// AppFormField supplies matching private fields and show/hide controls.
import 'package:peerstudy/components/app_form_field.dart';

// AuthPageShell provides the shared SafeArea and keyboard-safe scrolling.
import 'package:peerstudy/components/auth_page_shell.dart';

// AppRoutes supplies the clean Login destination after recovery.
import 'package:peerstudy/routes/app_routes.dart';

// AuthService updates the password inside the real recovery session.
import 'package:peerstudy/services/auth_service.dart';

// The strong validator matches new Student account passwords.
import 'package:peerstudy/utils/validators.dart';

// ResetPasswordScreen receives its secure session through the Supabase SDK.
class ResetPasswordScreen extends StatefulWidget {
  // No token is passed in an unsafe route argument.
  const ResetPasswordScreen({super.key});

  // Create the normal two-field form state.
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

// This state owns only its controllers and loading spinner.
class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  // The form key runs both validators together.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // These controllers hold the new password and its confirmation temporarily.
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmationController = TextEditingController();

  // True blocks duplicate update requests.
  bool _isLoading = false;

  // Validate both values and finish the recovery session.
  Future<void> _updatePassword() async {
    // Stop before networking when a visible validator reports a problem.
    if (!_formKey.currentState!.validate()) return;

    // Close the keyboard and show local progress.
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    // AuthService updates Supabase then clears recovery and login markers.
    final message = await AuthService.instance.updateRecoveredPassword(
      _passwordController.text,
    );

    // Do not update state after navigation removed the page.
    if (!mounted) return;

    // Hide progress after Supabase answers.
    setState(() => _isLoading = false);

    // Keep an expired or invalid recovery link on this page with feedback.
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    // Return to a clean Login route after the successful password change.
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (_) => false,
      arguments: 'Password updated. Sign in with your new password.',
    );
  }

  // Release native text resources when the route closes.
  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  // Build a quiet two-field recovery form inside the shared SafeArea shell.
  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      title: 'Choose a new password',
      subtitle: 'Use 8-128 characters with at least one letter and one number.',
      icon: Icons.lock_reset_rounded,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The first private field reads the requested new password.
              AppFormField(
                label: 'New password',
                controller: _passwordController,
                hintText: 'Enter your new password',
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

              // Confirmation catches typing differences locally.
              const SizedBox(height: 12),
              AppFormField(
                label: 'Confirm new password',
                controller: _confirmationController,
                hintText: 'Type the same password again',
                prefixIcon: Icons.lock_reset_rounded,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) {
                  if (!_isLoading) _updatePassword();
                },
                validator: (value) {
                  if (value != _passwordController.text) {
                    return 'The two passwords must match.';
                  }
                  return null;
                },
              ),

              // The single primary action performs the secure SDK update.
              const SizedBox(height: 18),
              AppButton(
                label: 'Update Password',
                onPressed: _updatePassword,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
