// Data models for PeerStudy's corrected academic hierarchy.
//
// Beginner note:
// A model gives one Supabase database row clear Dart field names. PeerStudy's
// complete path is School -> Academic Area -> Department -> Subject.

// The corrected master limits the first release to this one school.
const String peerStudySchoolName = 'School of Technology and Engineering';

// These are the only two Academic Area codes accepted in the first release.
enum AcademicAreaCode {
  it('IT', 'IT', 'Information Technology'),
  engineering('ENGINEERING', 'ENGINEERING', 'Engineering');

  const AcademicAreaCode(this.code, this.label, this.displayName);

  // Supabase stores this stable code separately from the row's UUID.
  final String code;

  // This short legacy label keeps unrelated saved-selection screens stable.
  final String label;

  // Corrected academic screens use the complete database-facing name.
  final String displayName;

  // Older callers used a small text ID before Supabase UUIDs were introduced.
  // Keeping this getter avoids breaking unrelated screens during migration.
  String get id => this == it ? 'it' : 'engineering';

  // Converts a database code into one of the two supported values.
  static AcademicAreaCode? fromCode(String value) {
    final normalized = value.trim().toUpperCase();
    for (final item in values) {
      if (item.code == normalized) return item;
    }
    return null;
  }
}

// The corrected master names exactly five IT and three Engineering departments.
const Map<AcademicAreaCode, Set<String>> peerStudyDepartmentNames = {
  AcademicAreaCode.it: {
    'Software Engineering',
    'Network',
    'Telecommunications',
    'Health Informatics',
    'Artificial Intelligence (AI)',
  },
  AcademicAreaCode.engineering: {
    'Architectural and Structural Engineering',
    'Mechatronics',
    'Interior Design',
  },
};

// One school row supplies the fixed top-level context shown on Home.
class AcademicSchool {
  const AcademicSchool({
    required this.id,
    required this.name,
    required this.status,
  });

  final String id;
  final String name;
  final String status;

  bool get isAvailable =>
      id.trim().isNotEmpty &&
      name.trim() == peerStudySchoolName &&
      status == 'active';

  // Supabase returns every selected row as a string-keyed map.
  factory AcademicSchool.fromSupabase(Map<String, dynamic> row) {
    return AcademicSchool(
      id: _text(row['id'] ?? row['school_id']),
      name: _text(row['name'], fallback: 'Unnamed school'),
      status: _rowStatus(row),
    );
  }
}

// One of the two Academic Areas belonging to the configured school.
class AcademicArea {
  const AcademicArea({
    required this.id,
    this.schoolId = '',
    required this.code,
    required this.name,
    required this.status,
    required this.displayOrder,
  });

  final String id;
  final String schoolId;
  final String code;
  final String name;
  final String status;
  final int displayOrder;

  AcademicAreaCode? get supportedCode => AcademicAreaCode.fromCode(code);

  bool get isAvailable =>
      id.trim().isNotEmpty &&
      schoolId.trim().isNotEmpty &&
      status == 'active' &&
      supportedCode != null;

  String get displayName => supportedCode?.displayName ?? name;

  factory AcademicArea.fromSupabase(Map<String, dynamic> row) {
    final name = _text(row['name'], fallback: 'Unnamed academic area');
    final rawCode = _text(row['code']).toUpperCase();
    var inferredCode = '';
    for (final item in AcademicAreaCode.values) {
      if (item.displayName.toLowerCase() == name.toLowerCase()) {
        inferredCode = item.code;
      }
    }
    return AcademicArea(
      id: _text(row['id'] ?? row['area_id']),
      schoolId: _text(row['school_id']),
      code: rawCode.isNotEmpty ? rawCode : inferredCode,
      name: name,
      status: _rowStatus(row),
      displayOrder: _integer(row['display_order']),
    );
  }
}

// One Department belonging to one Academic Area UUID.
class AcademicDepartment {
  const AcademicDepartment({
    required this.id,
    required this.areaId,
    required this.name,
    required this.status,
    required this.displayOrder,
  });

  final String id;
  final String areaId;
  final String name;
  final String status;
  final int displayOrder;

  bool get isAvailable =>
      id.trim().isNotEmpty && areaId.trim().isNotEmpty && status == 'active';

  factory AcademicDepartment.fromSupabase(Map<String, dynamic> row) {
    return AcademicDepartment(
      id: _text(row['id'] ?? row['department_id']),
      areaId: _text(row['area_id']),
      name: _text(row['name'], fallback: 'Unnamed department'),
      status: _rowStatus(row),
      displayOrder: _integer(row['display_order']),
    );
  }
}

// One Subject belonging to one Department UUID.
class StudySubject {
  const StudySubject({
    required this.id,
    required this.areaId,
    required this.departmentId,
    required this.code,
    required this.name,
    required this.description,
    required this.status,
    required this.displayOrder,
  });

  final String id;

  // areaId is retained in the UI model as useful parent context. The corrected
  // database owns the authoritative direct relationship through departmentId.
  final String areaId;
  final String departmentId;
  final String code;
  final String name;
  final String description;
  final String status;
  final int displayOrder;

  bool get isAvailable =>
      id.trim().isNotEmpty &&
      departmentId.trim().isNotEmpty &&
      status == 'active';

  // Materials, quiz attempts, and the single Community use this same UUID.
  String get workspaceId => id;

  factory StudySubject.fromSupabase(
    Map<String, dynamic> row, {
    required String areaId,
  }) {
    return StudySubject(
      id: _text(row['id'] ?? row['subject_id']),
      areaId: areaId,
      departmentId: _text(row['department_id']),
      code: _text(row['code']).toUpperCase(),
      name: _text(row['name'], fallback: 'Unnamed subject'),
      description: _text(row['description']),
      status: _rowStatus(row),
      displayOrder: _integer(row['display_order']),
    );
  }
}

// Metadata for one approved PDF stored by Supabase Storage.
class StudyMaterial {
  const StudyMaterial({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.storagePath,
    required this.version,
    required this.status,
    required this.mimeType,
    required this.sizeBytes,
    required this.checksum,
    required this.displayOrder,
    required this.updatedAt,
    this.summary = '',
    this.uploadedBy,
  });

  final String id;
  final String subjectId;
  final String title;
  final String summary;
  final String storagePath;
  final int version;
  final String status;
  final String mimeType;
  final int sizeBytes;
  final String checksum;
  final int displayOrder;
  final DateTime updatedAt;
  final String? uploadedBy;

  bool get isAvailable =>
      id.trim().isNotEmpty &&
      subjectId.trim().isNotEmpty &&
      status == 'approved' &&
      mimeType == 'application/pdf' &&
      storagePath.trim().isNotEmpty;

  factory StudyMaterial.fromSupabase(Map<String, dynamic> row) {
    final uploadedBy = _text(row['uploaded_by']);
    return StudyMaterial(
      id: _text(row['id'] ?? row['material_id']),
      subjectId: _text(row['subject_id']),
      title: _text(row['title'], fallback: 'Untitled material'),
      summary: _text(row['summary']),
      storagePath: _text(row['storage_path'] ?? row['file_url']),
      version: _integer(row['version'], fallback: 1),
      status: _text(row['status'], fallback: 'unavailable').toLowerCase(),
      mimeType: _text(
        row['mime_type'] ?? row['content_type'],
        fallback: 'application/pdf',
      ).toLowerCase(),
      sizeBytes: _integer(row['size_bytes']),
      checksum: _text(row['checksum']),
      displayOrder: _integer(row['display_order']),
      updatedAt: _dateTime(row['updated_at'] ?? row['created_at']),
      uploadedBy: uploadedBy.isEmpty ? null : uploadedBy,
    );
  }
}

// A short-lived material URL returned by the trusted backend.
class MaterialAccess {
  const MaterialAccess({
    required this.materialId,
    required this.signedUrl,
    required this.version,
    required this.checksum,
    required this.expiresAt,
  });

  final String materialId;
  final Uri signedUrl;
  final int version;
  final String checksum;
  final DateTime expiresAt;

  factory MaterialAccess.fromMap(Map<Object?, Object?> data) {
    return MaterialAccess(
      materialId: _objectText(data['materialId'] ?? data['material_id']),
      signedUrl: Uri.parse(
        _objectText(data['signedUrl'] ?? data['signed_url']),
      ),
      version: _objectInteger(data['version']),
      checksum: _objectText(data['checksum']),
      expiresAt: _objectDateTime(data['expiresAt'] ?? data['expires_at']),
    );
  }
}

// Small parsing helpers keep every beginner-facing factory short and uniform.
String _text(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _integer(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

// Every catalog table uses one readable active/inactive status value.
String _rowStatus(Map<String, dynamic> row) {
  final status = _text(row['status']).toLowerCase();
  return status.isEmpty ? 'inactive' : status;
}

DateTime _dateTime(Object? value) {
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);
}

String _objectText(Object? value) => _text(value);

int _objectInteger(Object? value) => _integer(value);

DateTime _objectDateTime(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
}
