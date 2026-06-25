// Static about screen for the PeerStudy app.
// This gives students a small, friendly summary of the product.

import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // Builds a short explanation of what PeerStudy is meant to support.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About PeerStudy')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            'PeerStudy is a LIMU learning companion for organized study material, peer discussion, and academic collaboration.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
