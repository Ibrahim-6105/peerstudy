// Shows the signed-in student's Supabase account facts.
//
// Beginner note:
// Authentication owns the email address and the `profiles` table owns the
// role/status. This screen only reads those trusted values. It never invents
// demo account data and it never stores a password.

import 'package:flutter/material.dart';
import 'package:peerstudy/models/app_user.dart';
import 'package:peerstudy/services/auth_service.dart';
import 'package:peerstudy/theme/app_theme.dart';

class StudentAccountScreen extends StatefulWidget {
  const StudentAccountScreen({super.key, this.user});

  // Widget tests may supply a known user without opening a cloud session.
  final AppUser? user;

  @override
  State<StudentAccountScreen> createState() {
    return _StudentAccountScreenState();
  }
}

class _StudentAccountScreenState extends State<StudentAccountScreen> {
  // This flag prevents two password emails from being requested at once.
  bool _isSendingPasswordEmail = false;

  @override
  void initState() {
    super.initState();

    // Refresh the server profile once, then update this ordinary State object.
    if (widget.user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Keep the already loaded account visible during a temporary outage.
        try {
          await AuthService.instance.refreshCurrentUser();
        } catch (_) {
          // The Account screen remains usable with its last verified snapshot.
        }
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user ?? AuthService.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTheme.contentWidth),
            child: ListView(
              padding: AppTheme.pagePadding,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Text(
                  'Your PeerStudy account',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'These values come from your current Supabase session and '
                  'server profile.',
                ),
                const SizedBox(height: 14),
                if (user == null)
                  const _AccountUnavailableCard()
                else ...[
                  _AccountDetailsCard(user: user),
                  const SizedBox(height: 10),
                  _PasswordCard(
                    isSending: _isSendingPasswordEmail,
                    onSend: () => _sendPasswordReset(user.email),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Supabase sends a short-lived recovery link to the signed-in LIMU email.
  Future<void> _sendPasswordReset(String email) async {
    if (_isSendingPasswordEmail) return;
    setState(() => _isSendingPasswordEmail = true);

    // The same small auth service used by Login sends the secure email.
    final error = await AuthService.instance.sendPasswordResetEmail(email);
    if (!mounted) return;

    // A null result means Supabase accepted the privacy-safe request.
    if (error == null) {
      _showMessage('Password reset instructions were sent to $email.');
    } else {
      _showMessage(error, isError: true);
    }

    // Re-enable the button after either result.
    setState(() => _isSendingPasswordEmail = false);
  }

  // Snack bars give one clear result without exposing backend exceptions.
  void _showMessage(String message, {bool isError = false}) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colors.error : null,
      ),
    );
  }
}

// One card keeps email, role, and status easy to scan on a phone.
class _AccountDetailsCard extends StatelessWidget {
  const _AccountDetailsCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _AccountRow(
              icon: Icons.person_outline,
              label: 'Full name',
              value: user.fullName,
            ),
            const Divider(height: 22),
            _AccountRow(
              icon: Icons.email_outlined,
              label: 'LIMU email',
              value: user.email,
            ),
            const Divider(height: 22),
            _AccountRow(
              icon: Icons.badge_outlined,
              label: 'Role',
              value: _titleCase(user.role),
            ),
            const Divider(height: 22),
            _AccountRow(
              icon: Icons.shield_outlined,
              label: 'Account status',
              value: user.accountStatusLabel,
            ),
          ],
        ),
      ),
    );
  }
}

// Each account row uses the same simple label/value layout.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 3),
              SelectableText(value),
            ],
          ),
        ),
      ],
    );
  }
}

// Password changes start through the reviewed recovery email flow.
class _PasswordCard extends StatelessWidget {
  const _PasswordCard({required this.isSending, required this.onSend});

  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Password', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'For security, PeerStudy sends a password-reset link to your '
              'LIMU email. The app never reads your current password.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: isSending ? null : onSend,
                icon: isSending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_reset_outlined),
                label: Text(
                  isSending ? 'Sending...' : 'Send password reset email',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// A missing service value means the protected session is no longer usable.
class _AccountUnavailableCard extends StatelessWidget {
  const _AccountUnavailableCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          'Account details are unavailable. Return to Login and sign in again.',
        ),
      ),
    );
  }
}

// Role strings are stored lowercase in PostgreSQL and displayed normally here.
String _titleCase(String value) {
  if (value.isEmpty) return 'Unknown';
  return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
}
