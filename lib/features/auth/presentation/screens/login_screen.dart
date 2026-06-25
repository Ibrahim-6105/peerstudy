// Login screen for PeerStudy.
// Uses Firebase Auth to sign in an existing user and redirect by role.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/form_field.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  // Creates the form state used by the login screen.
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // Validates the form, signs in, and redirects based on the loaded user role.
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final authNotifier = ref.read(authNotifierProvider.notifier);
    final message = await authNotifier.signIn(
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

    final user = ref.read(currentUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load your account.')),
      );
      return;
    }

    if (user.role == 'student') {
      Navigator.pushReplacementNamed(context, AppRoutes.studentShell);
    } else if (user.role == 'moderator') {
      Navigator.pushReplacementNamed(context, AppRoutes.moderatorDashboard);
    } else if (user.role == 'admin') {
      Navigator.pushReplacementNamed(context, AppRoutes.adminDashboard);
    }
  }

  // Cleans up text controllers when the login screen closes.
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Builds the login form with LIMU email and password fields.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login to PeerStudy')),
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
              const SizedBox(height: 16),
              AppFormField(
                label: 'Password',
                controller: _passwordController,
                hintText: 'Enter your password',
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
                label: 'Sign In',
                onPressed: _login,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.forgotPassword),
                child: const Text('Forgot Password?'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
