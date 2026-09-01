import 'package:flutter/material.dart';

class EditorialInfoSection {
  const EditorialInfoSection({required this.title, required this.body});

  final String title;
  final String body;
}

class EditorialInfoPage extends StatelessWidget {
  const EditorialInfoPage({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.intro,
    required this.sections,
  });

  final String eyebrow;
  final String title;
  final String intro;
  final List<EditorialInfoSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: theme.dividerColor),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Text(eyebrow.toUpperCase(), style: theme.textTheme.labelSmall),
                const SizedBox(height: 6),
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(intro, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                Divider(height: 1, color: theme.dividerColor),
                for (var index = 0; index < sections.length; index++)
                  _InfoRow(index: index + 1, section: sections[index]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.index, required this.section});

  final int index;
  final EditorialInfoSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              index.toString().padLeft(2, '0'),
              style: theme.textTheme.labelMedium,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(section.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(section.body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
