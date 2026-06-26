// Basic app smoke test for the PeerStudy shell.
// The goal is simple: open the app, let the splash screen finish, and confirm
// that a new user can see the public landing screen without Firebase config.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peerstudy/main.dart';

void main() {
  testWidgets('PeerStudy opens the landing screen', (tester) async {
    // Build the app like main does, with Riverpod available for providers.
    // We do not call Firebase initialization here because widget tests should
    // stay fast and should not depend on a real Firebase project.
    await tester.pumpWidget(const ProviderScope(child: PeerStudyApp()));

    // Let the splash delay finish so the router can show the landing screen.
    // pumpAndSettle waits for navigation animations and pending frames.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('PeerStudy'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Student Sign Up'), findsOneWidget);
  });
}
