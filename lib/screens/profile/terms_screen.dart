// Plain-language use terms for the academic collaboration app.

import 'package:flutter/material.dart';
import 'package:peerstudy/components/editorial_info_page.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EditorialInfoPage(
      eyebrow: 'Terms',
      title: 'Responsible academic use',
      intro:
          'PeerStudy supplements official LIMU teaching systems. It does not replace registration, attendance, grading, fees, official announcements, or instructor decisions.',
      sections: [
        EditorialInfoSection(
          title: 'Your account',
          body:
              'Use only your own LIMU account, keep your password private, and do not attempt to bypass department, subject, role, or account-status restrictions.',
        ),
        EditorialInfoSection(
          title: 'Academic integrity',
          body:
              'Use shared explanations to learn. Do not submit plagiarism, answer keys for active assessments, impersonation, or misleading material as official content.',
        ),
        EditorialInfoSection(
          title: 'Community conduct',
          body:
              'Be respectful, keep discussion relevant to the selected subject, protect personal information, and follow the Community Guidelines.',
        ),
        EditorialInfoSection(
          title: 'Uploaded content',
          body:
              'Only authorized administrators may publish official subject PDFs. Student Community posts, comments, and private attachments remain peer content subject to validation and review; they are never presented as official material.',
        ),
        EditorialInfoSection(
          title: 'AI quiz limitation',
          body:
              'PeerStudy quizzes are supplementary practice generated from approved subject materials. They are not official assessment or guaranteed academic advice.',
        ),
        EditorialInfoSection(
          title: 'Administrator actions',
          body:
              'Administrators may dismiss reports, remove violating content, or restrict accounts after protected review.',
        ),
      ],
    );
  }
}
