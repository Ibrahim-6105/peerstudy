// Placeholder moderator dashboard screen.
// This screen is shown to academic moderators after login.

import 'package:flutter/material.dart';

class ModeratorDashboardScreen extends StatelessWidget {
  const ModeratorDashboardScreen({super.key});

  // Builds the first moderator placeholder until lecture tools are added.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moderator Dashboard')),
      body: const Center(child: Text('Moderator dashboard content goes here.')),
    );
  }
}
