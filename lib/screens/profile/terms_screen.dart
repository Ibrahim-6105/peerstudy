// Static terms of service screen for PeerStudy.
// This page explains responsible academic use and can later be expanded with the
// final community rules from the project team.

import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  // Builds the simple terms text for responsible academic use.
  // The layout already scrolls, so adding more rules later will not break small
  // phone screens.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Service')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            'Using PeerStudy means you agree to the academic community guidelines and respect other students by using the platform responsibly.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
