// Static about screen for PeerStudy.
// It gives students a short explanation of the finished system.

import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // Builds a short explanation of what PeerStudy supports.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About PeerStudy')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: const SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Text(
                'PeerStudy is a LIMU learning companion for approved subject PDFs, text-based subject Communities, and ten-question practice quizzes generated from one selected approved material. Students use their LIMU accounts, while authorized administrators manage academic content, materials, reports, and account access.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
