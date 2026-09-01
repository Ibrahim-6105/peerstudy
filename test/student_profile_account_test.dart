// Focused widget tests for the Supabase-backed Student Profile and Account.
//
// Beginner note: cloud actions are replaced with local callbacks. This proves
// the visible behavior without needing a real phone session in unit tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerstudy/models/app_user.dart';
import 'package:peerstudy/models/subject.dart';
import 'package:peerstudy/providers/settings_provider.dart';
import 'package:peerstudy/providers/subject_provider.dart';
import 'package:peerstudy/screens/profile/student_account_screen.dart';
import 'package:peerstudy/screens/profile/student_profile_screen.dart';

void main() {
  group('StudentAccountScreen', () {
    testWidgets('shows the authenticated email, role, and status', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: StudentAccountScreen(user: _student)),
      );
      await tester.pumpAndSettle();

      expect(find.text(_student.fullName), findsOneWidget);
      expect(find.text(_student.email), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Send password reset email'), findsOneWidget);
      expect(find.textContaining('export'), findsNothing);
      expect(find.textContaining('deletion'), findsNothing);
    });
  });

  group('StudentProfileTab', () {
    testWidgets('shows real account facts, study path, and own activity', (
      tester,
    ) async {
      var loadCount = 0;
      String? loadedUserId;

      await _pumpProfile(
        tester,
        activityLoader:
            ({
              required String userId,
              required String? areaId,
              required String? departmentId,
              required String? subjectId,
            }) async {
              loadCount += 1;
              loadedUserId = userId;
              expect(areaId, _area.id);
              expect(departmentId, _department.id);
              expect(subjectId, _subject.id);
              return _recentActivity;
            },
      );
      await tester.pumpAndSettle();

      expect(loadCount, 1);
      expect(loadedUserId, _student.uid);
      expect(find.text(_student.fullName), findsOneWidget);
      expect(find.text('Role: Student'), findsOneWidget);
      expect(find.text('Status: Active'), findsOneWidget);
      expect(find.textContaining('Information Technology'), findsOneWidget);
      expect(find.textContaining('Software Engineering'), findsOneWidget);
      expect(find.textContaining('CS101 - Data Structures'), findsOneWidget);
      expect(find.text('My first Community post'), findsOneWidget);
      expect(find.text('AI quiz score: 8/10'), findsOneWidget);
      expect(find.text('Recent Community posts'), findsOneWidget);
      expect(find.text('Recent Quiz Attempts'), findsOneWidget);
    });

    testWidgets('does not read activity while Profile is hidden', (
      tester,
    ) async {
      var loadCount = 0;

      await _pumpProfile(
        tester,
        isActive: false,
        activityLoader:
            ({
              required String userId,
              required String? areaId,
              required String? departmentId,
              required String? subjectId,
            }) async {
              loadCount += 1;
              return _recentActivity;
            },
      );
      await tester.pumpAndSettle();

      expect(loadCount, 0);
      expect(
        find.text('Open Profile to load recent activity.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'updates only the full name through the injected RPC boundary',
      (tester) async {
        String? submittedName;

        await _pumpProfile(
          tester,
          profileNameUpdater: (fullName) async {
            submittedName = fullName;
            return fullName;
          },
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Edit full name'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Full name'),
          'Amina Updated',
        );
        await tester.tap(find.text('Save name'));
        await tester.pumpAndSettle();

        expect(submittedName, 'Amina Updated');
        expect(find.text('Amina Updated'), findsOneWidget);
        expect(find.text(_student.email), findsOneWidget);
      },
    );

    testWidgets('opens the Account screen through a simple direct route', (
      tester,
    ) async {
      await _pumpProfile(
        tester,
        accountScreenBuilder: (context) {
          return const Scaffold(body: Text('Account screen marker'));
        },
      );
      await tester.pumpAndSettle();

      final accountLink = find.text('Account');
      await tester.scrollUntilVisible(
        accountLink,
        100,
        maxScrolls: 20,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(accountLink);
      await tester.pumpAndSettle();

      expect(find.text('Account screen marker'), findsOneWidget);
    });
  });
}

// This notifier exposes a fixed completed settings snapshot for widget tests.
class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(SettingsState fixedState)
    : super(blobReader: _unusedSettingsReader) {
    state = fixedState;
  }
}

// The fixed notifier never performs a local storage read.
Future<Never> _unusedSettingsReader() {
  throw StateError('The fixed test settings loader must not be called.');
}

// Pump one Profile tab with known plain values and optional injected actions.
Future<void> _pumpProfile(
  WidgetTester tester, {
  bool isActive = true,
  StudentActivityLoader? activityLoader,
  ProfileNameUpdater? profileNameUpdater,
  WidgetBuilder? accountScreenBuilder,
}) {
  // The plain selection store supplies known choices in beginner tests.
  StudentSelectionStore.instance.chooseSubject(
    area: _area,
    department: _department,
    subject: _subject,
  );

  final settings = _FixedSettingsNotifier(
    const SettingsState(
      isLoading: false,
      settings: AppSettings(
        lastAreaId: 'area-it',
        lastDepartmentId: 'department-software',
        lastSubjectId: 'subject-data-structures',
      ),
    ),
  );

  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StudentProfileTab(
          isActive: isActive,
          onBrowseSubjects: () {},
          activityLoader: activityLoader,
          profileNameUpdater: profileNameUpdater,
          accountScreenBuilder: accountScreenBuilder,
          initialUser: _student,
          settingsService: settings,
        ),
      ),
    ),
  );
}

final _student = AppUser(
  uid: 'student-1',
  fullName: 'Amina Student',
  email: 'amina.student@limu.edu.ly',
  role: AppUser.studentRole,
  isBlocked: false,
  status: AppUser.activeStatus,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

const _area = AcademicArea(
  id: 'area-it',
  schoolId: 'school-technology-engineering',
  code: 'IT',
  name: 'Information Technology',
  status: 'active',
  displayOrder: 1,
);

const _department = AcademicDepartment(
  id: 'department-software',
  areaId: 'area-it',
  name: 'Software Engineering',
  status: 'active',
  displayOrder: 1,
);

const _subject = StudySubject(
  id: 'subject-data-structures',
  areaId: 'area-it',
  departmentId: 'department-software',
  code: 'CS101',
  name: 'Data Structures',
  description: 'The revised FYP acceptance subject.',
  status: 'active',
  displayOrder: 1,
);

final _recentActivity = StudentRecentActivity(
  posts: StudentActivitySection.available([
    StudentActivityEntry(
      title: 'Community post',
      preview: 'My first Community post',
      subjectId: 'community-data-structures',
      createdAt: DateTime.utc(2026, 1, 2),
    ),
  ]),
  quizzes: StudentActivitySection.available([
    StudentActivityEntry(
      title: 'AI quiz score: 8/10',
      preview: 'Completed from one approved Subject material.',
      subjectId: 'quiz-1',
      createdAt: DateTime.utc(2026, 1, 3),
    ),
  ]),
);
