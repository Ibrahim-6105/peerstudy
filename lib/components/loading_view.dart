// Reusable loading component.
// Use this when a page is waiting for startup, network data, or Firebase work so
// users see the same calm loading pattern everywhere.

import 'package:flutter/material.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  // Builds a centered spinner and optional loading message.
  // The message is optional because sometimes the spinner alone is enough for a
  // small area, while full pages benefit from a short explanation.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
