import 'package:flutter_test/flutter_test.dart';
import 'package:peerstudy/models/subject.dart';

void main() {
  test('defines the corrected School and exactly two Academic Areas', () {
    expect(peerStudySchoolName, 'School of Technology and Engineering');
    expect(AcademicAreaCode.values.map((area) => area.code), <String>[
      'IT',
      'ENGINEERING',
    ]);
    expect(AcademicAreaCode.values.map((area) => area.label), <String>[
      'IT',
      'ENGINEERING',
    ]);
    expect(AcademicAreaCode.values.map((area) => area.displayName), <String>[
      'Information Technology',
      'Engineering',
    ]);
  });

  test('defines exactly five IT and three Engineering Departments', () {
    expect(peerStudyDepartmentNames[AcademicAreaCode.it], <String>{
      'Software Engineering',
      'Network',
      'Telecommunications',
      'Health Informatics',
      'Artificial Intelligence (AI)',
    });
    expect(peerStudyDepartmentNames[AcademicAreaCode.engineering], <String>{
      'Architectural and Structural Engineering',
      'Mechatronics',
      'Interior Design',
    });
    final total = peerStudyDepartmentNames.values.fold<int>(
      0,
      (count, departments) => count + departments.length,
    );
    expect(total, 8);
  });

  test('parses Supabase UUID parents and snake-case catalog fields', () {
    final school = AcademicSchool.fromSupabase(<String, dynamic>{
      'id': '00000000-0000-0000-0000-000000000001',
      'name': peerStudySchoolName,
      'status': 'active',
    });
    final area = AcademicArea.fromSupabase(<String, dynamic>{
      'id': '00000000-0000-0000-0000-000000000002',
      'school_id': school.id,
      'code': 'IT',
      'name': 'Information Technology',
      'status': 'active',
      'display_order': 1,
    });
    final department = AcademicDepartment.fromSupabase(<String, dynamic>{
      'id': '00000000-0000-0000-0000-000000000003',
      'area_id': area.id,
      'name': 'Software Engineering',
      'status': 'active',
      'display_order': 1,
    });
    final subject = StudySubject.fromSupabase(<String, dynamic>{
      'id': '00000000-0000-0000-0000-000000000004',
      'department_id': department.id,
      'code': 'SE101',
      'name': 'Introduction to Software Engineering',
      'description': 'Configured Subject',
      'status': 'active',
      'display_order': 1,
    }, areaId: area.id);

    expect(school.isAvailable, isTrue);
    expect(area.schoolId, school.id);
    expect(area.supportedCode, AcademicAreaCode.it);
    expect(department.areaId, area.id);
    expect(subject.departmentId, department.id);
    expect(subject.areaId, area.id);
    expect(subject.isAvailable, isTrue);
  });

  test('approved Material parsing keeps its exact Subject association', () {
    final material = StudyMaterial.fromSupabase(<String, dynamic>{
      'id': 'material-uuid',
      'subject_id': 'subject-uuid',
      'title': 'Approved Lecture',
      'file_url': 'approved/subject-uuid/lecture.pdf',
      'status': 'approved',
      'mime_type': 'application/pdf',
      'display_order': 2,
      'updated_at': '2026-08-28T12:00:00Z',
    });

    expect(material.subjectId, 'subject-uuid');
    expect(material.storagePath, 'approved/subject-uuid/lecture.pdf');
    expect(material.isAvailable, isTrue);
  });
}
