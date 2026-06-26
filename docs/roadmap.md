# PeerStudy Roadmap

Last updated: 2026-06-25

## Phase 0 - Repository Foundation

- [x] Initialize a local Git repository.
- [x] Capture the Flutter starter project baseline.
- [x] Review the project PDF brief.
- [x] Add professional documentation.
- [x] Add Flutter quality workflow.

## Phase 1 - App Shell

- [x] Replace the counter app with a PeerStudy app shell.
- [ ] Add app theme, routing, and shared layout components.
- [ ] Update app display names and metadata.
- [ ] Add product-focused smoke tests.

## Phase 2 - Authentication

- [ ] Configure Firebase for target platforms.
- [ ] Add student registration with `@limu.edu.ly` validation.
- [ ] Add login, logout, and password reset.
- [ ] Add role loading for student, moderator, and admin.
- [ ] Add blocked-account handling.

## Phase 3 - Academic Navigation

- [ ] Model majors, academic years, departments, subjects, and concepts.
- [ ] Build major selection.
- [ ] Build conditional department or year routing.
- [ ] Build subject and concept screens.
- [ ] Add empty-state and loading-state tests.

## Phase 4 - Lecture Materials

- [ ] Select a PDF viewer package.
- [ ] Add lecture metadata model.
- [ ] Add lecture list and PDF viewing.
- [ ] Add download or cache behavior.
- [ ] Add missing-file and network-error handling.

## Phase 5 - AI Quiz

- [ ] Select AI provider and request gateway.
- [ ] Define prompt and context boundary rules.
- [ ] Parse AI output into typed quiz questions.
- [ ] Build quiz flow, scoring, and feedback.
- [ ] Add timeout and malformed-response handling.

## Phase 6 - Peer Community

- [ ] Build concept-level post and comment feed.
- [ ] Build real-time chat or discussion thread behavior.
- [ ] Add media upload progress and retry behavior.
- [ ] Add peer explanation video playback.
- [ ] Add user ownership controls.

## Phase 7 - Moderation

- [ ] Add report creation from posts, comments, and messages.
- [ ] Build admin reports dashboard.
- [ ] Add remove content, dismiss report, and block user actions.
- [ ] Add moderator lecture material management.
- [ ] Add audit trail fields for admin actions.

## Phase 8 - Release Readiness

- [ ] Finalize Firebase security rules.
- [ ] Run emulator-backed integration tests.
- [ ] Add privacy policy and support contact screens.
- [ ] Confirm performance targets for chat and media.
- [ ] Prepare store assets and release configuration.

## Deferred Scope

- Gamification features such as badges, leaderboards, and study streaks.
- Full offline mode.
- Advanced personalization.
- Multi-university support.
