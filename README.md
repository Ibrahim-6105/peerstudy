# PeerStudy

PeerStudy is a Flutter app for LIMU students. The goal is to give students one
organized place to sign in, find academic content, discuss subjects, and later
use features like AI quizzes, lecture files, peer posts, and moderation tools.

This repository is intentionally kept simple for learning. It does not use clean
architecture folders. The code is grouped by what beginners usually look for:
screens, components, providers, models, services, routes, theme, and utils.

## Current App Status

The app currently has:

- A splash screen that checks authentication state.
- Landing, login, signup, and forgot password screens.
- Student, moderator, and admin dashboard placeholders.
- Settings, privacy policy, terms, support, and about screens.
- Riverpod auth state connected to Firebase Auth and Firestore.
- A Firebase startup helper that lets the app run even before Firebase config is
  generated.
- A widget smoke test that confirms the app reaches the landing screen.

Firebase login/signup will only work after the real Firebase configuration is
added with FlutterFire. Until then, the app still opens and shows a friendly
setup message instead of crashing.

## How To Run

Run these commands from the project root:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Use these before pushing code:

```powershell
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Simple Folder Layout

```text
lib/
  main.dart
  components/
  models/
  providers/
  routes/
  screens/
  services/
  theme/
  utils/
test/
  widget_test.dart
```

### `lib/main.dart`

Start here first.

This file is the app entry point. It prepares Flutter, asks
`FirebaseService` to initialize Firebase, wraps the app in Riverpod's
`ProviderScope`, and opens `PeerStudyApp`.

`PeerStudyApp` creates the `MaterialApp`, attaches the app theme, and connects
navigation to `AppRouter`.

### `lib/routes/`

Read this second.

- `app_routes.dart` stores route names like `/login` and `/student-shell`.
- `app_router.dart` maps each route name to the screen widget Flutter should
  open.

When you add a new screen, usually you add a route name in `app_routes.dart` and
then add a case for it in `app_router.dart`.

### `lib/screens/`

Read this third.

Screens are full pages. They are grouped by the part of the app they belong to:

```text
screens/auth/       Splash, landing, login, signup, forgot password
screens/student/    Main student tab shell
screens/admin/      Admin dashboard placeholder
screens/moderator/  Moderator dashboard placeholder
screens/profile/    Settings, privacy, terms, support, about
```

Most beginner work will happen here because screens are where users see and tap
things.

### `lib/components/`

Reusable UI pieces live here.

- `app_button.dart` is the shared button with loading behavior.
- `app_form_field.dart` is the shared labeled text field.
- `loading_view.dart` is the shared loading spinner/message.
- `error_view.dart` is the shared error state.
- `empty_state_view.dart` is the shared empty state.

If the same widget is needed in more than one screen, put it in `components/`.

### `lib/providers/`

Riverpod state files live here.

`auth_provider.dart` handles:

- Auth loading state.
- Current signed-in user profile.
- Login.
- Signup.
- Password reset.
- Sign out.
- Loading the Firestore user profile.

Screens call this provider instead of calling Firebase directly. That keeps the
screens easier to read.

### `lib/models/`

Data objects live here.

`app_user.dart` describes the user profile saved in Firestore. It also has helper
methods for converting between Firestore documents and Dart objects.

### `lib/services/`

External setup and app services live here.

`firebase_service.dart` initializes Firebase and tracks whether Firebase is ready.
It is written to be gentle during early development: if Firebase config is
missing, the UI can still run.

### `lib/theme/`

`app_theme.dart` stores shared colors and Material styling. Change the app's
main look here instead of editing every screen separately.

### `lib/utils/`

Small helper functions live here.

`validators.dart` currently checks LIMU email addresses, password length, and
non-empty text.

### `test/widget_test.dart`

This is the first app test. It opens `PeerStudyApp`, waits for the splash screen
to redirect, and checks that the public landing screen appears.

## Beginner Reading Order

If you are new to this project, read files in this order:

1. `lib/main.dart`
2. `lib/routes/app_routes.dart`
3. `lib/routes/app_router.dart`
4. `lib/screens/auth/splash_screen.dart`
5. `lib/screens/auth/landing_screen.dart`
6. `lib/screens/auth/login_screen.dart`
7. `lib/providers/auth_provider.dart`
8. `lib/models/app_user.dart`
9. `lib/services/firebase_service.dart`
10. `lib/components/app_button.dart`
11. `lib/components/app_form_field.dart`
12. `test/widget_test.dart`

That order follows the real app flow: start app, choose route, show splash,
open public screens, call auth logic, read user data, and test startup.

## How The App Starts

1. `main()` runs.
2. Flutter bindings are prepared.
3. Firebase initialization is attempted.
4. Riverpod `ProviderScope` is added.
5. `PeerStudyApp` creates the `MaterialApp`.
6. The initial route `/` opens `SplashScreen`.
7. `SplashScreen` asks `auth_provider.dart` if a user is available.
8. The user is redirected to landing, student, moderator, or admin screens.

## How Login Works

1. `LoginScreen` validates email and password.
2. The screen calls `authNotifierProvider.notifier.signIn(...)`.
3. `AuthNotifier` asks Firebase Auth to sign in.
4. If sign-in succeeds, it loads the user's Firestore profile.
5. The screen checks the user's role.
6. The app opens the matching dashboard.

## How To Add A New Screen

Example: adding a subjects screen.

1. Create `lib/screens/student/subjects_screen.dart`.
2. Add a route name in `lib/routes/app_routes.dart`.
3. Add a matching case in `lib/routes/app_router.dart`.
4. Navigate with:

```dart
Navigator.pushNamed(context, AppRoutes.subjects);
```

## How To Add A New Reusable Widget

If a widget is used in two or more screens, put it in `lib/components/`.

Example names:

- `subject_card.dart`
- `section_title.dart`
- `profile_avatar.dart`
- `quiz_option_tile.dart`

Keep components small and give each one a short comment explaining what it is
for.

## Firebase Setup Reminder

The app has Firebase packages installed, but real Firebase login needs generated
configuration files.

Later, after a Firebase project is created, run:

```powershell
dart pub global activate flutterfire_cli
flutterfire configure
```

That usually generates `lib/firebase_options.dart`. After that, update
`FirebaseService.initializeFirebase()` to pass the generated options if needed.

## Notes For Future Features

- Put new pages in `screens/`.
- Put repeated UI in `components/`.
- Put Firebase or external setup code in `services/`.
- Put Riverpod state in `providers/`.
- Put simple data classes in `models/`.
- Keep comments friendly and useful. Explain why the file exists and what the
  main widget/function does.
