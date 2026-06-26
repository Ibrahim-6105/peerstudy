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
        backgroundColor: Theme.of(context).colorScheme.secondary,
        minimumSize: const Size.fromHeight(52),
      ),
      child: isLoading
          ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
    );
  }
}
