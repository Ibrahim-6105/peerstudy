// Shared compact page layout for Login, Sign Up, and password recovery.
//
// Beginner note:
// Each authentication screen still owns its normal Form and setState values.
// This widget only prevents repeated SafeArea, scrolling, width, and header code.

// Material supplies the standard page, layout, icon, and card widgets.
import 'package:flutter/material.dart';

// AuthPageShell keeps every public account form calm and phone-safe.
class AuthPageShell extends StatelessWidget {
  // The form screen supplies its own words, icon, and child Form.
  const AuthPageShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.icon = Icons.person_outline_rounded,
    this.showBackButton = true,
  });

  // The page title states the single current task.
  final String title;

  // The subtitle gives only the short information needed before the form.
  final String subtitle;

  // The screen-owned form is inserted below the heading.
  final Widget child;

  // A small icon helps distinguish login, signup, and recovery.
  final IconData icon;

  // Login is the first page and therefore does not show a useless back arrow.
  final bool showBackButton;

  // Build a safe, scrollable page for small phones and visible keyboards.
  @override
  Widget build(BuildContext context) {
    // Read colors from the active light or dark theme.
    final colors = Theme.of(context).colorScheme;

    // Scaffold uses the requested white or dark page background.
    return Scaffold(
      // SafeArea keeps every form below notches and above system navigation.
      body: SafeArea(
        // Tapping outside a field closes the keyboard naturally.
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          // LayoutBuilder gives the scroll content the visible phone height.
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Scrolling is a fallback when the keyboard reduces free space.
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                // Keep short forms vertically comfortable on taller phones.
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 28,
                  ),
                  // Column places the brand header above the centered form.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The small header is consistent on every auth page.
                      _AuthHeader(showBackButton: showBackButton),

                      // Flexible empty space prevents the form hugging the top.
                      const SizedBox(height: 14),

                      // Center keeps a compact form readable on a tablet.
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          // One subtle container separates form from background.
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colors.outline),
                            ),
                            // Form heading and the supplied child stay together.
                            child: _FormContent(
                              title: title,
                              subtitle: subtitle,
                              icon: icon,
                              child: child,
                            ),
                          ),
                        ),
                      ),

                      // A final gap keeps content away from the system bar.
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// This small brand header appears above every public account form.
class _AuthHeader extends StatelessWidget {
  // Login hides Back; nested forms use it to return to the previous page.
  const _AuthHeader({required this.showBackButton});

  // True enables the normal Navigator back action.
  final bool showBackButton;

  // Build one 42-pixel-tall header row.
  @override
  Widget build(BuildContext context) {
    // Read the current blue and white/dark surface values.
    final colors = Theme.of(context).colorScheme;

    // SizedBox keeps every form aligned whether Back is visible or hidden.
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          // Show a useful back control only on a page that can return.
          if (showBackButton)
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 21),
            )
          else
            const SizedBox(width: 40),

          // Center the compact PeerStudy identity in the available row.
          const Spacer(),

          // The small blue tile uses the exact brand color from the theme.
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.school_rounded,
              color: colors.onPrimary,
              size: 17,
            ),
          ),

          // Keep the icon and product name visually grouped.
          const SizedBox(width: 8),

          // The brand is intentionally smaller than the form's task title.
          Text('PeerStudy', style: Theme.of(context).textTheme.titleSmall),

          // Mirror the left control so the brand remains centered.
          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

// _FormContent draws the icon, title, subtitle, and caller-owned Form.
class _FormContent extends StatelessWidget {
  // All values come directly from AuthPageShell.
  const _FormContent({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  // These fields are visual text/icon values only.
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  // Build the calm top section above the form fields.
  @override
  Widget build(BuildContext context) {
    // Theme automatically switches text and container colors in dark mode.
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // Column keeps all form content left-aligned and easy to scan.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The 30-pixel icon is recognizable without dominating the form.
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: colors.primary, size: 16),
        ),

        // Keep title close to its task icon.
        const SizedBox(height: 11),

        // The compact shared text theme supplies a calm 19-pixel heading.
        Text(title, style: theme.textTheme.headlineSmall),

        // Subtitle remains secondary and concise.
        const SizedBox(height: 5),
        Text(subtitle, style: theme.textTheme.bodyMedium),

        // Separate instructions from interactive controls.
        const SizedBox(height: 16),

        // Insert the normal screen-owned Form here.
        child,
      ],
    );
  }
}
