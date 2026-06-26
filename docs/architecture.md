# Simple App Structure

Last updated: 2026-06-26

The app no longer follows a clean architecture folder style. It uses a simpler
Flutter layout that is easier for beginners to navigate.

## Folder Layout

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
```

## Folder Purpose

- `main.dart`: starts the app and connects Firebase, Riverpod, theme, and routes.
- `screens/`: full pages that users can open.
- `components/`: small reusable widgets used by more than one screen.
- `providers/`: Riverpod state and actions.
- `models/`: simple data classes.
- `services/`: Firebase and other external setup helpers.
- `routes/`: route names and route-to-screen mapping.
- `theme/`: shared colors and Material styling.
- `utils/`: small helper functions such as validators.

## Current Flow

1. `main.dart` starts the app.
2. `FirebaseService` tries to initialize Firebase.
3. `PeerStudyApp` opens `MaterialApp`.
4. `AppRouter` opens `SplashScreen` for `/`.
5. `SplashScreen` checks auth state with Riverpod.
6. The user is sent to landing, student, moderator, or admin screens.

## Why This Structure

This project is still early and is being built as a student app. A simple folder
structure is easier to explain, easier to debug, and faster to grow while the
main product screens are still being created.

If the app becomes much larger later, the team can introduce more structure
gradually, but the current priority is readable beginner-friendly Flutter code.
