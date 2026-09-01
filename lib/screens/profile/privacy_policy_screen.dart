// Plain-language product privacy notice.
// University/legal owners must approve the final wording before store release.

import 'package:flutter/material.dart';
import 'package:peerstudy/components/editorial_info_page.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EditorialInfoPage(
      eyebrow: 'Privacy',
      title: 'How PeerStudy handles data',
      intro:
          'PeerStudy uses the minimum account and study activity data needed to provide secure subject workspaces. This implementation notice must be reviewed and approved by LIMU before public release.',
      sections: [
        EditorialInfoSection(
          title: 'Account information',
          body:
              'We process your name, LIMU email address, Supabase user identifier, role, account status, and security timestamps to authenticate you and enforce access.',
        ),
        EditorialInfoSection(
          title: 'Academic activity',
          body:
              'Academic-area, department, and subject selections, quiz results, '
              'Community posts, comments, reports, and administrator '
              'records are stored so the academic community can work safely '
              'and consistently.',
        ),
        EditorialInfoSection(
          title: 'Files and device cache',
          body:
              'Approved lecture PDFs and files attached to Community posts or comments are stored in protected cloud object storage. The app uses short-lived access links and may use temporary device cache while a file is open, but PeerStudy does not keep a permanent saved-material library.',
        ),
        EditorialInfoSection(
          title: 'Service providers',
          body:
              'Supabase Authentication, PostgreSQL, Edge Functions, and private Storage process data on behalf of PeerStudy. The quiz service sends only the selected approved subject material to the configured AI provider through the protected backend.',
        ),
        EditorialInfoSection(
          title: 'Reports and safety',
          body:
              'Report identities are visible only to authorized administrators. Administrators can inspect attachments on reported content. Moderation decisions create protected audit records, while ordinary users do not receive reporter identity.',
        ),
        EditorialInfoSection(
          title: 'Retention and control',
          body:
              'Operational records are retained only for the university-approved period. Users can request access, correction, export, or deletion through support; legal and safety records may require limited retention.',
        ),
        EditorialInfoSection(
          title: 'Security and contact',
          body:
              'PeerStudy uses encrypted connections, authenticated Student and Admin roles, private storage, row-level access policies, and server validation. Use the Support page for privacy questions or account requests.',
        ),
      ],
    );
  }
}
