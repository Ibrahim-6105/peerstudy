# Contributing to PeerStudy

PeerStudy is an educational Flutter project. Changes should remain easy for a beginning Flutter student to follow while preserving the server-enforced security rules.

## Before editing

1. Read [the project brief](project-brief.md) and [architecture](architecture.md).
2. Confirm the change belongs to Student or Admin use cases.
3. Check `git status` and preserve unrelated work.
4. Create a small branch with one clear purpose.

## Source style

- Prefer direct, descriptive names over abbreviations.
- Keep the `lib/` folder structure shallow.
- Use one obvious flow instead of unnecessary abstraction.
- Add plain-language comments that explain each meaningful line or small logical group to a beginner.
- Explain why a security check exists, not merely what the syntax says.
- Keep widgets small enough to understand without jumping through many files.
- Show safe, useful errors to users; do not display tokens, raw SQL errors, or internal stack traces.
- Format with Dart’s formatter instead of manual spacing.

Comments must stay accurate when behavior changes. A large block of copied comments that no longer matches the code is worse than a short precise explanation.

## Architecture rules

- Keep exactly two roles: `student` and `admin`.
- Public signup always produces a Student.
- Require a complete `@limu.edu.ly` email for every account.
- Treat `profiles.status` and Row Level Security as authoritative access control.
- Keep service-role and AI credentials out of Flutter.
- Put privileged or multi-row changes in database functions or Edge Functions.
- Keep PDF and Community attachment Storage private and issue only short-lived access.
- Keep correct quiz answers on the server until submission.
- Use exactly ten questions from one selected approved material.
- Keep Community attachments owner-bound, count/size limited, and validated from
  their real bytes on the server before they become readable.
- Keep reports private and targeted to exactly one post or comment.
- Use idempotency keys for retryable writes.

## Database changes

Create a new timestamped migration; do not silently edit a migration that has already been applied to a shared project.

Every new client-facing table needs:

- clear constraints and defaults;
- appropriate indexes;
- Row Level Security enabled;
- explicit read and write policies;
- grants limited to the roles that need them; and
- tests for both permitted and denied access.

Update `supabase/seed.sql` only for reviewed reference catalog data. Do not seed people, credentials, PDFs, posts, reports, quizzes, or attempts.

## Edge Function changes

- Authenticate the caller and load the active profile.
- Validate request size, UUIDs, types, and allowed values.
- Enforce Subject and material access again on the server.
- Use bounded timeouts and helpful error codes.
- Keep secrets in Supabase secret storage.
- Never log PDF contents, access tokens, answer keys, or secret values.
- Validate external AI output before storing or returning it.

## Checks before handoff

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk
```

Run focused tests while working, then run the complete suite once source changes stop. If a check cannot run, record the reason rather than claiming it passed.

For backend changes, also preview the migration and deploy to the intended supervised-test project only after confirming its reference:

```powershell
npx.cmd --yes supabase@2.116.0 db push --linked --include-seed --dry-run
```

## Pull request checklist

- [ ] Change matches the corrected Student/Admin scope.
- [ ] Beginner-facing comments were added or updated.
- [ ] No secret or private user data appears in the diff.
- [ ] Access rules are enforced on the server, not only hidden in the UI.
- [ ] Formatting and analysis results are recorded.
- [ ] Focused and complete test results are recorded.
- [ ] Database and function changes include deployment notes.
- [ ] Documentation matches the implemented behavior.
- [ ] APK impact was tested when phone behavior changed.

## Commit messages

Use short action-based messages, for example:

```text
feat: add trusted quiz submission
fix: deny restricted profile refresh
test: cover one-target report rule
docs: explain phone-test build
```

Do not commit generated APKs, local CLI state, `.env` files, keystores, or signing passwords.
