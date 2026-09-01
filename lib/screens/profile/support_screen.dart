// Support entry points without hard-coding an unverified university address.

import 'package:flutter/material.dart';
import 'package:peerstudy/screens/profile/feedback_screen.dart';
import 'package:peerstudy/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

const String _supportEmail = String.fromEnvironment('SUPPORT_EMAIL');

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: const {'subject': 'PeerStudy support request'},
    );
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email application is available.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: AppTheme.pagePadding,
              children: [
                Text(
                  'How can we help?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'For urgent account restrictions or academic decisions, contact an authorized LIMU administrator.',
                ),
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    minTileHeight: 60,
                    dense: true,
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('View support options'),
                    subtitle: const Text(
                      'See where to report content or request account help.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const FeedbackScreen(),
                      ),
                    ),
                  ),
                ),
                if (_supportEmail.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      minTileHeight: 60,
                      dense: true,
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('Email PeerStudy support'),
                      subtitle: Text(_supportEmail),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: () => _openEmail(context),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Deployment note: set SUPPORT_EMAIL with --dart-define after LIMU confirms the monitored support address.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
