import 'package:flutter/material.dart';

// Show the required Admin audit-note prompt and return only a valid note.
Future<String?> showAdminResolutionNoteDialog(
  BuildContext context, {
  required String actionLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) =>
        _AdminResolutionNoteDialog(actionLabel: actionLabel),
  );
}

// The dialog owns its controller for its complete route/animation lifetime.
// This avoids disposing a controller immediately when Navigator.pop completes
// while Flutter may still be painting the closing dialog for another frame.
class _AdminResolutionNoteDialog extends StatefulWidget {
  const _AdminResolutionNoteDialog({required this.actionLabel});

  final String actionLabel;

  @override
  State<_AdminResolutionNoteDialog> createState() =>
      _AdminResolutionNoteDialogState();
}

class _AdminResolutionNoteDialogState
    extends State<_AdminResolutionNoteDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final note = _controller.text.trim();
    if (note.length < 5) return;
    Navigator.pop(context, note);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.actionLabel} report'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        maxLength: 500,
        decoration: const InputDecoration(
          labelText: 'Resolution note',
          hintText: 'Explain the Admin decision',
          alignLabelWithHint: true,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('Confirm')),
      ],
    );
  }
}
