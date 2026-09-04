# PeerStudy

PeerStudy is a Flutter learning application for LIMU’s School of Technology and Engineering. The corrected system has exactly two roles: **Student** and **Admin**.

Students register with a complete `@limu.edu.ly` email, browse the academic hierarchy, open approved PDF materials, generate a ten-question quiz from one selected material, join the matching subject community, share private attachments with posts/comments, and privately report content.

Admins use their pre-created account to manage academic areas, departments, subjects, materials, reports, and Student access. Creating a Subject also creates its one Community.

## System shape

```text
Flutter phone app
    |
    +-- Supabase Auth: Student and Admin sessions
    +-- PostgreSQL: profiles, catalog, communities, attachments, quizzes, reports
    +-- Private Storage: approved PDFs and Community attachments
    +-- Realtime: posts, comments, and attachment metadata
    +-- Edge Functions: quizzes, attachment validation, and file cleanup
```

Supabase is authoritative. The phone stores only device preferences and temporary viewer data. Correct answers and server secrets never belong in the Flutter application.

## Academic hierarchy

```text
School of Technology and Engineering
    +-- Information Technology
    |   +-- Software Engineering
    |   +-- Network
    |   +-- Telecommunications
    |   +-- Health Informatics
    |   +-- Artificial Intelligence (AI)
    +-- Engineering
        +-- Architectural and Structural Engineering
        +-- Mechatronics
        +-- Interior Design
```

The seed also creates the corrected reference Subject, **Software Engineering Fundamentals**, and its Community. Admins add reviewed Subjects through the app.

## Quick start

Install Flutter, Android Studio or the Android SDK, Java 17, and Node.js. Then run from the repository root:

```powershell
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter run
```

The checked-in public client configuration currently targets project reference `xihsvhhkbaaypmjjtzxa`. The publishable key is intentionally public. Never place a Supabase service-role key or an AI key in Flutter source, `--dart-define`, an APK, or Git.

Another project can be selected at build time:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY `
  --dart-define=SUPABASE_AUTH_REDIRECT_URL=io.supabase.peerstudy://login-callback
```

## Configure the hosted backend

Authenticate the Supabase CLI, link the project, preview the migration, and apply the migration with its reference seed:

```powershell
npx.cmd --yes supabase@2.116.0 login
npx.cmd --yes supabase@2.116.0 link --project-ref xihsvhhkbaaypmjjtzxa
npx.cmd --yes supabase@2.116.0 db push --linked --include-seed --dry-run
npx.cmd --yes supabase@2.116.0 db push --linked --include-seed
```

Quiz generation is a real external service call. Put `AI_API_KEY` and `AI_MODEL` in the ignored file `supabase/functions/.env`, upload them as Supabase secrets, and deploy the protected functions:

```powershell
npx.cmd --yes supabase@2.116.0 secrets set `
  --env-file supabase/functions/.env `
  --project-ref xihsvhhkbaaypmjjtzxa
npx.cmd --yes supabase@2.116.0 functions deploy generate-quiz submit-quiz finalize-community-attachment cleanup-community-attachments `
  --project-ref xihsvhhkbaaypmjjtzxa `
  --use-api
```

Do not commit `supabase/functions/.env`. Quiz generation must report a configuration error until genuine AI credentials are supplied; it must not return invented fallback questions.

See [the implementation guide](docs/implementation-guide.md) for the complete beginner-friendly setup.

## Admin phone-test account

The hosted classroom-test account is now provisioned:

- Login name: `admin`
- Password: `123456`

The app maps this one Admin alias to the underlying Supabase Auth identity `admin@limu.edu.ly`. Students must still enter their complete university email.

This password is intentionally simple for the requested phone test. It is not acceptable for a public system. Change the password and remove this published credential before any real deployment. Public Student registration cannot create an Admin.

## Build the APK

No owner keystore is required for a phone test. When `android/key.properties` is absent, the release build uses the local debug signing key while retaining release-mode optimization:

```powershell
flutter clean
flutter pub get
flutter build apk
```

The APK is written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Install it with Android tools or copy it to the phone:

```powershell
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Verification status

The hosted project has a genuine Gemini key and a verified primary/fallback
model configuration; quiz generation returns real ten-question results and
never uses demo questions. Current command counts, attachment acceptance
evidence, APK checksum, and any remaining physical-phone checks are recorded in
the linked audit files rather than duplicated here.

The signed phone-test APK is
`build/app/outputs/flutter-apk/PeerStudy-phone-test.apk`. See the
[repository audit](docs/repository-audit.md) and
[hosted evidence](docs/evidence/hosted-smoke-summary.md) for exact results.

## Documentation

- [PeerStudy project guide (PDF)](PeerStudy-Project-Guide.pdf)
- [PeerStudy project guide source](PeerStudy-Project-Guide.md)
- [Project brief](docs/project-brief.md)
- [Architecture](docs/architecture.md)
- [Implementation guide](docs/implementation-guide.md)
- [Supabase backend reference](docs/supabase-implementation.md)
- [Repository audit](docs/repository-audit.md)
- [Roadmap and acceptance checklist](docs/roadmap.md)
- [Contributing](docs/contributing.md)
