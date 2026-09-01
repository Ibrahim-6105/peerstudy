// Focused tests for the pure validation and role decisions used by Supabase
// authentication. These tests do not contact a live project or alter accounts.

import 'package:flutter_test/flutter_test.dart';
import 'package:peerstudy/components/role_guard.dart';
import 'package:peerstudy/models/app_user.dart';
import 'package:peerstudy/services/auth_service.dart';
import 'package:peerstudy/utils/validators.dart';

void main() {
  group('LIMU login email validation', () {
    test('accepts and normalizes a complete LIMU address', () {
      expect(isValidLimuEmail('student@limu.edu.ly'), isTrue);
      expect(
        normalizedLimuLoginEmail(' Student@LIMU.EDU.LY '),
        'student@limu.edu.ly',
      );
      expect(
        normalizedLoginIdentifier(' Student@LIMU.EDU.LY '),
        'student@limu.edu.ly',
      );
    });

    test('maps only the exact Admin alias to the pre-created account', () {
      expect(normalizedLimuLoginEmail('admin'), isNull);
      expect(normalizedLoginIdentifier(' ADMIN '), 'admin@limu.edu.ly');
      expect(normalizedLoginIdentifier('administrator'), isNull);
    });

    test('rejects a Student username and a non-LIMU address', () {
      expect(normalizedLoginIdentifier('student'), isNull);
      expect(normalizedLimuLoginEmail('student@gmail.com'), isNull);
    });
  });

  group('Student registration input', () {
    test('normalizes safe full-name whitespace', () {
      expect(
        normalizedRegistrationFullName('  Student   Example  '),
        'Student Example',
      );
    });

    test('requires 2-100 safe characters for a full name', () {
      expect(normalizedRegistrationFullName('   '), isNull);
      expect(normalizedRegistrationFullName('A'), isNull);
      expect(normalizedRegistrationFullName('Al'), 'Al');
      expect(
        normalizedRegistrationFullName(List.filled(101, 'A').join()),
        isNull,
      );
      expect(normalizedRegistrationFullName('Student\nExample'), isNull);
    });

    test('requires a bounded password containing letters and numbers', () {
      expect(isValidNewPassword('ValidPass123'), isTrue);
      expect(isValidNewPassword('Pass123'), isFalse);
      expect(isValidNewPassword('OnlyLetters'), isFalse);
      expect(isValidNewPassword('12345678'), isFalse);
      expect(isValidNewPassword(List.filled(65, 'A1').join()), isFalse);
    });
  });

  group('role guard access decision', () {
    test('allows active Students and Admins only on their allowed routes', () {
      final student = _user(role: AppUser.studentRole);
      final admin = _user(role: AppUser.adminRole);

      expect(canAccessAnyRole(student, {AppUser.studentRole}), isTrue);
      expect(canAccessAnyRole(student, {AppUser.adminRole}), isFalse);
      expect(canAccessAnyRole(admin, {AppUser.adminRole}), isTrue);
      expect(canAccessAnyRole(admin, {AppUser.studentRole}), isFalse);
    });

    test('rejects the removed moderator role even if a route requests it', () {
      final removedRole = _user(role: 'moderator');

      expect(canAccessAnyRole(removedRole, {'moderator'}), isFalse);
      expect(removedRole.canUseProtectedFeatures, isFalse);
    });

    test('denies missing, blocked, and restricted profiles', () {
      expect(canAccessAnyRole(null, {AppUser.studentRole}), isFalse);
      expect(
        canAccessAnyRole(_user(role: AppUser.studentRole, isBlocked: true), {
          AppUser.studentRole,
        }),
        isFalse,
      );
      expect(
        canAccessAnyRole(
          _user(role: AppUser.studentRole, status: AppUser.restrictedStatus),
          {AppUser.studentRole},
        ),
        isFalse,
      );
    });
  });

  group('Supabase profile session validation', () {
    test('accepts one complete active profile', () {
      expect(_canOpenSession(_profileData()), isTrue);
    });

    test('fails closed for lifecycle and role restrictions', () {
      expect(
        _canOpenSession(_profileData(status: AppUser.restrictedStatus)),
        isFalse,
      );
      expect(_canOpenSession(_profileData(isBlocked: true)), isFalse);
      expect(_canOpenSession(_profileData(role: 'moderator')), isFalse);

      final missingStatus = _profileData()..remove('status');
      expect(_canOpenSession(missingStatus), isFalse);
    });

    test('fails closed for mismatched identity and malformed timestamps', () {
      expect(_canOpenSession(_profileData(id: 'another-user')), isFalse);
      expect(
        _canOpenSession(_profileData(email: 'other@limu.edu.ly')),
        isFalse,
      );
      expect(
        _canOpenSession(_profileData(updatedAt: 'not-a-timestamp')),
        isFalse,
      );

      final malformedName = _profileData()..['full_name'] = 'Test\nUser';
      expect(_canOpenSession(malformedName), isFalse);
    });

    test('the same decision rejects a restricted profile refresh', () {
      final liveProfile = _profileData();
      expect(_canOpenSession(liveProfile), isTrue);

      // A later protected-route refresh applies the same server-owned rule.
      liveProfile['status'] = AppUser.restrictedStatus;
      expect(_canOpenSession(liveProfile), isFalse);
    });
  });

  group('AppUser Supabase parsing', () {
    test('loads a trusted active Student row', () {
      final user = AppUser.fromSupabase(
        _profileData(),
        expectedUid: 'test-user',
        expectedEmail: 'test@limu.edu.ly',
      );

      expect(user.uid, 'test-user');
      expect(user.fullName, 'Test User');
      expect(user.email, 'test@limu.edu.ly');
      expect(user.role, AppUser.studentRole);
      expect(user.status, AppUser.activeStatus);
      expect(user.canUseProtectedFeatures, isTrue);
      expect(user.version, 1);
    });

    test('converts removed and unknown roles to an inaccessible role', () {
      final removedRole = AppUser.fromSupabase(_profileData(role: 'moderator'));
      final unknownRole = AppUser.fromSupabase(_profileData(role: 'owner'));

      expect(removedRole.role, AppUser.invalidRole);
      expect(removedRole.canUseProtectedFeatures, isFalse);
      expect(unknownRole.role, AppUser.invalidRole);
    });

    test('unknown status and mismatched identity fail closed', () {
      final unknownStatus = AppUser.fromSupabase(
        _profileData(status: 'future-value'),
      );
      final mismatch = AppUser.fromSupabase(
        _profileData(),
        expectedUid: 'different-user',
        expectedEmail: 'test@limu.edu.ly',
      );

      expect(unknownStatus.status, AppUser.restrictedStatus);
      expect(unknownStatus.accountStatusLabel, 'Restricted');
      expect(mismatch.role, AppUser.invalidRole);
      expect(mismatch.isBlocked, isTrue);
    });

    test('uses safe version and date defaults for malformed values', () {
      final malformed = _profileData()
        ..['version'] = 0
        ..['created_at'] = 'invalid';
      final user = AppUser.fromSupabase(malformed);

      expect(user.version, 1);
      expect(user.createdAt.millisecondsSinceEpoch, 0);
      expect(AppUser.versionFromProfile(4), 4);
      expect(AppUser.versionFromProfile('4'), 1);
    });
  });
}

// Creates the smallest realistic profile needed by the pure guard tests.
AppUser _user({
  required String role,
  bool isBlocked = false,
  String status = AppUser.activeStatus,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return AppUser(
    uid: 'test-user',
    fullName: 'Test User',
    email: 'test@limu.edu.ly',
    role: role,
    isBlocked: isBlocked,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

// Builds the exact snake_case row returned by the Supabase `profiles` table.
Map<String, dynamic> _profileData({
  String id = 'test-user',
  String email = 'test@limu.edu.ly',
  String role = AppUser.studentRole,
  bool isBlocked = false,
  String status = AppUser.activeStatus,
  String updatedAt = '2026-01-01T00:00:00.000Z',
}) {
  return {
    'id': id,
    'full_name': 'Test User',
    'email': email,
    'role': role,
    'is_blocked': isBlocked,
    'status': status,
    'version': 1,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': updatedAt,
  };
}

// Calls the exact pure decision shared by login and Supabase Realtime updates.
bool _canOpenSession(Map<String, dynamic> profile) {
  return profileCanOpenProtectedSession(
    profile,
    authUid: 'test-user',
    authEmail: 'test@limu.edu.ly',
  );
}
