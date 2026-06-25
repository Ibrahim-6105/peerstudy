// Screen for sending a password reset email through Firebase Auth.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/form_field.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  // Creates the form state used by the reset password screen.
  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  // Sends a Firebase password reset email after validating the LIMU address.
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
  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // Builds the password reset form for a LIMU email address.
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
