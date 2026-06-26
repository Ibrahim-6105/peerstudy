// Support contact screen for PeerStudy.
// This page gives users a clear place to look when they need help with account
// access, content, or academic moderation.

import 'package:flutter/material.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  // Builds the support contact information screen.
  // The contact text is hard-coded for now and can be replaced by real support
  // details when the university process is confirmed.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Support')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'For help with PeerStudy, email support@limu.edu.ly or contact your academic moderator directly.',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
