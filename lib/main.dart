// Entry point for the PeerStudy Flutter application.
// This file initializes Firebase and sets up the root widget.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/services/firebase_service.dart';
import 'core/theme/app_theme.dart';

// Starts Flutter, prepares Firebase when it is configured, then shows the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initializeFirebase();
  runApp(const ProviderScope(child: PeerStudyApp()));
}

class PeerStudyApp extends StatelessWidget {
  const PeerStudyApp({super.key});

  // Builds the root MaterialApp and connects it to the central router.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PeerStudy',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
