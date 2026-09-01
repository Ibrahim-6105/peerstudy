// Explains the two real support paths available in the corrected application.
//
// Beginner note:
// The corrected database has no feedback table, so this screen does not pretend
// a form was stored. Content problems use the Community report action; general
// app help opens the existing Contact Support page.

import 'package:flutter/material.dart';
import 'package:peerstudy/routes/app_routes.dart';
import 'package:peerstudy/theme/app_theme.dart';

class FeedbackScreen extends StatelessWidget {
  const FeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback and Support')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTheme.contentWidth),
            child: ListView(
              padding: AppTheme.pagePadding,
              children: [
                Text(
                  'How can we help?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose the path that matches the problem. Never include a '
                  'password or another person\'s private information.',
                ),
                const SizedBox(height: 14),
                const _HelpCard(
                  icon: Icons.flag_outlined,
                  title: 'Community content problem',
                  description:
                      'Open the Post or Comment menu in its Subject Community and '
                      'choose Report. An Admin can then review the exact content.',
                ),
                const SizedBox(height: 8),
                _HelpCard(
                  icon: Icons.support_agent_outlined,
                  title: 'Account or app problem',
                  description:
                      'Use Contact Support for login, restriction, accessibility, '
                      'or technical help.',
                  actionLabel: 'Open Contact Support',
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.support);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// A reusable card keeps the support explanation short and phone-friendly.
class _HelpCard extends StatelessWidget {
  const _HelpCard({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description),
            if (actionLabel != null && onPressed != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
