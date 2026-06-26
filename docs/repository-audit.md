# Repository Audit

Last audited: 2026-06-26

## Summary

The repository now contains a simple Flutter PeerStudy app shell. It is no longer
organized with `core/` and `features/` clean-architecture folders. The app uses a
beginner-friendly layout with screens, components, providers, models, services,
routes, theme, and utils.

## Current Project State

- Git branch: `main`.
- App entry point: `lib/main.dart`.
- Current UI: PeerStudy splash, landing, auth forms, role dashboards, settings,
  policy, support, and about screens.
- Current state management: Riverpod.
- Current backend packages: Firebase Core, Firebase Auth, and Cloud Firestore.
- Current test coverage: app startup smoke test in `test/widget_test.dart`.
- CI: Flutter quality workflow in `.github/workflows/flutter_quality.yml`.

## Current `lib/` Layout

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

## Folder Notes

- `screens/`: full app pages. Most new visible features start here.
- `components/`: reusable widgets such as app buttons, form fields, loading
  views, empty states, and error states.
- `providers/`: Riverpod state and actions. Auth currently lives here.
- `models/`: simple data objects such as `AppUser`.
- `services/`: setup helpers such as Firebase initialization.
- `routes/`: route names and route-to-screen mapping.
- `theme/`: shared colors and Material styling.
- `utils/`: helper functions such as validators.

## Verified Commands

These commands should pass before every push:

```powershell
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Remaining Gaps

- Firebase configuration has not been generated yet.
- The student academic path screens are not implemented yet.
- Lecture PDFs, AI quizzes, chat, peer posts, and reports are still future
  features.
- Firebase security rules still need to be designed before real data writes.
- The current dashboards are placeholders for role-based navigation.

## Recommended Next Steps

1. Add FlutterFire configuration for the Firebase project.
2. Build the student major, department/year, subject, and concept screens.
3. Add Firestore collections and security rules.
4. Replace dashboard placeholders with real feature screens.
5. Add tests for validators, auth flow, and navigation.
