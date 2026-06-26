// Password reset screen for PeerStudy.
// The user enters a LIMU email and Firebase sends the reset link when the app is
// configured with a real Firebase project.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerstudy/components/app_button.dart';
import 'package:peerstudy/components/app_form_field.dart';
import 'package:peerstudy/providers/auth_provider.dart';
import 'package:peerstudy/utils/validators.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  // Creates the form state used by the reset password screen.
  // ConsumerState is used so the screen can call the auth provider.
  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  // Sends a Firebase password reset email after validating the LIMU address.
  // The mounted check after await keeps SnackBars from running if the user left
  // the screen while Firebase was responding.
  Future<void> _sendReset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final authNotifier = ref.read(authNotifierProvider.notifier);
    final message = await authNotifier.sendPasswordResetEmail(
      _emailController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message ?? 'Password reset email sent.')),
    );
  }

  // Cleans up the email controller when the reset screen closes.
  // It is a small habit, but it keeps every form screen safe and predictable.
  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // Builds the password reset form for a LIMU email address.
  // The form stays intentionally short because password recovery should be quick.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              AppFormField(
                label: 'LIMU Email',
                controller: _emailController,
                hintText: 'name@limu.edu.ly',
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Email is required.';
                  }
                  if (!isValidLimuEmail(value.trim())) {
                    return 'Please use your LIMU email address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              AppButton(
                label: 'Send Reset Email',
                onPressed: _sendReset,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
