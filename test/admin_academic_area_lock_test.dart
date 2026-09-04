import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Admin Academic Area is a fixed Engineering and IT dropdown', () {
    final dashboard = File(
      'lib/screens/admin/admin_dashboard_screen.dart',
    ).readAsStringSync();
    final areaWidget = _section(
      dashboard,
      'class _AcademicAreaDropdownCard',
      '// _CatalogSelectorCard',
    );
    final academicContent = _section(
      dashboard,
      'class _AcademicContentTabState',
      '// _ReportsTab',
    );

    expect(
      dashboard,
      contains("<String>{'ENGINEERING', 'IT'}"),
      reason: 'Only the two release Academic Area codes may be listed.',
    );
    expect(academicContent, contains(".eq('name', peerStudySchoolName)"));
    expect(
      academicContent,
      contains("row['school_id']?.toString() == schoolId"),
    );
    expect(areaWidget, contains('DropdownButtonFormField<String>'));
    expect(areaWidget, contains("? 'Engineering' : 'IT'"));
    expect(areaWidget, isNot(contains('IconButton(')));
    expect(areaWidget, isNot(contains('onAdd')));
    expect(areaWidget, isNot(contains('onEdit')));
    expect(areaWidget, isNot(contains('onDelete')));

    expect(academicContent, contains('_AcademicAreaDropdownCard('));
    expect(academicContent, isNot(contains('_editArea')));
    expect(academicContent, isNot(contains('AcademicAreaForm')));
    expect(academicContent, isNot(contains("table: 'academic_areas'")));
    expect(academicContent, isNot(contains('_deleteCatalogRow')));
    expect(academicContent, contains('_deleteDepartment'));
  });

  test('obsolete Academic Area add and edit form no longer exists', () {
    final forms = File(
      'lib/screens/admin/admin_form_pages.dart',
    ).readAsStringSync();

    expect(forms, isNot(contains('AcademicAreaFormValue')));
    expect(forms, isNot(contains('AcademicAreaFormPage')));
    expect(forms, contains('DepartmentFormPage'));
    expect(forms, contains('SubjectFormPage'));
    expect(forms, contains('MaterialFormPage'));
  });

  test(
    'public app roles cannot mutate fixed Academic Areas through the API',
    () {
      final migration = File(
        'supabase/migrations/20260904000200_fixed_academic_areas.sql',
      ).readAsStringSync();

      expect(
        migration,
        contains('drop policy if exists academic_areas_admin_insert'),
      );
      expect(
        migration,
        contains('drop policy if exists academic_areas_admin_update'),
      );
      expect(
        migration,
        contains('drop policy if exists academic_areas_admin_delete'),
      );
      expect(
        migration,
        contains(
          'revoke insert, update, delete on table public.academic_areas',
        ),
      );
      expect(migration, contains('from anon, authenticated'));
    },
  );
}

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing $end');
  return source.substring(startIndex, endIndex);
}
