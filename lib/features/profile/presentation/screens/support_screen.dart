// Simple support contact screen for the PeerStudy app.

import 'package:flutter/material.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  // Builds the support contact information screen.
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
