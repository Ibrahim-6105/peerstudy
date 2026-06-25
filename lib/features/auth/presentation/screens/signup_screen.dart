// Student signup screen for PeerStudy.
// Creates Firebase Auth user and Firestore profile with student role.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/form_field.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  // Creates the form state used by the signup screen.
  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // Validates student details, creates the account, and opens the student area.
  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final authNotifier = ref.read(authNotifierProvider.notifier);
    final message = await authNotifier.signUp(
      _nameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    Navigator.pushReplacementNamed(context, AppRoutes.studentShell);
  }

  // Cleans up text controllers when the signup screen closes.
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Builds the student signup form with the required LIMU fields.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Student Account')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              AppFormField(
                label: 'Full Name',
                controller: _nameController,
                hintText: 'Your full name',
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Full name is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
              AppFormField(
                label: 'Password',
                controller: _passwordController,
                hintText: 'Enter secure password',
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required.';
                  }
                  if (!isValidPassword(value)) {
                    return 'Password must be at least 6 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Create Account',
                onPressed: _signup,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.login),
                child: const Text('Already have an account? Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
