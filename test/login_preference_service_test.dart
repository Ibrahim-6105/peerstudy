// Focused tests for the harmless SharedPreferences login marker.

// Flutter Test supplies expectations and the plugin test binding.
import 'package:flutter_test/flutter_test.dart';

// PeerStudy's small service is the subject of these tests.
import 'package:peerstudy/services/login_preference_service.dart';

// SharedPreferences supplies an in-memory test store with no phone filesystem.
import 'package:shared_preferences/shared_preferences.dart';

// Group all marker expectations in the normal Dart test entry point.
void main() {
  // Flutter plugins need a binding before a test opens preferences.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Start every test with a completely empty device preference store.
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // A successful account login saves only the allowed safe primitives.
  test('saves a boolean and verified user ID without credentials', () async {
    // Use a normal UUID-shaped identity, not a real account value.
    const userId = '11111111-2222-3333-4444-555555555555';

    // Save through the exact production singleton API.
    final saved = await LoginPreferenceService.instance.saveLogin(userId);

    // The complete two-value marker should report success.
    expect(saved, isTrue);

    // The public read API returns the same harmless Auth identity.
    expect(await LoginPreferenceService.instance.readSavedUserId(), userId);

    // Inspect the in-memory plugin store to prevent accidental secret fields.
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), <String>{
      'peerstudy.saved_login',
      'peerstudy.saved_login_user_id',
    });
    expect(preferences.getBool('peerstudy.saved_login'), isTrue);
    expect(preferences.getString('peerstudy.saved_login_user_id'), userId);
  });

  // Logout removes both values so cold startup cannot route automatically.
  test('clear removes the complete saved-login marker', () async {
    // Create the normal marker first.
    await LoginPreferenceService.instance.saveLogin('test-user-id');

    // Simulate AuthService logout or a rejected server profile.
    await LoginPreferenceService.instance.clearLogin();

    // Both the service API and underlying plugin store must now be empty.
    expect(await LoginPreferenceService.instance.readSavedUserId(), isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), isEmpty);
  });

  // A partial preference write never becomes authorization by itself.
  test(
    'rejects and repairs a true marker without a matching user ID',
    () async {
      // Reproduce an interrupted old write containing only the boolean.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'peerstudy.saved_login': true,
      });

      // The service treats this incomplete state exactly like signed out.
      expect(await LoginPreferenceService.instance.readSavedUserId(), isNull);

      // Reading also repairs the broken local value for the next startup.
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), isEmpty);
    },
  );
}
