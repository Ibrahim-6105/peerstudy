// Admin dashboard placeholder.
// Admin users land here after login; reports, blocking, and content management
// can be added here as the moderation features are built.

import 'package:flutter/material.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  // Builds the first admin placeholder until moderation tools are added.
  // Keeping a real route now helps role-based navigation work before the full
  // dashboard is implemented.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: const Center(child: Text('Admin dashboard content goes here.')),
    );
  }
}
