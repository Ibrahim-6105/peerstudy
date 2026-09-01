// Small widget regressions for the beginner startup and route guard.
// These tests use no Riverpod and do not connect to the live Supabase project.

// Material is used to host the isolated RoleGuard widget.
import 'package:flutter/material.dart';

// Flutter's widget test helpers render and search the test interface.
import 'package:flutter_test/flutter_test.dart';

// RoleGuard is tested with a supplied AppUser and no network.
import 'package:peerstudy/components/role_guard.dart';

// PeerStudyApp verifies the real cold-start route.
import 'package:peerstudy/main.dart';

// AppUser builds one valid active Student for the guard regression.
import 'package:peerstudy/models/app_user.dart';

// Group the two small startup/authorization widget checks.
void main() {
  // The requested first page must be Login itself, not Splash or Landing.
  testWidgets('a cold start shows Login with a clear Sign Up action', (
    tester,
  ) async {
    // Build PeerStudy exactly as main does after backend initialization.
    await tester.pumpWidget(const PeerStudyApp());

    // Let the ordinary settings load and first Flutter frame finish.
    await tester.pumpAndSettle();

    // The Login heading and primary action must be visible immediately.
    expect(find.text('PeerStudy'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);

    // New Students must have a clear account-creation button on Login.
    expect(find.text('Sign Up'), findsOneWidget);
  });

  // A valid Student must never see the removed false "sign in" content.
  testWidgets('a supplied valid Student opens protected content', (
    tester,
  ) async {
    // Build the smallest complete active Student profile.
    final now = DateTime.utc(2026, 1, 1);
    final student = AppUser(
      uid: 'widget-student',
      fullName: 'Widget Student',
      email: 'widget.student@limu.edu.ly',
      role: AppUser.studentRole,
      isBlocked: false,
      status: AppUser.activeStatus,
      createdAt: now,
      updatedAt: now,
    );

    // Supply the profile through RoleGuard's test-only input.
    await tester.pumpWidget(
      MaterialApp(
        home: RoleGuard(
          allowedRoles: const {AppUser.studentRole},
          testUser: student,
          child: const Scaffold(body: Text('Protected Student Content')),
        ),
      ),
    );

    // Run the post-frame access check and its one setState rebuild.
    await tester.pump();

    // The real child appears and the old misleading auth page does not.
    expect(find.text('Protected Student Content'), findsOneWidget);
    expect(find.textContaining('Please sign in'), findsNothing);
  });
}
