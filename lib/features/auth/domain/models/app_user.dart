// Model for a user profile in Firestore.
// This class maps the fields saved under users/{userId}.

import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  AppUser({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.role,
    required this.majorId,
    required this.departmentId,
    required this.yearId,
    required this.isBlocked,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uid;
  final String fullName;
  final String email;
  final String role;
  final String majorId;
  final String departmentId;
  final String yearId;
  final bool isBlocked;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AppUser.fromFirestore(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>? ?? {};
    return AppUser(
      uid: data['uid'] as String? ?? '',
      fullName: data['fullName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'student',
      majorId: data['majorId'] as String? ?? '',
      departmentId: data['departmentId'] as String? ?? '',
      yearId: data['yearId'] as String? ?? '',
      isBlocked: data['isBlocked'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'fullName': fullName,
      'email': email,
      'role': role,
      'majorId': majorId,
      'departmentId': departmentId,
      'yearId': yearId,
      'isBlocked': isBlocked,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
