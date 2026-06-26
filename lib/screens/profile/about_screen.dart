// Static about screen for PeerStudy.
// It gives students a short explanation of why the app exists before the fuller
// academic features are implemented.

import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // Builds a short explanation of what PeerStudy is meant to support.
  // This is useful for settings, onboarding, and quick project demos.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About PeerStudy')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            'PeerStudy is a LIMU learning companion for organized study material, peer discussion, and academic collaboration.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
