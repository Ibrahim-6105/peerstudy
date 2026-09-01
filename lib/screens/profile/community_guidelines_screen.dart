// Community rules displayed from profile, settings, and report workflows.

import 'package:flutter/material.dart';
import 'package:peerstudy/components/editorial_info_page.dart';

class CommunityGuidelinesScreen extends StatelessWidget {
  const CommunityGuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EditorialInfoPage(
      eyebrow: 'Community',
      title: 'PeerStudy Community Guidelines',
      intro:
          'Every workspace belongs to one subject. Helpful, sourced, respectful discussion keeps the history useful for everyone who studies later.',
      sections: [
        EditorialInfoSection(
          title: 'Stay on subject',
          body:
              'Publish posts and comments only in the subject Community where '
              'they belong. The Community is a post-and-comment feed, not '
              'direct student-to-student messaging.',
        ),
        EditorialInfoSection(
          title: 'Be respectful',
          body:
              'Do not harass, threaten, shame, discriminate against, or impersonate another person.',
        ),
        EditorialInfoSection(
          title: 'Protect privacy',
          body:
              'Do not publish passwords, private contact details, confidential university records, or another person’s personal information.',
        ),
        EditorialInfoSection(
          title: 'Share responsibly',
          body:
              'Use accurate titles, explain sources, respect copyright, and never present a peer attachment as official material. Do not upload malware, executable files, unsafe documents, or files unrelated to the Subject.',
        ),
        EditorialInfoSection(
          title: 'Report privately',
          body:
              'Report misleading, inappropriate, unsafe, or unrelated content with a clear reason. Reporter identity remains private from ordinary users.',
        ),
        EditorialInfoSection(
          title: 'Administrator review',
          body:
              'Authorized administrators review private reports and may dismiss a report, remove violating content, or restrict an account.',
        ),
      ],
    );
  }
}
