// Firebase startup helper.
// The app uses Firebase for login and user profiles, but this helper keeps the
// app runnable even before firebase_options.dart is generated.

import 'package:firebase_core/firebase_core.dart';

class FirebaseService {
  FirebaseService._();

  static bool _isReady = false;

  static bool get isReady => _isReady;

  // Initializes Firebase once and records whether it is ready.
  // If Firebase config is missing, we do not crash; auth screens will show a
  // friendly setup message instead.
  static Future<void> initializeFirebase() async {
    if (Firebase.apps.isNotEmpty) {
      _isReady = true;
      return;
    }

    try {
      await Firebase.initializeApp();
      _isReady = true;
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
