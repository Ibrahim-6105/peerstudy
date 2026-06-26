// Student signup screen for PeerStudy.
// Public registration only creates student accounts; admin and moderator users
// should be prepared separately so platform roles stay controlled.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerstudy/components/app_button.dart';
import 'package:peerstudy/components/app_form_field.dart';
import 'package:peerstudy/providers/auth_provider.dart';
import 'package:peerstudy/routes/app_routes.dart';
import 'package:peerstudy/utils/validators.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  // Creates the form state used by the signup screen.
  // ConsumerState is used because account creation goes through Riverpod auth.
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
  // The provider handles Firebase work; this screen only manages form input,
  // loading state, and navigation.
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
  // This keeps form screens tidy when the user goes back and forth.
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Builds the student signup form with the required LIMU fields.
  // The LIMU email validator is important because the product is scoped to the
  // university community.
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
