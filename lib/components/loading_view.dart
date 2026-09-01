// Reusable loading component.
// Use this when a page is waiting for startup, network data, or backend work so
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
    // SafeArea also makes this component safe when it is used as a full page.
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A compact spinner feels calmer than a large loading illustration.
            const SizedBox.square(
              dimension: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(message!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
