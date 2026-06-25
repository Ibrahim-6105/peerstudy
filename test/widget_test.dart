// Basic app smoke test for the PeerStudy shell.
// It verifies startup reaches the public landing screen without Firebase config.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peerstudy/main.dart';

void main() {
  testWidgets('PeerStudy opens the landing screen', (tester) async {
    // Build the app exactly like main does, but without starting Firebase.
    await tester.pumpWidget(const ProviderScope(child: PeerStudyApp()));

    // Let the splash delay finish so the router can show the landing screen.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('PeerStudy'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Student Sign Up'), findsOneWidget);
  });
}
