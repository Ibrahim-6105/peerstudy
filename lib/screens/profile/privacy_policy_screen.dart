// Static privacy policy screen for PeerStudy.
// This is placeholder copy for now; it gives the app a real route while the
// final university-approved policy text is prepared.

import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  // Builds the static privacy text shown from onboarding and settings.
  // SingleChildScrollView is used so longer policy text can fit later.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            'PeerStudy respects your privacy. We collect only the information needed for academic features and do not share it outside the application.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
