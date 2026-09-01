// Initializes the one Supabase client shared by PeerStudy authentication.
//
// Beginner note:
// Screens do not initialize Supabase themselves. The small app services use
// this already initialized client after startup finishes.

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:peerstudy/config/supabase_config.dart';

class SupabaseService {
  // This is a static service holder, so no object needs to be created.
  SupabaseService._();

  // Ready becomes true only after the SDK accepts the reviewed configuration.
  static bool _isReady = false;

  // A private startup failure is retained for diagnostics without displaying
  // raw provider details or credentials to students.
  static Object? _initializationError;

  static bool get isReady => _isReady;
  static bool get isConfigured => SupabaseConfig.isConfigured;
  static Object? get initializationError => _initializationError;

  // Every caller receives the SDK singleton only after safe initialization.
  static SupabaseClient get client {
    if (!_isReady) {
      throw StateError('Supabase has not been initialized.');
    }
    return Supabase.instance.client;
  }

  // Initialize once before the first Login screen is displayed.
  static Future<void> initialize() async {
    // A second caller in the same app process reuses the existing singleton.
    if (_isReady) return;

    _isReady = false;
    _initializationError = null;

    // A malformed dart-define must fail clearly instead of reaching the SDK.
    if (!SupabaseConfig.isConfigured) return;

    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
        authOptions: const FlutterAuthClientOptions(
          // PKCE protects email confirmation and password-recovery redirects.
          authFlowType: AuthFlowType.pkce,
        ),
      );
      _isReady = true;
    } catch (error) {
      _initializationError = error;
      _isReady = false;
    }
  }
}
