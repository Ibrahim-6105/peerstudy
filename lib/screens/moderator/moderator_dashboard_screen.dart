// Moderator dashboard placeholder.
// Academic moderators land here after login; lecture uploads and discussion
// guidance tools can be added here later.

import 'package:flutter/material.dart';

class ModeratorDashboardScreen extends StatelessWidget {
  const ModeratorDashboardScreen({super.key});

  // Builds the first moderator placeholder until lecture tools are added.
  // This keeps moderator routing separate from admin routing from the beginning.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moderator Dashboard')),
      body: const Center(child: Text('Moderator dashboard content goes here.')),
    );
  }
}
