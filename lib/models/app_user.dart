// Application profile loaded after Supabase Authentication succeeds.
//
// Beginner note:
// Supabase Auth stores the login identity. The `profiles` table stores the
// student's full name plus the server-controlled role and restriction state.
// Both records must agree before PeerStudy opens a protected screen.

class AppUser {
  AppUser({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isBlocked,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
  });

  // The corrected master permits exactly these two application roles.
  static const String studentRole = 'student';
  static const String adminRole = 'admin';
  static const Set<String> supportedRoles = {studentRole, adminRole};

  // Unknown role values never receive a protected route.
  static const String invalidRole = 'invalid';

  // These are the only lifecycle values understood by the application.
  static const String activeStatus = 'active';
  static const String restrictedStatus = 'restricted';

  final String uid;
  final String fullName;
  final String email;
  final String role;
  final bool isBlocked;
  final String status;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Only Student and Admin are recognized by the corrected application.
  bool get hasSupportedRole => supportedRoles.contains(role);

  // Missing or future values become restricted before this check.
  bool get hasActiveStatus => status == activeStatus;

  // Role, lifecycle status, and block state must all permit protected access.
  bool get canUseProtectedFeatures =>
      hasSupportedRole && hasActiveStatus && !isBlocked;

  // A block takes priority because it is the strongest account restriction.
  String get accountStatusLabel {
    if (isBlocked) return 'Blocked';
    if (status == activeStatus) return 'Active';
    return 'Restricted';
  }

  // Convert one untrusted Supabase row into a fail-closed application profile.
  factory AppUser.fromSupabase(
    Map<String, dynamic> data, {
    String? expectedUid,
    String? expectedEmail,
  }) {
    final storedUid = data['id'];
    final storedEmail = data['email'];
    final normalizedExpectedEmail = expectedEmail?.trim().toLowerCase();
    final identityMatches =
        storedUid is String &&
        storedUid.isNotEmpty &&
        (expectedUid == null || storedUid == expectedUid) &&
        storedEmail is String &&
        storedEmail.trim().isNotEmpty &&
        (normalizedExpectedEmail == null ||
            storedEmail.trim().toLowerCase() == normalizedExpectedEmail);

    final storedBlockState = data['is_blocked'];

    return AppUser(
      uid: storedUid is String ? storedUid : '',
      fullName: data['full_name'] is String
          ? (data['full_name'] as String).trim()
          : '',
      email: storedEmail is String ? storedEmail.trim().toLowerCase() : '',
      role: identityMatches ? roleFromProfile(data['role']) : invalidRole,
      isBlocked: !identityMatches || storedBlockState is! bool
          ? true
          : storedBlockState,
      status: identityMatches
          ? statusFromProfile(data['status'])
          : restrictedStatus,
      version: versionFromProfile(data['version']),
      createdAt: dateFromProfile(data['created_at']),
      updatedAt: dateFromProfile(data['updated_at']),
    );
  }

  // This complete map is useful for trusted data conversion and tests. Public
  // registration never sends role, status, or block fields from the phone.
  Map<String, dynamic> toSupabase() {
    return {
      'id': uid,
      'full_name': fullName.trim(),
      'email': email.trim().toLowerCase(),
      'role': role,
      'is_blocked': isBlocked,
      'status': status,
      'version': version,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  // Only the corrected Student and Admin role strings are accepted.
  static String roleFromProfile(Object? value) {
    return value is String && supportedRoles.contains(value)
        ? value
        : invalidRole;
  }

  // Unknown lifecycle values fail closed to the restricted state.
  static String statusFromProfile(Object? value) {
    if (value is String &&
        (value == activeStatus || value == restrictedStatus)) {
      return value;
    }
    return restrictedStatus;
  }

  // Missing or malformed optimistic versions begin at one.
  static int versionFromProfile(Object? value) {
    return value is int && value >= 1 ? value : 1;
  }

  // Supabase normally returns ISO-8601 text, while tests may pass DateTime.
  static DateTime dateFromProfile(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}
