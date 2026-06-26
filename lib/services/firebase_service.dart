// Firebase startup helper.
// The app uses Firebase for login and user profiles, so this helper initializes
// Firebase once using the FlutterFire-generated options in firebase_options.dart.
// Keeping this in one file makes startup easier to understand and debug.

import 'package:firebase_core/firebase_core.dart';
import 'package:peerstudy/firebase_options.dart';

class FirebaseService {
  FirebaseService._();

  static bool _isReady = false;

  static bool get isReady => _isReady;

  // Initializes Firebase once and records whether it is ready.
  // Android and iOS use DefaultFirebaseOptions.currentPlatform. Unsupported
  // platforms continue without crashing, so web/desktop development can still
  // open the UI until those Firebase apps are configured later.
  static Future<void> initializeFirebase() async {
    if (Firebase.apps.isNotEmpty) {
      _isReady = true;
      return;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _isReady = true;
    } on UnsupportedError {
      _isReady = false;
    } on FirebaseException catch (error) {
      final isMissingConfig =
          error.code == 'core/not-initialized' ||
          error.code == 'invalid-app-argument' ||
          error.message?.toLowerCase().contains('options') == true ||
          error.message?.toLowerCase().contains('configuration') == true;

      if (!isMissingConfig) {
        rethrow;
      }

      _isReady = false;
    } catch (_) {
      _isReady = false;
    }
  }
}
