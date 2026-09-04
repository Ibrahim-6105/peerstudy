# PeerStudy implementation guide

This guide takes a beginner from a fresh checkout to a phone-test build. Run commands from the repository root in PowerShell.

## 1. Install tools

Required tools:

- Flutter compatible with Dart `^3.12.0`;
- Android Studio or Android SDK command-line tools;
- Java 17;
- Node.js for `npx`; and
- a Supabase account with access to the target project.

Check the phone toolchain first:

```powershell
flutter doctor -v
flutter pub get
```

Fix all Android items reported by `flutter doctor` before building an APK.

## 2. Understand public and secret values

The Flutter app needs three public values:

| Value | Purpose |
| --- | --- |
| `SUPABASE_URL` | Hosted project API URL |
| `SUPABASE_PUBLISHABLE_KEY` | Public mobile client key |
| `SUPABASE_AUTH_REDIRECT_URL` | Password-recovery return link |

Defaults are stored in `lib/config/supabase_config.dart`. The current public project reference is `xihsvhhkbaaypmjjtzxa`, and the redirect is `io.supabase.peerstudy://login-callback`.

Never put these secret values in Flutter or Git:

- a Supabase service-role or secret key;
- `AI_API_KEY`; or
- database passwords.

Use `supabase.example.json` only as a public configuration template for another project.

## 3. Configure Auth

In the Supabase Dashboard for the target project:

1. Enable email/password sign-in.
2. Set the application URL to `io.supabase.peerstudy://login-callback`.
3. Add both of these allowed redirect URLs:
   - `io.supabase.peerstudy://login-callback`
   - `io.supabase.peerstudy://login-callback/`
4. Decide whether email confirmation is required for the supervised test.

The Android manifest and iOS URL types already register the scheme. The database trigger rejects non-LIMU Auth emails and always creates public signups as Students.

## 4. Link the hosted project

Login opens a browser once. Link writes only machine-specific state under `supabase/.temp`, which Git ignores.

```powershell
npx.cmd --yes supabase@2.116.0 login
npx.cmd --yes supabase@2.116.0 link --project-ref xihsvhhkbaaypmjjtzxa
npx.cmd --yes supabase@2.116.0 projects list
```

Confirm the intended project before any write.

## 5. Apply schema and reference data

First preview the exact remote change:

```powershell
npx.cmd --yes supabase@2.116.0 db push --linked --include-seed --dry-run
```

Review the output, then apply it:

```powershell
npx.cmd --yes supabase@2.116.0 db push --linked --include-seed
```

The migrations create tables, constraints, indexes, triggers, database functions, Row Level Security policies, Realtime publication entries, and the private `subject-materials` and `community-attachments` buckets. The seed adds only the corrected academic reference data. It creates no people, PDFs, attachments, posts, quizzes, attempts, or reports.

Do not repeatedly wipe a shared project. For a fresh acceptance run, the project owner should remove old test users and their owned data deliberately, confirm the exact target project, and then create the agreed accounts again.

## 6. Configure real quiz generation

The function uses a Gemini-compatible HTTPS endpoint. It requires both `AI_API_KEY` and `AI_MODEL`. There is no fallback question set.

Create the ignored file `supabase/functions/.env` locally:

```text
AI_API_KEY=YOUR_REAL_PROVIDER_KEY
AI_MODEL=gemini-3.5-flash
AI_FALLBACK_MODEL=gemini-3.1-flash-lite
```

Optional server settings include `AI_API_BASE_URL`, `AI_TIMEOUT_MS`, `QUIZ_GENERATION_PER_MINUTE`, and `ALLOWED_ORIGIN`. Do not change them unless the deployment owner understands their effect.

Upload the secrets without placing their values in a command or build log:

```powershell
npx.cmd --yes supabase@2.116.0 secrets set `
  --env-file supabase/functions/.env `
  --project-ref xihsvhhkbaaypmjjtzxa
```

Deploy the protected functions through the Supabase API:

```powershell
npx.cmd --yes supabase@2.116.0 functions deploy generate-quiz submit-quiz finalize-community-attachment cleanup-community-attachments `
  --project-ref xihsvhhkbaaypmjjtzxa `
  --use-api
```

JWT verification is enabled in `supabase/config.toml`. Do not add `--no-verify-jwt`.

## 7. Provision the Admin

Public registration must not be used for Admin creation. The project owner creates the Auth user in the Supabase Dashboard or through a trusted server-side Admin API, confirms the email, and then changes the matching `profiles.role` to `admin` from a trusted operator context.

For the requested supervised phone test, the expected credential after provisioning is:

```text
Login name: admin
Password: 123456
```

The app maps this exact Admin alias to the underlying Auth email `admin@limu.edu.ly`. Student login still requires a complete university email. Verify the matching profile is `role = admin` and `status = active`. Never place a service-role key in a provisioning script committed to this repository.

The password is intentionally weak for the requested classroom test. Before a real deployment, change it to a unique long password, remove the published test credential, and retest password recovery.

## 8. Register a Student

Use a fresh, complete university address such as `student.name@limu.edu.ly` and a password that meets the app’s signup rules. Registration must create:

- one Supabase Auth user; and
- one matching active `profiles` row with role `student`.

If confirmation is enabled, complete the email step before login. A Student must never reach an Admin route even if a route name is typed manually.

## 9. Run locally

The checked-in public configuration is used by default:

```powershell
flutter run
```

To point a build to a different project:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY `
  --dart-define=SUPABASE_AUTH_REDIRECT_URL=io.supabase.peerstudy://login-callback
```

The phone needs internet access to the hosted Supabase project and the external quiz service. Community attachment uploads accept up to three JPG/JPEG, PNG, WebP, PDF, or UTF-8 TXT files per post/comment, with a 10 MiB limit per file, ten new reservations per minute, and 100 MiB of uncleaned bytes per Student.

## 10. Run code checks

Run these commands after every meaningful change:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Record the exact output in the handoff. Do not write “all tests pass” from an earlier run after source files have changed.

## 11. Build and install the APK

For this student phone test, leave `android/key.properties` absent. The Android build then uses the local debug key automatically:

```powershell
flutter clean
flutter pub get
flutter build apk
```

Expected output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Connect a phone with USB debugging enabled and verify that Android can see it:

```powershell
adb devices
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

If an owner keystore is later required, copy `android/key.properties.example` to `android/key.properties` and supply valid private values. The test build does not require this.

## 12. Perform the acceptance walk-through

Use fresh data and record each result:

1. Register and sign in as a Student.
2. Confirm School, Area, Department, and Subject navigation.
3. Sign in as Admin and upload one real approved PDF.
4. Return as Student and open it through the temporary secure link in the device browser or PDF app.
5. Select that material, explicitly start a quiz, answer ten questions, submit, and review corrections.
6. Create a post and comment from two Student sessions; verify real counts and timestamps.
7. Report one post or comment and verify the report is private.
8. Resolve reports with dismiss, remove, and restrict actions using fresh targets.
9. Confirm a restricted Student is denied protected access.
10. Restart the app and confirm valid sessions route correctly.

Failures should remain visible in the audit until fixed and rerun.

## Common setup errors

| Symptom | Check |
| --- | --- |
| Configuration error screen | Public URL/key shape and project availability |
| Registration rejected | Full lowercase-compatible `@limu.edu.ly` address |
| Admin reaches Student home | Matching profile role and active status |
| Recovery link opens browser only | Dashboard redirect allowlist and phone scheme |
| PDF does not open | Material approval, private path, file size, and RLS |
| Quiz reports configuration failure | `AI_API_KEY`, `AI_MODEL`, and deployed function version |
| Quiz has no questions | Approved PDF contents and AI provider response logs |
| APK signing error | Remove invalid `android/key.properties` for the phone-test build |
