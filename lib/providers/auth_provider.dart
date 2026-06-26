// Riverpod auth state for PeerStudy.
// This file is the bridge between the UI screens and Firebase Auth/Firestore:
// screens call simple methods here instead of talking to Firebase directly.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peerstudy/models/app_user.dart';
import 'package:peerstudy/services/firebase_service.dart';

// Stores the current loading/error state for auth-related screens.
// The splash screen reads this to know if it should wait before redirecting.
final authStateProvider = StateProvider<AuthState>(
  (ref) => const AuthState.initial(),
);

// Stores the signed-in user profile after it is loaded from Firestore.
// A null value means the app should treat the person as signed out.
final currentUserProvider = StateProvider<AppUser?>((ref) => null);

// Exposes auth actions such as login, signup, reset, and logout.
// UI widgets read the notifier to run actions, then react to the returned result.
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);

class AuthState {
  const AuthState({required this.isLoading, this.error});
  const AuthState.initial() : isLoading = true, error = null;

  final bool isLoading;
  final String? error;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this.ref) : super(const AuthState.initial());

  final Ref ref;

  fb.FirebaseAuth get _auth => fb.FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // Checks the saved Firebase session and loads the profile when possible.
  // This runs from the splash screen so returning users can skip the landing
  // page and go straight to the correct dashboard.
  Future<void> initialize() async {
    if (!FirebaseService.isReady) {
      ref.read(currentUserProvider.notifier).state = null;
      state = const AuthState(isLoading: false);
      return;
    }

    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      await _loadUserProfile(currentUser.uid);
    }
    state = const AuthState(isLoading: false);
  }

  // Reads the app user profile and signs out blocked users.
  // Firebase Auth only knows identity; Firestore tells us the role, selected
  // major details, and whether the account is blocked.
  Future<void> _loadUserProfile(String uid) async {
    try {
      final snapshot = await _firestore.collection('users').doc(uid).get();
      if (snapshot.exists) {
        final user = AppUser.fromFirestore(snapshot);
        if (user.isBlocked) {
          await signOut();
          state = AuthState(
            isLoading: false,
            error: 'Your account has been restricted.',
          );
          return;
        }
        ref.read(currentUserProvider.notifier).state = user;
      }
    } catch (e) {
      state = AuthState(
        isLoading: false,
        error: 'Failed to load account profile.',
      );
    }
  }

  // Signs in with Firebase Auth and then loads the matching Firestore profile.
  // The method returns null on success or a message the screen can show in a
  // SnackBar when something goes wrong.
  Future<String?> signIn(String email, String password) async {
    if (!FirebaseService.isReady) {
      return 'Firebase is not ready for this platform yet. Please check the Firebase setup.';
    }

    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _loadUserProfile(result.user!.uid);
      if (ref.read(currentUserProvider)?.isBlocked ?? false) {
        await signOut();
        return 'Your account has been restricted.';
      }
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return e.message ?? 'Could not sign in. Please try again.';
    } catch (_) {
      return 'Something went wrong while signing in.';
    }
  }

  // Creates a student account and saves the first profile document.
  // New public signups always become students; moderator and admin accounts
  // should be created separately by trusted project owners.
  Future<String?> signUp(String fullName, String email, String password) async {
    if (!FirebaseService.isReady) {
      return 'Firebase is not ready for this platform yet. Please check the Firebase setup.';
    }

    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final now = DateTime.now();
      final user = AppUser(
        uid: result.user!.uid,
        fullName: fullName,
        email: email,
        role: 'student',
        majorId: '',
        departmentId: '',
        yearId: '',
        isBlocked: false,
        createdAt: now,
        updatedAt: now,
      );
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(user.toFirestore());
      ref.read(currentUserProvider.notifier).state = user;
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return e.message ?? 'Could not create account. Please try again.';
    } catch (_) {
      return 'Something went wrong while creating your account.';
    }
  }

  // Sends a reset link to the student's LIMU email address.
  // Firebase handles the email itself, while the screen only needs to show
  // whether the request was accepted.
  Future<String?> sendPasswordResetEmail(String email) async {
    if (!FirebaseService.isReady) {
      return 'Firebase is not ready for this platform yet. Please check the Firebase setup.';
    }

    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return e.message ?? 'Unable to send password reset email.';
    } catch (_) {
      return 'Something went wrong while sending reset email.';
    }
  }

  // Clears Firebase and local Riverpod auth state.
  // Keeping both in sync prevents old user information from staying visible
  // after logout.
  Future<void> signOut() async {
    if (FirebaseService.isReady) {
      await _auth.signOut();
    }
    ref.read(currentUserProvider.notifier).state = null;
  }
}
