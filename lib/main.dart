// Main entry point for the PeerStudy Flutter app.
// Start reading here first: it prepares Flutter, tries to initialize Firebase,
// then opens the root widget that controls theme and navigation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerstudy/routes/app_router.dart';
import 'package:peerstudy/services/firebase_service.dart';
import 'package:peerstudy/theme/app_theme.dart';

// This function runs before any screen appears.
// Firebase is allowed to fail gracefully here so beginners can run the UI before
// adding real Firebase project files.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initializeFirebase();
  runApp(const ProviderScope(child: PeerStudyApp()));
}

class PeerStudyApp extends StatelessWidget {
  const PeerStudyApp({super.key});

  // The root widget is intentionally small.
  // It gives the whole app one theme, one route table, and removes the debug
  // banner so all screens feel like one connected application.
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
