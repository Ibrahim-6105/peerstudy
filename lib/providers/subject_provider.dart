// Simple academic data helper for School -> Area -> Department -> Subject.
//
// Beginner note:
// There is no state-management package in this file. A screen creates one
// SubjectRepository, awaits a method, and then calls setState with the result.
// SubjectRepository is the only class that knows the Supabase table names.

import 'package:peerstudy/models/subject.dart';
import 'package:peerstudy/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// This tiny object remembers the last catalog choice while the app is open.
// It is intentionally just three fields, not a provider or state manager.
class StudentSelectionStore {
  // A private constructor prevents accidental extra copies of the store.
  StudentSelectionStore._();

  // Every screen reads the same small in-memory store through this instance.
  static final StudentSelectionStore instance = StudentSelectionStore._();

  // Private fields can change only through the clear, choose... methods below.
  AcademicArea? _selectedArea;
  AcademicDepartment? _selectedDepartment;
  StudySubject? _selectedSubject;

  // Read-only getters make the values easy to use on Home and Profile.
  AcademicArea? get selectedArea => _selectedArea;
  AcademicDepartment? get selectedDepartment => _selectedDepartment;
  StudySubject? get selectedSubject => _selectedSubject;

  // Choosing a new Area clears children that belonged to the old Area.
  void chooseArea(AcademicArea area) {
    _selectedArea = area;
    _selectedDepartment = null;
    _selectedSubject = null;
  }

  // Choosing a Department remembers its Area and clears an old Subject.
  void chooseDepartment({
    required AcademicArea area,
    required AcademicDepartment department,
  }) {
    _selectedArea = area;
    _selectedDepartment = department;
    _selectedSubject = null;
  }

  // Choosing a Subject keeps the full parent chain for recent activity.
  void chooseSubject({
    required AcademicArea area,
    required AcademicDepartment department,
    required StudySubject subject,
  }) {
    _selectedArea = area;
    _selectedDepartment = department;
    _selectedSubject = subject;
  }

  // Sign-out can remove every in-memory academic selection in one call.
  void clear() {
    _selectedArea = null;
    _selectedDepartment = null;
    _selectedSubject = null;
  }
}

// The repository owns every read-only corrected-master catalog query.
class SubjectRepository {
  SubjectRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  // A supplied client is used by focused tests. Normal app reads fail clearly
  // if Supabase startup has not completed instead of touching a null service.
  SupabaseClient get _client {
    final injectedClient = _injectedClient;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseService.isReady) {
      throw StateError(
        'The academic database is unavailable. Check your connection and retry.',
      );
    }
    return SupabaseService.client;
  }

  // Finds the one active School of Technology and Engineering row.
  Future<AcademicSchool> fetchSchool() async {
    final response = await _client
        .from('schools')
        .select()
        .eq('name', peerStudySchoolName)
        .eq('status', 'active')
        .limit(2);
    final schools = _rows(response)
        .map(AcademicSchool.fromSupabase)
        .where((school) => school.isAvailable)
        .toList(growable: false);
    if (schools.length != 1) {
      throw StateError(
        'The School of Technology and Engineering is not configured correctly.',
      );
    }
    return schools.single;
  }

  // Reads only supported active Areas under the exact school parent UUID.
  Future<List<AcademicArea>> fetchAcademicAreas(String schoolId) async {
    _requireId(schoolId, 'schoolId');
    final response = await _client
        .from('academic_areas')
        .select()
        .eq('school_id', schoolId)
        .eq('status', 'active')
        .order('display_order');
    final areas = _rows(response)
        .map(AcademicArea.fromSupabase)
        .where((area) => area.isAvailable && area.schoolId == schoolId)
        .toList(growable: false);
    final seenCodes = <AcademicAreaCode>{};
    for (final area in areas) {
      final supportedCode = area.supportedCode!;
      if (!seenCodes.add(supportedCode)) {
        throw StateError('An Academic Area code is configured more than once.');
      }
    }
    return List<AcademicArea>.unmodifiable(areas);
  }

  // Reads the Area code first, then accepts only its corrected-master names.
  Future<List<AcademicDepartment>> fetchDepartments(String areaId) async {
    _requireId(areaId, 'areaId');
    final areaResponse = await _client
        .from('academic_areas')
        .select()
        .eq('id', areaId)
        .eq('status', 'active')
        .limit(1);
    final areaRows = _rows(areaResponse);
    if (areaRows.length != 1) {
      throw StateError('The selected Academic Area is no longer available.');
    }
    final area = AcademicArea.fromSupabase(areaRows.single);
    final areaCode = area.supportedCode;
    if (!area.isAvailable || areaCode == null) {
      throw StateError('The selected Academic Area is not supported.');
    }

    final response = await _client
        .from('departments')
        .select()
        .eq('area_id', areaId)
        .eq('status', 'active')
        .order('display_order');
    final expectedNames = peerStudyDepartmentNames[areaCode]!;
    final departments = _rows(response)
        .map(AcademicDepartment.fromSupabase)
        .where(
          (department) =>
              department.isAvailable &&
              department.areaId == areaId &&
              expectedNames.contains(department.name),
        )
        .toList(growable: false);
    return List<AcademicDepartment>.unmodifiable(departments);
  }

  // A direct department_id equality is the authoritative parent filter.
  Future<List<StudySubject>> fetchSubjects(
    AcademicDepartment department,
  ) async {
    _requireId(department.id, 'departmentId');
    _requireId(department.areaId, 'areaId');
    if (!department.isAvailable) {
      throw StateError('The selected Department is no longer available.');
    }
    final response = await _client
        .from('subjects')
        .select()
        .eq('department_id', department.id)
        .eq('status', 'active')
        .order('name');
    final subjects = _rows(response)
        .map((row) => StudySubject.fromSupabase(row, areaId: department.areaId))
        .where(
          (subject) =>
              subject.isAvailable &&
              subject.departmentId == department.id &&
              subject.areaId == department.areaId,
        )
        .toList(growable: false);
    return List<StudySubject>.unmodifiable(subjects);
  }

  // Approved Materials are filtered by subject_id before reaching the UI.
  Future<List<StudyMaterial>> fetchMaterials(StudySubject subject) async {
    _requireId(subject.id, 'subjectId');
    if (!subject.isAvailable) {
      throw StateError('The selected Subject is no longer available.');
    }
    final response = await _client
        .from('subject_materials')
        .select()
        .eq('subject_id', subject.id)
        .eq('status', 'approved')
        .order('created_at');
    final materials = _rows(response)
        .map(StudyMaterial.fromSupabase)
        .where(
          (material) =>
              material.isAvailable && material.subjectId == subject.id,
        )
        .toList(growable: false);
    return List<StudyMaterial>.unmodifiable(materials);
  }
}

// Converts dynamic PostgREST rows into typed maps without trusting raw data.
List<Map<String, dynamic>> _rows(Object? response) {
  if (response is! List) {
    throw StateError('The academic database returned an invalid response.');
  }
  return response
      .map((row) {
        if (row is! Map) {
          throw StateError('The academic database returned an invalid row.');
        }
        return Map<String, dynamic>.from(row);
      })
      .toList(growable: false);
}

// UUID values stay opaque, but empty parent IDs never enter a database query.
void _requireId(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'Cannot be empty.');
  }
}
