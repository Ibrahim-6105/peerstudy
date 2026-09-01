// Public Supabase connection settings used by the Flutter application.
//
// Beginner note:
// A publishable key identifies this public app to Supabase. It is designed to
// be included in mobile builds. A service-role key is secret and must never be
// placed in this file, a Flutter build, or source control.

import 'dart:convert';

class SupabaseConfig {
  // This class only stores constants, so no object needs to be created.
  SupabaseConfig._();

  // Production and CI can replace the reviewed public URL at build time with:
  // --dart-define=SUPABASE_URL=https://PROJECT.supabase.co
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xihsvhhkbaaypmjjtzxa.supabase.co',
  );

  // This is the public publishable key restored from the project's reviewed
  // Supabase configuration. Never replace it with an sb_secret/service key.
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_Aih-A7TJRPLRCUBdGOr5sw_rknI1RuZ',
  );

  // Confirmation and password-recovery emails return to this application URL.
  // Native Android/iOS builds must register the same scheme with the platform.
  static const String authRedirectUrl = String.fromEnvironment(
    'SUPABASE_AUTH_REDIRECT_URL',
    defaultValue: 'io.supabase.peerstudy://login-callback',
  );

  // Older code may refer to the connection credential simply as `key`.
  static String get key => publishableKey;

  // Validate only public connection shape here. Supabase remains responsible
  // for deciding whether the project and key actually belong together.
  static bool get isConfigured {
    final projectUri = Uri.tryParse(url);
    final redirectUri = Uri.tryParse(authRedirectUrl);
    final hasPublicKey = _isPublicClientKey(publishableKey);

    return projectUri != null &&
        projectUri.scheme == 'https' &&
        projectUri.host.endsWith('.supabase.co') &&
        hasPublicKey &&
        redirectUri != null &&
        redirectUri.scheme.isNotEmpty;
  }

  // New projects use `sb_publishable_...`. A legacy JWT is accepted only when
  // its public role claim is `anon`; service-role JWTs therefore fail closed.
  static bool _isPublicClientKey(String value) {
    final key = value.trim();
    if (key.startsWith('sb_publishable_')) return true;
    if (!key.startsWith('eyJ')) return false;

    try {
      final parts = key.split('.');
      if (parts.length != 3) return false;
      final payloadBytes = base64Url.decode(base64Url.normalize(parts[1]));
      final payload = jsonDecode(utf8.decode(payloadBytes));
      return payload is Map<String, dynamic> && payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }
}
