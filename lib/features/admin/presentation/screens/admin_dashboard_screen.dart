// Placeholder admin dashboard screen.
// This screen is shown to admin users after login.

import 'package:flutter/material.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  // Builds the first admin placeholder until moderation tools are added.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: const Center(child: Text('Admin dashboard content goes here.')),
    );
  }
}
