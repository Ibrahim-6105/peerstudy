// Reusable compact text field used by all authentication forms.
// Keeping this small widget in one file makes labels and password controls
// consistent while every screen still uses ordinary controllers and setState.

// Material supplies TextFormField, icons, and the local StatefulWidget.
import 'package:flutter/material.dart';

// AppFormField is stateful only so its eye button can show or hide a password.
class AppFormField extends StatefulWidget {
  // Every field needs a label; all other behavior is optional and simple.
  const AppFormField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.prefixIcon,
    this.obscureText = false,
    this.validator,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.onFieldSubmitted,
  });

  // The short label appears directly above the field.
  final String label;

  // A screen-owned controller reads and clears the value.
  final TextEditingController? controller;

  // The hint shows a brief example while the field is empty.
  final String? hintText;

  // The keyboard can be optimized for email, names, or ordinary text.
  final TextInputType? keyboardType;

  // This tells the phone which keyboard action appears in the bottom corner.
  final TextInputAction? textInputAction;

  // A small leading icon makes longer forms easier to scan.
  final IconData? prefixIcon;

  // True hides private text and adds a show/hide eye button.
  final bool obscureText;

  // The owning form supplies its own beginner-friendly validation rule.
  final String? Function(String?)? validator;

  // Autofill hints let the operating system fill known values safely.
  final Iterable<String>? autofillHints;

  // Names may start each word with a capital letter automatically.
  final TextCapitalization textCapitalization;

  // Login can submit when the user presses Done on the password keyboard.
  final ValueChanged<String>? onFieldSubmitted;

  // Create the tiny state that owns only password visibility.
  @override
  State<AppFormField> createState() => _AppFormFieldState();
}

// This state never stores form data; the screen's controller still owns that.
class _AppFormFieldState extends State<AppFormField> {
  // Password fields begin hidden for privacy.
  late bool _hideText;

  // Read the initial visibility once when Flutter creates the field.
  @override
  void initState() {
    super.initState();
    _hideText = widget.obscureText;
  }

  // Keep visibility correct if a test rebuilds this widget with a new type.
  @override
  void didUpdateWidget(covariant AppFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      _hideText = widget.obscureText;
    }
  }

  // Build one label and one compact Material input.
  @override
  Widget build(BuildContext context) {
    // The theme supplies light/dark text and blue focus colors automatically.
    final theme = Theme.of(context);

    // Column keeps the short label close to its input.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A medium-weight small label is readable without dominating the page.
        Text(
          widget.label,
          style: theme.textTheme.labelLarge?.copyWith(fontSize: 12.5),
        ),

        // Six pixels clearly connects the label to its field.
        const SizedBox(height: 6),

        // TextFormField works with the parent Form's normal validator call.
        TextFormField(
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          obscureText: widget.obscureText && _hideText,
          validator: widget.validator,
          autofillHints: widget.autofillHints,
          textCapitalization: widget.textCapitalization,
          onFieldSubmitted: widget.onFieldSubmitted,
          autocorrect: !widget.obscureText,
          enableSuggestions: !widget.obscureText,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: widget.prefixIcon == null
                ? null
                : Icon(widget.prefixIcon, size: 19),
            prefixIconConstraints: const BoxConstraints(minWidth: 42),
            suffixIcon: widget.obscureText
                ? IconButton(
                    tooltip: _hideText ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _hideText = !_hideText),
                    icon: Icon(
                      _hideText
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 19,
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(minWidth: 42),
          ),
        ),
      ],
    );
  }
}
