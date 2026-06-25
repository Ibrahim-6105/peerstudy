// Central Firebase initialization and shared service helpers.
// This file keeps Firebase setup in one place so the app can use it safely.

import 'package:firebase_core/firebase_core.dart';

class FirebaseService {
  FirebaseService._();

  static bool _isReady = false;

  static bool get isReady => _isReady;

  // Initializes Firebase once and lets local builds continue without config.
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
