# PeerStudy architecture

## Design goal

PeerStudy keeps the Flutter code easy to follow while enforcing important rules on the server. The phone presents the workflow; Supabase verifies identity, role, status, ownership, and data relationships.

## Roles and route decisions

There are exactly two roles:

| Profile state | Destination |
| --- | --- |
| active Student | Student home |
| active Admin | Admin dashboard |
| restricted account | Access denied |
| missing or invalid profile | Fail closed and sign out |

Students can create their own account only with a normalized `@limu.edu.ly` email. Admin accounts are pre-created by the project owner. The profile trigger ignores any public attempt to request the Admin role.

## Runtime components

| Component | Responsibility |
| --- | --- |
| Flutter StatefulWidget and setState | Screens, navigation, form state, and readable user feedback |
| Supabase Auth | Email/password sessions and password recovery |
| PostgreSQL | Authoritative application data and transactions |
| Row Level Security | Per-row Student/Admin permissions |
| Private Storage | Approved PDFs and private Community attachment bytes |
| Realtime | New and changed Community posts, comments, and attachment metadata |
| Edge Functions | AI quizzes, trusted scoring, attachment validation, and file cleanup |
| Device storage | Theme and other non-authoritative preferences |

## Domain model

```text
School 1--* AcademicArea 1--* Department 1--* Subject
                                                   |
                                                   +--1 Community
                                                   +--* SubjectMaterial
                                                   +--* Quiz --* QuizAttempt

Community 1--* CommunityPost 1--* CommunityComment
                     |                    |
                     +--* Attachment      +--* Attachment
Profile   1--* owned posts, comments, attempts, and reports
Report    *--1 exactly one target: post or comment
```

Important invariants are enforced in PostgreSQL:

- Roles are `student` or `admin`.
- Account states are `active` or `restricted`.
- Catalog rows are `active` or `inactive`.
- A Subject owns exactly one Community, using the same UUID.
- A report targets one post or one comment, never both.
- A quiz contains exactly ten validated questions.
- An attempt contains exactly ten answers and is scored once.
- A Student sees only approved materials under an active catalog path.
- PDF size is limited to 25 MiB.
- A post or comment has at most three ready/in-progress attachments.
- A Community attachment is at most 10 MiB and is one validated JPG, PNG,
  WebP, PDF, or UTF-8 text file.
- New reservations are limited to ten per Student per minute and 100 MiB of
  uncleaned private attachment bytes per Student.

## Authentication flow

```text
Launch
  -> show Login
  -> sign in or create a Student account
  -> receive a Supabase session
  -> load profiles row
  -> verify email, role, status, and UUID
  -> route to Student home or Admin dashboard
```

Every protected route refreshes the real session and profile before drawing its page. Row Level Security also rejects protected requests immediately when an Admin restricts an account, even if the phone still holds an earlier token. Password recovery returns through `io.supabase.peerstudy://login-callback`, registered on Android and iOS.

## Catalog and material flow

Admins manage the academic hierarchy. Subject creation calls `admin_create_subject_with_community`, so the Subject and Community are committed together.

For a material upload:

1. The Admin selects one PDF of at most 25 MiB.
2. A metadata row starts as `uploading`.
3. The app receives a signed upload token for one private path.
4. The app uploads the bytes and records their checksum.
5. The Admin-approved row becomes `approved`.
6. Students receive short-lived signed access only when Row Level Security permits the Subject.

The viewer opens the signed URL inside the app and supports scrolling, page movement, and zoom. It does not create a permanent Student library.

## Quiz trust boundary

`generate-quiz` accepts one active Subject, one approved material, and one UUID idempotency key. It downloads the PDF with server authority, calls the configured AI provider, and validates exactly ten questions with four choices each.

Correct answers remain in the protected `quizzes` row. The Flutter response contains only the information required to take the quiz.

`submit-quiz` accepts one quiz, exactly ten selected option indexes, and one UUID idempotency key. It performs trusted scoring, stores one attempt, and returns the score and corrections after submission.

## Community and report flow

Active Students create posts and comments through database functions. Each form
may also upload up to three private attachments. The server derives author
identity from the session, keeps real timestamps, updates comment counts, and
prevents cross-user edits.

An attachment first receives one owner-bound, idempotent reservation. Storage
accepts bytes only at that opaque path. `finalize-community-attachment` then
downloads the object with server authority, checks its exact size, stored MIME
type, real file signature/UTF-8 content, and SHA-256 checksum before marking it
ready. The app issues a 60-second signed URL only after an authorized tap.
Removal hides metadata first; protected cleanup then deletes inaccessible bytes.

A Student can privately report one active post or comment. Admins see pending and resolved reports and may dismiss the report, remove the reported content, or remove it and restrict the responsible Student. These actions are transactional and audited.

## Security boundaries

- The APK contains only the public project URL and publishable key.
- Service-role and AI credentials exist only in Supabase-managed server configuration.
- Row Level Security is enabled on every client-facing table.
- Privileged database functions verify `auth.uid()` and active role again.
- Both private Storage buckets follow the same catalog and profile rules.
- Idempotency keys prevent accidental duplicate quiz generation, submission,
  posts, comments, reports, and attachment reservations.
- Error messages sent to the phone do not expose server internals or credentials.

## Source layout

```text
lib/
  components/   shared beginner-friendly widgets
  config/       public Supabase connection values
  models/       Student-facing data objects
  providers/    small plain repositories/controllers (no state package)
  routes/       route names and role guards
  screens/      auth, Student, Admin, and profile pages
  services/     Supabase initialization and backend calls
  theme/        shared colors and typography
  utils/        validation helpers
supabase/
  migrations/   schema, functions, policies, Storage, Realtime
  functions/    quiz operations and Community attachment verification/cleanup
  seed.sql      corrected academic reference data
test/           Flutter unit and widget tests
```
