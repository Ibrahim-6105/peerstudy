// Reusable button component for PeerStudy.
// Use this instead of creating a new ElevatedButton every time, because it keeps
// button height, loading behavior, and text style consistent across screens.

import 'package:flutter/material.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isLoading;

  // Builds a full-width action button with an optional loading spinner.
  // When isLoading is true, the button disables taps so the user cannot submit
  // the same form twice by accident.
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        // Forty-six pixels remains easy to tap without making forms look loud.
        minimumSize: const Size.fromHeight(46),
      ),
      child: isLoading
          ? SizedBox(
              height: 19,
              width: 19,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                // Match the correct foreground in both light and dark themes.
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : Text(
              label,
              // The shared theme supplies the calm 14-pixel button size.
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
    );
  }
}
