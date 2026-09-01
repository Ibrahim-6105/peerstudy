// This page asks Supabase to email a secure password-recovery link.
// One StatefulWidget and setState are enough for its loading spinner.

// Material supplies Form, icons, SnackBar, and text input behavior.
import 'package:flutter/material.dart';

// AppButton shows compact progress during the real email request.
import 'package:peerstudy/components/app_button.dart';

// AppFormField keeps this email control consistent with Login.
import 'package:peerstudy/components/app_form_field.dart';

// AuthPageShell guarantees SafeArea and responsive keyboard scrolling.
import 'package:peerstudy/components/auth_page_shell.dart';

// AuthService sends the recovery request through real Supabase Auth.
import 'package:peerstudy/services/auth_service.dart';

// The LIMU validator rejects malformed public email requests locally.
import 'package:peerstudy/utils/validators.dart';

// ForgotPasswordScreen needs no external values.
class ForgotPasswordScreen extends StatefulWidget {
  // A const constructor keeps the small route efficient.
  const ForgotPasswordScreen({super.key});

  // Create the screen's local form state.
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

// This state owns only one controller and one loading boolean.
class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // The form key validates email before a network call.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // This controller reads the official university email.
  final TextEditingController _emailController = TextEditingController();

  // True prevents repeated email requests while Supabase responds.
  bool _isLoading = false;

  // Validate the email and request a secure recovery link.
  Future<void> _sendReset() async {
    // Do not send an invalid visible value.
    if (!_formKey.currentState!.validate()) return;

    // Close the keyboard and show local progress.
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    // AuthService applies privacy-safe wording for known and unknown accounts.
    final error = await AuthService.instance.sendPasswordResetEmail(
      _emailController.text.trim(),
    );

    // Stop if navigation already removed the screen.
    if (!mounted) return;

    // Hide the spinner when the request finishes.
    setState(() => _isLoading = false);

    // Success never reveals whether a particular address exists.
    final message =
        error ??
        'If that LIMU account exists, a password reset email was sent.';

    // Keep the result visible on this simple form.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // Release the native text controller with the screen.
  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // Build one quiet recovery form inside the shared SafeArea shell.
  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      title: 'Reset password',
      subtitle: 'We will email a secure reset link to your LIMU address.',
      icon: Icons.mark_email_read_outlined,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Recovery needs only one official university email.
            AppFormField(
              label: 'LIMU email',
              controller: _emailController,
              hintText: 'name@limu.edu.ly',
              prefixIcon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onFieldSubmitted: (_) {
                if (!_isLoading) _sendReset();
              },
              validator: (value) {
                // Empty input receives the shortest useful instruction.
                if (value == null || value.trim().isEmpty) {
                  return 'Email is required.';
                }

                // Only official LIMU addresses belong to this application.
                if (!isValidLimuEmail(value.trim().toLowerCase())) {
                  return 'Please use your LIMU email address.';
                }

                // Null tells Flutter the field passed validation.
                return null;
              },
            ),

            // The single action stays visually close to its only input.
            const SizedBox(height: 18),
            AppButton(
              label: 'Send Reset Email',
              onPressed: _sendReset,
              isLoading: _isLoading,
            ),
          ],
        ),
      ),
    );
  }
}
