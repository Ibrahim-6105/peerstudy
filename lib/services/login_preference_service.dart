// This file remembers only whether this phone may restore a previous login.
//
// Security note:
// The password and Supabase access token are NEVER written here. Supabase
// Flutter already protects and restores its own session. PeerStudy stores only
// a harmless boolean marker and the matching Auth user ID in SharedPreferences.

// SharedPreferences stores small primitive values on the current device.
import 'package:shared_preferences/shared_preferences.dart';

// LoginPreferenceService keeps the tiny persistence API in one simple class.
class LoginPreferenceService {
  // The private constructor creates one shared service for the application.
  LoginPreferenceService._();

  // Screens and AuthService use this one normal singleton instance.
  static final LoginPreferenceService instance = LoginPreferenceService._();

  // Prefixing keys prevents a different plugin preference from using them.
  static const String _signedInKey = 'peerstudy.saved_login';

  // The UID lets startup reject a stale marker for a different Supabase user.
  static const String _userIdKey = 'peerstudy.saved_login_user_id';

  // Save a successful login without storing a password, email, or token.
  Future<bool> saveLogin(String userId) async {
    // Trim accidental outside spaces before checking the identifier.
    final cleanUserId = userId.trim();

    // An empty ID can never describe a valid authenticated account.
    if (cleanUserId.isEmpty) {
      await clearLogin();
      return false;
    }

    try {
      // Open the platform's small key/value preference file.
      final preferences = await SharedPreferences.getInstance();

      // Save the UID first, so a true marker never points at a missing value.
      final idWasSaved = await preferences.setString(_userIdKey, cleanUserId);

      // Mark this phone only after a successful, verified app login.
      final markerWasSaved = await preferences.setBool(_signedInKey, true);

      // A partial write is cleared rather than trusted during the next startup.
      if (!idWasSaved || !markerWasSaved) {
        await clearLogin();
        return false;
      }

      // True confirms that both safe values reached the device preferences.
      return true;
    } catch (_) {
      // Preference failure must never expose or break the real Supabase session.
      return false;
    }
  }

  // Read the UID only when both saved values form a complete marker.
  Future<String?> readSavedUserId() async {
    try {
      // Open the same platform preference store used by saveLogin.
      final preferences = await SharedPreferences.getInstance();

      // A missing or false marker means the user chose not to stay signed in.
      if (preferences.getBool(_signedInKey) != true) return null;

      // Read and trim the harmless Auth identity marker.
      final savedUserId = preferences.getString(_userIdKey)?.trim();

      // Treat a damaged empty value as signed out and repair the preference.
      if (savedUserId == null || savedUserId.isEmpty) {
        await clearLogin();
        return null;
      }

      // The caller must still compare this ID with a valid Supabase session.
      return savedUserId;
    } catch (_) {
      // A damaged preference file safely behaves like a missing login marker.
      return null;
    }
  }

  // Remove both local values during logout or a rejected server session.
  Future<void> clearLogin() async {
    try {
      // Open the platform preference store.
      final preferences = await SharedPreferences.getInstance();

      // Remove the marker before the ID so startup cannot trust partial state.
      await preferences.remove(_signedInKey);

      // Remove the saved Auth identity marker too.
      await preferences.remove(_userIdKey);
    } catch (_) {
      // AuthService still clears Supabase and memory if preferences are damaged.
    }
  }
}
