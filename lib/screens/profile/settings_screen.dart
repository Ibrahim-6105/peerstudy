// Settings screen for simple profile-related links.
// This page is intentionally just a menu right now, because each policy/support
// item is easier to edit as its own small screen.

import 'package:flutter/material.dart';
import 'package:peerstudy/routes/app_routes.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // Builds the profile settings links for policies, support, and app info.
  // ListTile keeps this beginner-friendly: title, arrow icon, and a route tap.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, AppRoutes.privacy),
          ),
          ListTile(
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, AppRoutes.terms),
          ),
          ListTile(
            title: const Text('Contact Support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, AppRoutes.support),
          ),
          ListTile(
            title: const Text('About PeerStudy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, AppRoutes.about),
          ),
        ],
      ),
    );
  }
}
