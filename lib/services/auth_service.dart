// This file contains the complete, beginner-friendly authentication logic.
// It uses one normal Dart object instead of Riverpod, Provider, BLoC, or any
// other state-management package.

// `dart:async` gives us StreamSubscription for Supabase recovery-link events.
import 'dart:async';

// Supabase Flutter supplies the real email/password authentication client.
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

// The redirect URL is used when Supabase sends a password-recovery email.
import 'package:peerstudy/config/supabase_config.dart';

// AppUser is the simple Dart model for a Student or Admin profile.
import 'package:peerstudy/models/app_user.dart';

// SettingsNotifier clears the last account's saved academic path on sign-out.
import 'package:peerstudy/providers/settings_provider.dart';

// StudentSelectionStore clears the last account's in-memory study choices.
import 'package:peerstudy/providers/subject_provider.dart';

// LoginPreferenceService stores only a boolean and UID after verified login.
import 'package:peerstudy/services/login_preference_service.dart';

// SupabaseService owns the one initialized Supabase client used by the app.
import 'package:peerstudy/services/supabase_service.dart';

// These small helpers validate LIMU emails and passwords before network calls.
import 'package:peerstudy/utils/validators.dart';

// The root widget assigns this callback so recovery links can open one screen.
typedef PasswordRecoveryCallback = void Function();

// This helper cleans and checks a registration name in one easy-to-test place.
String? normalizedRegistrationFullName(String? value) {
  // A missing name is not valid.
  if (value == null) return null;

  // Control characters do not belong in a display name.
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) return null;

  // Trim outside spaces and turn repeated spaces into one space.
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');

  // The database accepts normal names between 2 and 100 characters.
  if (normalized.length < 2 || normalized.length > 100) return null;

  // Return the clean value that can safely be sent to Supabase.
  return normalized;
}

// This pure helper verifies that Auth and the public profile describe the same
// active account. It stays public because focused tests also use it.
bool profileCanOpenProtectedSession(
  Map<String, dynamic> data, {
  required String authUid,
  required String authEmail,
}) {
  // Normalize the trusted Auth email before comparing it with the profile.
  final normalizedAuthEmail = normalizedLimuLoginEmail(authEmail);

  // Read the few profile values needed for the access decision.
  final profileId = data['id'];
  final profileEmail = data['email'];
  final fullName = data['full_name'];
  final role = data['role'];
  final isBlocked = data['is_blocked'];
  final status = data['status'];

  // Read both timestamps so malformed or incomplete rows fail closed.
  final createdAt = data['created_at'];
  final updatedAt = data['updated_at'];

  // Every condition must pass before a protected page can open.
  return normalizedAuthEmail != null &&
      profileId is String &&
      profileId == authUid &&
      profileEmail is String &&
      profileEmail.trim().toLowerCase() == normalizedAuthEmail &&
      fullName is String &&
      normalizedRegistrationFullName(fullName) != null &&
      role is String &&
      AppUser.supportedRoles.contains(role) &&
      isBlocked is bool &&
      isBlocked == false &&
      status == AppUser.activeStatus &&
      _isProfileDate(createdAt) &&
      _isProfileDate(updatedAt);
}

// Supabase sends ISO text, while small unit tests may use DateTime objects.
bool _isProfileDate(Object? value) {
  // Accept a real DateTime or an ISO value that Dart can parse completely.
  return value is DateTime ||
      (value is String && DateTime.tryParse(value) != null);
}

// AuthService is a singleton, so every screen reads the same signed-in user.
// A singleton is simply one shared object created once for the whole app.
class AuthService {
  // The private constructor prevents screens from creating competing sessions.
  AuthService._();

  // `instance` is the one shared authentication object used by all screens.
  static final AuthService instance = AuthService._();

  // This getter keeps the Supabase SDK detail inside this service.
  sb.SupabaseClient get _client => SupabaseService.client;

  // The loaded Student/Admin profile is kept in one ordinary Dart variable.
  AppUser? _currentUser;

  // Screens may read the current user but cannot accidentally replace it.
  AppUser? get currentUser => _currentUser;

  // This flag tells signup when Supabase requires email confirmation.
  bool requiresEmailConfirmation = false;

  // This flag becomes true only after a valid password-recovery event.
  bool isPasswordRecovery = false;

  // This safe message explains why the most recent profile check failed.
  String? lastMessage;

  // The app widget places its navigation callback here after it is mounted.
  PasswordRecoveryCallback? onPasswordRecovery;

  // This subscription listens only for Auth events that matter globally.
  StreamSubscription<sb.AuthState>? _authSubscription;

  // This getter is useful before protected pages perform a profile query.
  bool get hasSession =>
      SupabaseService.isReady &&
      _client.auth.currentSession != null &&
      _client.auth.currentUser != null;

  // Start one small listener for sign-out and recovery-link events.
  // Login itself loads the profile directly, which avoids an event timing race.
  void startListening() {
    // Do nothing when setup failed or the listener already exists.
    if (!SupabaseService.isReady || _authSubscription != null) return;

    // Listen to Supabase's authentication event stream.
    _authSubscription = _client.auth.onAuthStateChange.listen((event) {
      // A recovery event contains the short-lived session from the email link.
      if (event.event == sb.AuthChangeEvent.passwordRecovery) {
        // Normal protected pages must stay closed during password recovery.
        _currentUser = null;

        // Remember this state for the reset form and for a late root callback.
        isPasswordRecovery = true;

        // A recovery session is temporary and must not become a saved login.
        unawaited(LoginPreferenceService.instance.clearLogin());

        // Ask the mounted app navigator to open the new-password screen.
        onPasswordRecovery?.call();

        // No other event handling is needed for this recovery event.
        return;
      }

      // A real Supabase sign-out clears the local profile immediately.
      if (event.event == sb.AuthChangeEvent.signedOut) {
        _currentUser = null;

        // Remove the harmless SharedPreferences login marker too.
        unawaited(LoginPreferenceService.instance.clearLogin());

        // Clear account-specific study choices even for an SDK-driven sign-out.
        unawaited(_clearAccountData());
      }
    });
  }

  // Sign in with a LIMU email or the exact beginner-friendly Admin alias.
  // A null return value means success; a String is a friendly form error.
  Future<String?> signIn(String identifier, String password) async {
    // Clear messages left by an earlier form attempt.
    lastMessage = null;
    requiresEmailConfirmation = false;
    isPasswordRecovery = false;

    // The form never relies on a profile left by an earlier account.
    _currentUser = null;

    // Only a newly verified successful login is allowed to set this marker.
    await LoginPreferenceService.instance.clearLogin();

    // Stop early when the app has no working Supabase configuration.
    if (!SupabaseService.isReady) return _configurationMessage();

    // Convert `admin` to the server account email or normalize a LIMU email.
    final email = normalizedLoginIdentifier(identifier);

    // Show a direct input message instead of sending an invalid request.
    if (email == null) {
      return _remember('Use your full @limu.edu.ly email or the Admin name.');
    }

    // The existing Admin test password is six characters long.
    if (!isValidPassword(password)) {
      return _remember('Password must be at least 6 characters.');
    }

    try {
      // Ask Supabase to verify the email and password.
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      // A protected page needs both an Auth user and a saved session.
      if (response.user == null || response.session == null) {
        return _remember('The login session could not be created. Try again.');
      }

      // Load the matching profile before reporting login success.
      await _loadProfile(response.user!, attempts: 4);

      // Remember only the verified UID; Supabase securely owns the real token.
      await LoginPreferenceService.instance.saveLogin(response.user!.id);

      // Null tells the login screen that it may navigate to the dashboard.
      return null;
    } on sb.AuthException catch (error) {
      // Supabase Auth errors are translated into safe, useful wording.
      return _remember(_friendlyAuthError(error));
    } on _ProfileProblem catch (error) {
      // An invalid profile must never keep a half-open Auth session.
      await _signOutRejectedSession();

      // Return the exact safe profile problem to the form.
      return _remember(error.message);
    } on sb.PostgrestException catch (_) {
      // A failed profile query must not leave a partial persisted session.
      await _signOutRejectedSession();

      // A database/network failure is different from incorrect credentials.
      return _remember('Your account profile could not be loaded. Try again.');
    } catch (_) {
      // Close any session that may have been created before an unknown failure.
      await _signOutRejectedSession();

      // Unknown SDK details are intentionally not shown to students.
      return _remember('Unable to sign in right now. Please try again.');
    }
  }

  // Create a normal Student account and immediately load its active session.
  // Public signup never sends an Admin role from the phone.
  Future<String?> signUp(String fullName, String email, String password) async {
    // Clear values left by an earlier request.
    lastMessage = null;
    requiresEmailConfirmation = false;
    isPasswordRecovery = false;

    // Public registration starts without a profile from an older account.
    _currentUser = null;

    // Public signup also starts without an old device login marker.
    await LoginPreferenceService.instance.clearLogin();

    // Stop early if Supabase did not initialize.
    if (!SupabaseService.isReady) return _configurationMessage();

    // Normalize each public value before it leaves the device.
    final cleanName = normalizedRegistrationFullName(fullName);
    final cleanEmail = normalizedLimuLoginEmail(email);

    // Give the student direct validation feedback.
    if (cleanName == null) {
      return _remember('Full name must contain 2-100 normal characters.');
    }

    // Only the university domain may create public Student accounts.
    if (cleanEmail == null) {
      return _remember('Please use your full @limu.edu.ly email address.');
    }

    // New Student passwords use the stronger registration rule.
    if (!isValidNewPassword(password)) {
      return _remember('Use 8-128 characters with a letter and number.');
    }

    try {
      // Ask Supabase Auth to create the account.
      final response = await _client.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {'full_name': cleanName},
        emailRedirectTo: SupabaseConfig.authRedirectUrl,
      );

      // A missing Auth user means account creation did not complete.
      if (response.user == null) {
        return _remember('The Student account could not be created.');
      }

      // Some Supabase projects require the student to confirm an email first.
      if (response.session == null) {
        requiresEmailConfirmation = true;
        lastMessage =
            'Account created. Check your LIMU email, then sign in here.';
        return null;
      }

      // The database trigger creates the profile. Short retries cover the tiny
      // delay that can occur between the Auth response and the first row read.
      await _loadProfile(
        response.user!,
        requiredRole: AppUser.studentRole,
        attempts: 8,
      );

      // A completed signup is also a successful verified Student login.
      await LoginPreferenceService.instance.saveLogin(response.user!.id);

      // At this point Auth, session, and active Student profile all exist.
      return null;
    } on sb.AuthException catch (error) {
      // Show a safe Auth message such as "account already exists".
      return _remember(_friendlyAuthError(error));
    } on _ProfileProblem catch (error) {
      // Remove the partial local session if its profile is unsafe or missing.
      await _signOutRejectedSession();
      return _remember(error.message);
    } on sb.PostgrestException catch (_) {
      // A failed trigger-row read must not keep a half-open signup session.
      await _signOutRejectedSession();

      // Keep SQL and policy details private while giving a useful retry action.
      return _remember(
        'The account was created, but its profile could not be loaded. Try signing in.',
      );
    } catch (_) {
      // Close any session created before an unexpected SDK failure.
      await _signOutRejectedSession();

      // Unknown provider details should not be printed in the user interface.
      return _remember('Unable to create the account right now. Try again.');
    }
  }

  // Restore a previous login only when SharedPreferences and Supabase agree.
  // A saved boolean alone never grants access; the server profile is rechecked.
  Future<AppUser?> restoreSavedLogin() async {
    // Begin without trusting a profile left in process memory.
    _currentUser = null;
    lastMessage = null;
    requiresEmailConfirmation = false;

    // A password-recovery session must always open the reset page instead.
    if (isPasswordRecovery) return null;

    // Read the harmless UID marker saved after the previous successful login.
    final savedUserId = await LoginPreferenceService.instance.readSavedUserId();

    // No explicit marker means startup should show the normal Login page.
    if (savedUserId == null) return null;

    // A configured and initialized backend is required for session validation.
    if (!SupabaseService.isReady) {
      await LoginPreferenceService.instance.clearLogin();
      return null;
    }

    // Supabase Flutter restores its protected session from secure SDK storage.
    final session = _client.auth.currentSession;
    final authUser = _client.auth.currentUser;

    // Both sources must identify exactly the same account before any routing.
    if (session == null || authUser == null || authUser.id != savedUserId) {
      await _signOutRejectedSession();
      return null;
    }

    try {
      // Re-read account status, role, and block state from the live database.
      await _loadProfile(authUser, attempts: 3);

      // Refresh the safe marker in case platform storage migrated successfully.
      await LoginPreferenceService.instance.saveLogin(authUser.id);

      // Startup may now choose the Student or Admin destination from this role.
      return _currentUser;
    } on _ProfileProblem catch (error) {
      // Missing, blocked, inactive, or mismatched accounts fail closed.
      lastMessage = error.message;
      await _signOutRejectedSession();
      return null;
    } on sb.PostgrestException catch (_) {
      // A temporary profile read failure opens Login without trusting stale data.
      lastMessage = 'Your saved login could not be checked. Please sign in.';
      _currentUser = null;
      return null;
    } catch (_) {
      // Unknown startup failures are handled safely without showing SDK details.
      lastMessage = 'Your saved login could not be restored. Please sign in.';
      _currentUser = null;
      return null;
    }
  }

  // Recheck the real saved session and profile before a protected route opens.
  // Network failures are thrown so RoleGuard can show Retry instead of falsely
  // telling a signed-in user that they are logged out.
  Future<AppUser?> refreshCurrentUser() async {
    // No configured backend means there can be no trusted account.
    if (!SupabaseService.isReady) {
      _currentUser = null;
      await LoginPreferenceService.instance.clearLogin();
      return null;
    }

    // Read both parts of the persisted Supabase session.
    final session = _client.auth.currentSession;
    final authUser = _client.auth.currentUser;

    // Only a genuinely missing session redirects to Login.
    if (session == null || authUser == null) {
      _currentUser = null;
      await LoginPreferenceService.instance.clearLogin();
      return null;
    }

    try {
      // Query and validate the profile belonging to this exact Auth identity.
      await _loadProfile(authUser, attempts: 3);

      // Keep the harmless local marker aligned with the verified SDK session.
      await LoginPreferenceService.instance.saveLogin(authUser.id);

      // Return the newly checked application profile.
      return _currentUser;
    } on _ProfileProblem catch (error) {
      // A missing, blocked, inactive, or mismatched profile is not usable.
      lastMessage = error.message;
      await _signOutRejectedSession();
      return null;
    }
  }

  // Send a privacy-preserving password-recovery email.
  Future<String?> sendPasswordResetEmail(String email) async {
    // Normalize and validate the university email first.
    final cleanEmail = normalizedLimuLoginEmail(email);

    // An invalid public value does not need a network request.
    if (cleanEmail == null) {
      return _remember('Please use your full @limu.edu.ly email address.');
    }

    // Stop when the backend is unavailable.
    if (!SupabaseService.isReady) return _configurationMessage();

    try {
      // Supabase sends a secure link back to the configured app URL.
      await _client.auth.resetPasswordForEmail(
        cleanEmail,
        redirectTo: SupabaseConfig.authRedirectUrl,
      );

      // Always use privacy-preserving wording, even for an unknown email.
      lastMessage =
          'If that LIMU account exists, a password reset email was sent.';
      return null;
    } on sb.AuthException catch (error) {
      // Translate rate limits and other known Auth errors.
      return _remember(_friendlyAuthError(error));
    } catch (_) {
      // Keep raw network errors out of the public screen.
      return _remember('Unable to send the reset email right now.');
    }
  }

  // Replace the password during a valid Supabase recovery session.
  Future<String?> updateRecoveredPassword(String password) async {
    // New passwords use the same strong rule as signup.
    if (!isValidNewPassword(password)) {
      return _remember('Use 8-128 characters with a letter and number.');
    }

    // Both the recovery event and its short-lived session must exist.
    if (!SupabaseService.isReady ||
        !isPasswordRecovery ||
        _client.auth.currentSession == null) {
      return _remember('This recovery link is invalid or expired.');
    }

    try {
      // Ask Supabase to securely replace the password.
      await _client.auth.updateUser(sb.UserAttributes(password: password));

      // Sign out so the student proves the new password on the normal form.
      await _client.auth.signOut();

      // Clear local values from the finished recovery session.
      _currentUser = null;
      isPasswordRecovery = false;

      // A completed password reset must return to a clean Login page.
      await LoginPreferenceService.instance.clearLogin();

      // Remove study choices that belonged to the recovery account.
      await _clearAccountData();

      lastMessage = 'Password updated. Sign in with your new password.';
      return null;
    } on sb.AuthException catch (error) {
      // Use the same safe translation as other Auth requests.
      return _remember(_friendlyAuthError(error));
    } catch (_) {
      // Expired links and network failures receive one clear recovery action.
      return _remember('Unable to update the password. Request a new link.');
    }
  }

  // Sign out and remove the local profile from this device.
  Future<void> signOut() async {
    // Clear the local value first so no later widget can read stale access.
    _currentUser = null;
    requiresEmailConfirmation = false;
    isPasswordRecovery = false;

    // Remove the safe stay-signed-in marker before any network operation.
    await LoginPreferenceService.instance.clearLogin();

    // Clear the previous account's in-memory and saved academic path.
    await _clearAccountData();

    // There is nothing else to do when Supabase is not initialized.
    if (!SupabaseService.isReady) return;

    try {
      // Supabase removes its persisted tokens from the device.
      await _client.auth.signOut();
    } catch (_) {
      // Local sign-out remains complete when the network is temporarily down.
    }
  }

  // Profile editing screens call this after the database confirms an update.
  // It is a plain assignment and deliberately does not notify a state package.
  void replaceCurrentUser(AppUser user) {
    // Only replace the profile for the same authenticated identity.
    if (_client.auth.currentUser?.id == user.uid) _currentUser = user;
  }

  // Focused widget tests can supply a local profile without a real network.
  void setCurrentUserForTesting(AppUser? user) {
    // The method is intentionally tiny and is never called by production UI.
    _currentUser = user;
  }

  // Read, validate, and store the profile associated with one Auth user.
  Future<void> _loadProfile(
    sb.User authUser, {
    String? requiredRole,
    required int attempts,
  }) async {
    // Auth must contain a complete LIMU identity.
    final authEmail = normalizedLimuLoginEmail(authUser.email);
    if (authEmail == null) {
      throw const _ProfileProblem(
        'PeerStudy needs a complete @limu.edu.ly account.',
      );
    }

    // Start without a row and retry only when the trigger row is not visible yet.
    Map<String, dynamic>? data;

    // Keep the retry loop short and easy to understand.
    for (var attempt = 0; attempt < attempts; attempt++) {
      // RLS allows an authenticated user to read only the matching profile.
      data = await _client
          .from('profiles')
          .select()
          .eq('id', authUser.id)
          .maybeSingle();

      // Stop retrying as soon as the row appears.
      if (data != null) break;

      // Give the database trigger a moment before the next read.
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(Duration(milliseconds: 180 * (attempt + 1)));
      }
    }

    // A real session without its matching profile is not authorized.
    if (data == null) {
      throw const _ProfileProblem(
        'Your account profile is missing. Please contact an administrator.',
      );
    }

    // Explain common server-controlled restrictions clearly.
    if (data['is_blocked'] == true) {
      throw const _ProfileProblem(
        'Your account is blocked. Please contact an administrator.',
      );
    }

    // Inactive accounts cannot use protected application features.
    if (data['status'] != AppUser.activeStatus) {
      throw const _ProfileProblem(
        'Your account is inactive. Please contact an administrator.',
      );
    }

    // Verify identity, role, lifecycle, and profile data together.
    if (!profileCanOpenProtectedSession(
      data,
      authUid: authUser.id,
      authEmail: authEmail,
    )) {
      throw const _ProfileProblem(
        'Your account profile could not be verified.',
      );
    }

    // Convert the verified row into the ordinary application model.
    final profile = AppUser.fromSupabase(
      data,
      expectedUid: authUser.id,
      expectedEmail: authEmail,
    );

    // Signup is Student-only even if a server was accidentally misconfigured.
    if (requiredRole != null && profile.role != requiredRole) {
      throw const _ProfileProblem(
        'Public signup can create Student accounts only.',
      );
    }

    // Store the profile only after every check succeeds.
    _currentUser = profile;
    lastMessage = null;
  }

  // Remove an invalid partial Auth session without exposing SDK details.
  Future<void> _signOutRejectedSession() async {
    // Local state closes immediately.
    _currentUser = null;

    // Rejected server state must never leave an automatic-login marker.
    await LoginPreferenceService.instance.clearLogin();

    // A rejected identity must not leave its academic choices for another user.
    await _clearAccountData();

    try {
      // Remove the persisted Supabase session too.
      await _client.auth.signOut();
    } catch (_) {
      // The local account remains closed if the network sign-out fails.
    }
  }

  // Clear the small pieces of device state that belong to one account.
  Future<void> _clearAccountData() async {
    // Remove the in-memory Area, Department, and Subject values immediately.
    StudentSelectionStore.instance.clear();

    // Remove the same account-specific path from the local settings snapshot.
    await SettingsNotifier.instance.clearAccountSelection();
  }

  // Save one safe form message and return the same value to the caller.
  String _remember(String message) {
    // Screens may inspect the latest message after a route check.
    lastMessage = message;

    // Returning the value keeps each form method beginner-friendly.
    return message;
  }

  // Explain a missing or failed public Supabase setup without revealing keys.
  String _configurationMessage() {
    // Distinguish an absent configuration from a failed connection.
    return _remember(
      SupabaseService.isConfigured
          ? 'PeerStudy could not connect. Please try again.'
          : 'PeerStudy is not configured for this build.',
    );
  }

  // Convert common Supabase Auth errors into short student-facing messages.
  String _friendlyAuthError(sb.AuthException error) {
    // Error codes are safer and more stable than displaying raw SDK text.
    final code = error.code?.toLowerCase();
    final message = error.message.toLowerCase();

    // Incorrect credentials are the most common login failure.
    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }

    // This supports projects that later turn email confirmation back on.
    if (code == 'email_not_confirmed' ||
        message.contains('email not confirmed')) {
      return 'Confirm your LIMU email before signing in.';
    }

    // Signup should clearly explain an existing university account.
    if (code == 'user_already_exists' ||
        message.contains('already registered')) {
      return 'An account already exists for this LIMU email.';
    }

    // Supabase protects email endpoints with request rate limits.
    if (code == 'over_email_send_rate_limit' || error.statusCode == '429') {
      return 'Too many requests. Wait a moment, then try again.';
    }

    // Keep password feedback aligned with the visible signup rule.
    if (code == 'weak_password') {
      return 'Use 8-128 characters with a letter and number.';
    }

    // Unknown provider internals are never printed in the interface.
    return 'The account request could not be completed. Please try again.';
  }
}

// A private typed exception separates unsafe profile data from network errors.
class _ProfileProblem implements Exception {
  // Store only the friendly message that a screen is allowed to display.
  const _ProfileProblem(this.message);

  // The message describes a missing, blocked, inactive, or mismatched profile.
  final String message;
}
