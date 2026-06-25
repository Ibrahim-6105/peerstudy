# Target Architecture

Last updated: 2026-06-25

## Current Reality

The repository currently contains a Flutter starter application. This document
describes the target architecture for the PeerStudy product described in the
project brief.

## Architecture Goals

- Keep UI, state, domain rules, and backend integrations separated.
- Make Firebase services replaceable behind repository interfaces.
- Keep role and permission checks explicit.
- Support concept-level academic context throughout the app.
- Make AI quiz generation traceable to approved study material.
- Prepare for testing from the first implemented feature.

## Proposed App Layers

```text
Presentation
  Flutter screens, widgets, navigation, forms, and feedback states

Application
  Use cases, controllers, state management, validation, and orchestration

Domain
  Entities, value objects, role rules, and product policies

Data
  Firebase repositories, local cache, AI gateway, media storage gateway
```

## Suggested Flutter Structure

```text
lib/
  app/
    peerstudy_app.dart
    router.dart
    theme.dart
  core/
    errors/
    result/
    validation/
  features/
    auth/
    academic_path/
    lectures/
    quizzes/
    community/
    moderation/
    profile/
    settings/
  shared/
    widgets/
    services/
```

## Role Model

- Student: can access academic content, post, comment, upload explanations, and
  report content.
- Academic moderator: can manage lecture material and guide discussion quality.
- Admin: can review reports, remove content, dismiss reports, and block users.

Role claims should be stored in a secure backend-controlled location, not trusted
from editable client state.

## Firebase Model Proposal

Firestore collections can start with this shape:

```text
users/{userId}
  fullName
  email
  role
  status
  createdAt

majors/{majorId}
  name
  pathType

majors/{majorId}/paths/{pathId}
  name
  type

majors/{majorId}/paths/{pathId}/subjects/{subjectId}
  name

subjects/{subjectId}/concepts/{conceptId}
  title
  description

concepts/{conceptId}/lectures/{lectureId}
  title
  storagePath
  uploadedBy
  updatedAt

concepts/{conceptId}/messages/{messageId}
  authorId
  body
  createdAt

concepts/{conceptId}/posts/{postId}
  authorId
  type
  body
  mediaPath
  createdAt

posts/{postId}/comments/{commentId}
  authorId
  body
  createdAt

reports/{reportId}
  reporterId
  targetType
  targetId
  reason
  status
  resolvedBy
  resolvedAt
```

The final schema should be refined against query patterns and Firebase security
rules before implementation.

## Storage Strategy

- Lecture PDFs: Firebase Cloud Storage with Firestore metadata.
- Peer videos: Firebase Cloud Storage with upload progress and failure handling.
- Thumbnails: generated or uploaded alongside video metadata.
- Local cache: selected PDFs and lightweight metadata only.

## AI Quiz Boundary

The AI service should receive only the approved concept material required for the
quiz. The app should store or display enough provenance to explain which material
was used.

Minimum safeguards:

- Generate exactly 10 questions per quiz request.
- Reject empty or unsupported source material.
- Time out failed AI requests cleanly.
- Parse AI responses into a typed quiz model.
- Display corrections and feedback after submission.
- Avoid sending student private data to the AI service.

## Security Expectations

- Require authentication for all personalized features.
- Validate `@limu.edu.ly` emails during student registration.
- Enforce role-based permissions in Firebase security rules.
- Allow students to edit or delete only their own content, unless an admin action
  applies.
- Keep admin accounts pre-created and protected from public registration.
- Store only password hashes through Firebase Authentication, never directly in
  Firestore.
- Use HTTPS for all backend and AI traffic.

## Testing Strategy

- Unit tests for validation, role rules, and domain mapping.
- Widget tests for forms, navigation, empty states, and error states.
- Repository tests with Firebase emulators or mocked gateways.
- Integration tests for login, academic navigation, posting, commenting, and
  reporting once Firebase is configured.

## Deployment Notes

The first production-like release should include:

- Firebase projects for development and production.
- Environment-specific configuration.
- CI checks for formatting, analysis, and tests.
- Security rules reviewed before enabling write access.
- App identifiers, icons, and display names updated from Flutter defaults.
