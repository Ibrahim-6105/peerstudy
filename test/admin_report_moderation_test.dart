import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerstudy/screens/admin/admin_resolution_note_dialog.dart';

void main() {
  group('Admin report resolution dialog', () {
    testWidgets('returns a trimmed note and closes without widget errors', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: _DialogHarness()));

      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        '  Removed because it breaks the guidelines.  ',
      );
      await tester.tap(find.text('Confirm'));

      // Exercise both the first closing frame and the completed route removal.
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      expect(
        find.text('Removed because it breaks the guidelines.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the dialog open for an invalid short note', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: _DialogHarness()));

      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'no');
      await tester.tap(find.text('Confirm'));
      await tester.pump();

      expect(find.text('Remove content for report'), findsOneWidget);
      expect(find.text('No result'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  test('Admin moderation migration preserves safe idempotent contracts', () {
    final migration = File(
      'supabase/migrations/20260902000100_admin_report_delete_safety.sql',
    );
    expect(migration.existsSync(), isTrue);

    final sql = migration.readAsStringSync().toLowerCase();
    expect(
      sql,
      contains(
        "if v_action = 'remove' and v_report.status = 'content_removed' then",
      ),
    );
    expect(
      sql,
      contains("elsif v_target_exists and v_target_status = 'removed' then"),
    );
    expect(sql, contains("v_new_status := 'content_removed'"));
    expect(
      sql,
      contains('if not v_target_exists or v_target_author is null then'),
    );
    expect(
      sql,
      contains(
        'revoke execute on function public.admin_resolve_report(uuid, text, text)',
      ),
    );

    // The parent lock must happen before report status changes so concurrent
    // Comment resolutions cannot publish a stale is_reported value.
    final parentLock =
        RegExp(
          r'perform\s+1\s+from public[.]community_posts p\s+'
          r'where p[.]id = v_post_id\s+for update;',
        ).firstMatch(sql)?.start ??
        -1;
    final reportUpdate =
        RegExp(
          r'update public[.]reports\s+set status = v_new_status',
        ).firstMatch(sql)?.start ??
        -1;
    expect(parentLock, greaterThanOrEqualTo(0));
    expect(reportUpdate, greaterThan(parentLock));
  });

  test('restricting a Student removes all of their Community content', () {
    final migration = File(
      'supabase/migrations/20260905000100_remove_restricted_user_content.sql',
    );
    expect(migration.existsSync(), isTrue);

    final sql = migration.readAsStringSync().toLowerCase();
    expect(
      sql,
      contains("if new.role = 'student' and new.status = 'restricted' then"),
    );
    expect(sql, contains('update public.community_comments'));
    expect(sql, contains('update public.community_posts'));
    expect(sql, contains("removal_reason = 'author account was restricted'"));
    expect(sql, contains("and status = 'active'"));
    expect(sql, contains('after update of status on public.profiles'));
    expect(
      sql,
      contains(
        'revoke execute on function public.remove_restricted_student_content()',
      ),
    );

    // Existing restricted accounts must receive the same cleanup during deploy.
    expect(RegExp(r"p[.]status = 'restricted'").allMatches(sql).length, 2);
  });
}

class _DialogHarness extends StatefulWidget {
  const _DialogHarness();

  @override
  State<_DialogHarness> createState() => _DialogHarnessState();
}

class _DialogHarnessState extends State<_DialogHarness> {
  String? _result;

  Future<void> _openDialog() async {
    final result = await showAdminResolutionNoteDialog(
      context,
      actionLabel: 'Remove content for',
    );
    if (!mounted || result == null) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          FilledButton(
            onPressed: _openDialog,
            child: const Text('Open dialog'),
          ),
          Text(_result ?? 'No result'),
        ],
      ),
    );
  }
}
