// Static privacy policy screen for the PeerStudy app.

import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  // Builds the static privacy text shown from onboarding and settings.
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
