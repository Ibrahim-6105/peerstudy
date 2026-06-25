# PeerStudy

PeerStudy is a Flutter mobile application planned as a LIMU-focused collaborative
learning platform. The product vision is to help university students move from
isolated study and scattered messaging groups into structured academic spaces for
lecture resources, concept discussions, AI-assisted quizzes, and peer explanations.

Last audited: 2026-06-25

## Current Status

This repository currently contains a fresh Flutter scaffold with the default
counter app in `lib/main.dart`. The project brief, SRS, and software design
document have been reviewed from:

`C:\Users\betoe\Downloads\PeerStudy_Project_Document.pdf`

The PDF is treated as the product source of truth for the next implementation
phase. The extracted requirements are documented in `docs/`.

## Product Vision

PeerStudy is intended to provide:

- Verified student registration using official `@limu.edu.ly` email addresses.
- Role-based access for students, academic moderators, and admins.
- Context-based navigation through major, department or academic year, subject,
  and concept.
- Lecture material access, primarily PDF notes and slides.
- AI-generated concept quizzes constrained to official learning material.
- Concept-level peer discussion and chronological chat history.
- Peer posts, comments, and short explanation videos.
- Reporting, moderation, blocking, and content removal tools.

## Tech Stack

- Flutter for cross-platform app development.
- Dart SDK as provided by the active Flutter channel.
- Firebase Authentication for identity and session management.
- Cloud Firestore for academic structures, messages, reports, and metadata.
- Firebase Cloud Storage for lecture files and peer media.
- External AI API for quiz generation.
- Local cache storage planned for performance and selected offline support.

Only Flutter and the default scaffold dependencies are installed in the repo
today. Firebase, AI, PDF viewing, video, and local cache packages still need to be
selected during implementation.

## Getting Started

Install Flutter, then run:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

The current app runs as the starter counter application.

## Quality Checks

Use these checks before opening a pull request:

```powershell
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

The repository also includes a GitHub Actions workflow in
`.github/workflows/flutter_quality.yml` for formatting, analysis, and tests.

## Documentation Map

- `docs/project-brief.md` summarizes the reviewed project document.
- `docs/repository-audit.md` explains the current folder state and risks.
- `docs/architecture.md` describes the target technical architecture.
- `docs/roadmap.md` breaks the implementation into practical phases.
- `docs/contributing.md` defines workflow, commit, and review standards.

## Repository Layout

```text
lib/                  Flutter application source
test/                 Flutter widget and unit tests
android/              Android platform project
ios/                  iOS platform project
web/                  Web runner
windows/              Windows desktop runner
linux/                Linux desktop runner
macos/                macOS desktop runner
docs/                 Project documentation
.github/workflows/    Continuous integration workflows
```

## Important Notes

- The current implementation does not yet contain PeerStudy product features.
- The project document mentions both local SQLite caching and MySQL in different
  places. The backend persistence strategy should be finalized before feature
  development begins.
- The initial scope depends on active internet connectivity and does not include
  full offline mode or gamification.
