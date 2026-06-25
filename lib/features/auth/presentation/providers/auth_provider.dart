// Auth provider and notifier for PeerStudy.
// Handles sign in, sign up, password reset, and user profile loading.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/firebase_service.dart';
import '../../domain/models/app_user.dart';

// Stores the current loading/error state for auth-related screens.
final authStateProvider = StateProvider<AuthState>(
  (ref) => const AuthState.initial(),
);

// Stores the signed-in user profile after it is loaded from Firestore.
final currentUserProvider = StateProvider<AppUser?>((ref) => null);

// Exposes auth actions such as login, signup, reset, and logout.
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
  Future<String?> signIn(String email, String password) async {
    if (!FirebaseService.isReady) {
      return 'Firebase is not configured yet. Run FlutterFire configuration first.';
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
  Future<String?> signUp(String fullName, String email, String password) async {
    if (!FirebaseService.isReady) {
      return 'Firebase is not configured yet. Run FlutterFire configuration first.';
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
  Future<String?> sendPasswordResetEmail(String email) async {
    if (!FirebaseService.isReady) {
      return 'Firebase is not configured yet. Run FlutterFire configuration first.';
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
  Future<void> signOut() async {
    if (FirebaseService.isReady) {
      await _auth.signOut();
    }
    ref.read(currentUserProvider.notifier).state = null;
  }
}
