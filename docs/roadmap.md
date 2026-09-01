# Roadmap and acceptance checklist

The corrected source, hosted backend, and APK are implemented. Completed items
below have current evidence; unchecked items still need an external AI key or a
physical-phone/manual acceptance action.

## Milestone 1: source consistency

- [x] Confirm every Flutter query uses the final migration column names and statuses.
- [x] Confirm every Flutter RPC parameter matches its SQL function signature.
- [x] Confirm Edge Function request and response fields match the plain quiz controller.
- [x] Remove unreachable legacy files and packages.
- [x] Keep source names and comments understandable to a beginning Flutter student.
- [x] Pass formatting, analysis, and the complete Flutter test suite (57/57).

## Milestone 2: hosted Supabase setup

- [x] Confirm the intended project reference before writing.
- [x] Apply the migration and corrected reference seed.
- [x] Verify all client-facing tables have Row Level Security enabled.
- [x] Verify the `subject-materials` bucket is private and limited to PDFs of at most 25 MiB.
- [x] Verify the `community-attachments` bucket is private, limited to five
  validated types and 10 MiB per object, with at most three files per target.
- [x] Confirm both native recovery redirects are allowed.
- [x] Supply a genuine `AI_API_KEY` secret (`gemini-3.5-flash` with a
  `gemini-3.1-flash-lite` fallback is configured).
- [x] Deploy `generate-quiz` and `submit-quiz` with JWT verification.
- [x] Deploy attachment finalization and cleanup with JWT verification.
- [x] Provision `admin@limu.edu.ly` as an active Admin for the supervised test.
- [x] Remove the old account from the confirmed project and verify clean state.

## Milestone 3: functional acceptance

- [x] TC1 — Fresh LIMU Student registration creates one active Student profile.
- [ ] TC2 — Valid Student login reaches Student home; invalid credentials do not.
- [x] TC3 — Active Admin authentication and role authorization pass; route guards are tested.
- [x] TC4 — Restricted profiles cannot use protected backend data, including an existing token.
- [x] TC5 — Student browses the complete hosted academic hierarchy and Subject data.
- [ ] TC6 — Admin creates/updates catalog entries; Subject creation also creates one Community.
- [ ] TC7 — Admin uploads, replaces, edits, and removes a real approved PDF.
- [ ] TC8 — Student opens the approved PDF in the internal viewer with page and zoom controls.
- [x] TC9 — Student selects one approved material and receives exactly ten real AI questions.
- [x] TC10 — Exit confirmation is covered in Flutter tests; trusted hosted submission returns score and corrections.
- [x] TC11 — Students create/edit/remove their own posts and comments with real counts and timestamps.
- [x] TC11A — Post and Comment attachments pass real upload, server validation,
  eligible read, retry-safe removal, cross-user denial, and physical cleanup.
- [x] TC12 — Student privately reports exactly one post or comment.
- [ ] TC13 — Admin separately verifies dismiss, remove, and restrict report actions.
- [ ] TC14 — Password recovery deep link returns to the app and allows a new password.

## Milestone 4: phone handoff

- [x] Build `build/app/outputs/flutter-apk/app-release.apk` from the accepted source.
- [x] Record the APK SHA-256 checksum in the repository audit.
- [ ] Install the APK on a physical Android phone.
- [ ] Repeat the main Student and Admin flows on mobile data or normal Wi-Fi.
- [ ] Record phone model, Android version, date, and any failures.
- [x] Copy the final APK to `PeerStudy-phone-test.apk`.

## Milestone 5: requirements before real deployment

The simple credential and test signing approach are suitable only for the requested supervised test. A real deployment additionally requires:

- unique strong Admin credentials and removal of published test credentials;
- an owner-controlled Android signing key and protected signing workflow;
- separate development and real-data Supabase projects;
- database backup and restore exercises;
- logging, alerting, rate-limit review, and incident ownership;
- legal review of privacy, terms, data retention, and external AI processing;
- accessibility and representative-device testing;
- performance and concurrency measurements against stated targets;
- dependency and security review; and
- a rollback procedure for database, functions, and app releases.

No roadmap checkbox should be marked complete without a linked command result or test record from the current source revision.
