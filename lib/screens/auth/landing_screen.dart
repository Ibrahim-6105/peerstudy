// Public landing screen shown before login or signup.
// This is the first real page after the splash screen when no user is signed in.
// It keeps the entry choices simple: login, create student account, or read privacy.

import 'package:flutter/material.dart';
import 'package:peerstudy/components/app_button.dart';
import 'package:peerstudy/routes/app_routes.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  // Builds the first public screen with login, signup, and privacy links.
  // The text is short on purpose so students can immediately choose the action
  // they need instead of reading a long marketing page.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PeerStudy',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              const Text(
                'A learning platform for LIMU students to study, discuss and manage academic content.',
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const Spacer(),
              AppButton(
                label: 'Login',
                onPressed: () => Navigator.pushNamed(context, AppRoutes.login),
              ),
              const SizedBox(height: 12),
              AppButton(
                label: 'Student Sign Up',
                onPressed: () => Navigator.pushNamed(context, AppRoutes.signup),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.privacy),
                child: const Text('Privacy Policy'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
