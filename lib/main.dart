// This is the small starting point for the PeerStudy Flutter application.
// The project intentionally uses StatefulWidget and setState instead of a
// state-management package so a beginner can follow the complete startup flow.

// `dart:async` supplies unawaited for a simple background settings read.
import 'dart:async';

// Material contains Flutter's standard application and screen widgets.
import 'package:flutter/material.dart';

// AppUser supplies the two trusted role names used for cold-start routing.
import 'package:peerstudy/models/app_user.dart';

// SettingsNotifier is one ordinary object that stores the selected theme.
import 'package:peerstudy/providers/settings_provider.dart';

// AuthService is one ordinary object that owns the Supabase login session.
import 'package:peerstudy/services/auth_service.dart';

// AppRouter maps simple route names to the application's screens.
import 'package:peerstudy/routes/app_router.dart';

// AppRoutes keeps every route-name string in one beginner-friendly file.
import 'package:peerstudy/routes/app_routes.dart';

// SupabaseService initializes the backend before a form can use it.
import 'package:peerstudy/services/supabase_service.dart';

// AppTheme contains the matching light and dark visual themes.
import 'package:peerstudy/theme/app_theme.dart';

// Flutter calls main once when the application process starts.
Future<void> main() async {
  // Flutter plugins need the binding before asynchronous initialization.
  WidgetsFlutterBinding.ensureInitialized();

  // Connect the single Supabase client using the public mobile configuration.
  await SupabaseService.initialize();

  // Show a safe setup screen when the configured backend cannot initialize.
  if (!SupabaseService.isReady) {
    runApp(const PeerStudyConfigurationErrorApp());
    return;
  }

  // Load the saved light/dark choice before painting the first Flutter frame.
  await SettingsNotifier.instance.load();

  // Start the small listener used by sign-out and password-recovery links.
  AuthService.instance.startListening();

  // Verify a harmless SharedPreferences marker against the real Supabase data.
  final restoredUser = await AuthService.instance.restoreSavedLogin();

  // A fresh or signed-out device always starts at the Login page.
  var firstRoute = AppRoutes.login;

  // A verified Student returns directly to the normal student application.
  if (restoredUser?.role == AppUser.studentRole) {
    firstRoute = AppRoutes.studentShell;
  }

  // A verified Admin returns directly to the management dashboard.
  if (restoredUser?.role == AppUser.adminRole) {
    firstRoute = AppRoutes.adminDashboard;
  }

  // Display the real application using only the route verified above.
  runApp(PeerStudyApp(initialRoute: firstRoute));
}

// This fallback avoids printing project URLs, keys, or raw SDK errors.
class PeerStudyConfigurationErrorApp extends StatelessWidget {
  // The widget has no changing local value, so it can be const.
  const PeerStudyConfigurationErrorApp({super.key});

  // Build one clear deployment/setup message.
  @override
  Widget build(BuildContext context) {
    // MaterialApp supplies the theme and normal phone text rendering.
    return MaterialApp(
      // This title may appear in the operating-system task switcher.
      title: 'PeerStudy setup required',

      // Remove the debug ribbon from phone-test builds.
      debugShowCheckedModeBanner: false,

      // Use the same visual style as the configured application.
      theme: AppTheme.lightTheme,

      // Scaffold gives the message a normal full-screen page.
      home: Scaffold(
        // SafeArea avoids phone notches and system bars.
        body: SafeArea(
          // Center keeps the short message readable on any screen size.
          child: Center(
            // Padding prevents text from touching a narrow phone edge.
            child: Padding(
              padding: EdgeInsets.all(18),
              // ConstrainedBox avoids an over-wide paragraph on tablets.
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 520),
                // Column groups the setup icon, title, and explanation.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The icon makes the setup state recognizable at a glance.
                    Icon(Icons.settings_outlined, size: 38),

                    // Add breathing space before the title.
                    SizedBox(height: 12),

                    // Explain the result without technical secrets.
                    Text(
                      'PeerStudy could not connect to its backend.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    // Separate the title from its simple action text.
                    SizedBox(height: 7),

                    // The project owner can check configuration or connectivity.
                    Text(
                      'Check the internet connection and app configuration, then reopen the app.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// PeerStudyApp uses only StatefulWidget and setState for the changing theme.
class PeerStudyApp extends StatefulWidget {
  // Tests may request a public page; a fresh real device defaults to Login.
  const PeerStudyApp({super.key, this.initialRoute = AppRoutes.login});

  // This route is used for the first page created by MaterialApp.
  final String initialRoute;

  // Create the small state object that listens to settings and recovery links.
  @override
  State<PeerStudyApp> createState() => _PeerStudyAppState();
}

// This state owns no business data; it only rebuilds the root after a theme edit.
class _PeerStudyAppState extends State<PeerStudyApp> {
  // Keep the exact callback object so dispose can remove it safely.
  late final VoidCallback _recoveryCallback;

  // Prevent the same recovery event from pushing duplicate reset pages.
  bool _recoveryPageIsOpening = false;

  // Register the two ordinary callbacks once when the root widget is created.
  @override
  void initState() {
    // Always let StatefulWidget perform its normal initialization first.
    super.initState();

    // Rebuild this root when SettingsNotifier stores a different theme.
    SettingsNotifier.instance.addListener(_settingsChanged);

    // Direct widget tests do not call main, so load settings there if necessary.
    if (SettingsNotifier.instance.state.isLoading) {
      unawaited(SettingsNotifier.instance.load());
    }

    // Store one stable callback for the Supabase password-recovery event.
    _recoveryCallback = _openRecoveryPage;

    // Give the auth service access to that small navigation callback.
    AuthService.instance.onPasswordRecovery = _recoveryCallback;

    // A recovery event may have arrived just before this widget was mounted.
    if (AuthService.instance.isPasswordRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRecoveryPage());
    }
  }

  // One setState call applies the saved light or dark preference.
  void _settingsChanged() {
    // Ignore a late storage callback after this widget was removed.
    if (!mounted) return;

    // No local assignment is needed because build reads the notifier snapshot.
    setState(() {});
  }

  // Open the new-password form from any currently visible screen.
  void _openRecoveryPage() {
    // Do not push twice while the same recovery event is being handled.
    if (_recoveryPageIsOpening) return;

    // Remember that navigation has been scheduled.
    _recoveryPageIsOpening = true;

    // Navigation must run after the current Flutter frame is complete.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The global navigator may not exist yet during the earliest startup event.
      final navigator = peerStudyNavigatorKey.currentState;

      // Allow a later callback to retry if the navigator is not mounted yet.
      if (navigator == null) {
        _recoveryPageIsOpening = false;
        return;
      }

      // Recovery replaces every prior page so Back cannot enter private content.
      navigator.pushNamedAndRemoveUntil(AppRoutes.resetPassword, (_) => false);

      // Keep the flag true until recovery succeeds or the root is recreated.
    });
  }

  // Remove callbacks when Flutter destroys the application widget in a test.
  @override
  void dispose() {
    // Stop theme callbacks from reaching a removed widget.
    SettingsNotifier.instance.removeListener(_settingsChanged);

    // Remove only the callback that belongs to this root instance.
    if (identical(AuthService.instance.onPasswordRecovery, _recoveryCallback)) {
      AuthService.instance.onPasswordRecovery = null;
    }

    // Finish normal StatefulWidget cleanup.
    super.dispose();
  }

  // Build the application themes and named navigation table.
  @override
  Widget build(BuildContext context) {
    // Read the latest plain settings snapshot.
    final settings = SettingsNotifier.instance.state.settings;

    // MaterialApp is the top-level container for every PeerStudy screen.
    return MaterialApp(
      // This key lets a recovery link navigate from any current page.
      navigatorKey: peerStudyNavigatorKey,

      // The operating system may display this app title.
      title: 'PeerStudy',

      // Use the shared theme files so every screen looks consistent.
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,

      // Remove the debug ribbon from local phone-test builds.
      debugShowCheckedModeBanner: false,

      // Apply readable status/navigation bar icons even on pages without AppBar.
      builder: (context, child) {
        // Choose the matching phone-bar colors from the active theme brightness.
        final overlayStyle = Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkSystemUiOverlayStyle
            : AppTheme.lightSystemUiOverlayStyle;

        // AnnotatedRegion updates Android/iOS system chrome with the page theme.
        return AnnotatedRegion(
          value: overlayStyle,
          child: child ?? const SizedBox.shrink(),
        );
      },

      // The production default is Login, as requested by the project owner.
      initialRoute: widget.initialRoute,

      // Build exactly one initial page instead of expanding slash route names.
      onGenerateInitialRoutes: (routeName) => <Route<dynamic>>[
        AppRouter.onGenerateRoute(RouteSettings(name: routeName)),
      ],

      // Send later named navigation requests to the central beginner router.
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}

// PeerStudy has one Navigator, so one global key is sufficient.
final GlobalKey<NavigatorState> peerStudyNavigatorKey =
    GlobalKey<NavigatorState>();
