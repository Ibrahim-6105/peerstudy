# Repository audit

## Final verification record

- Date: 30 August 2026 (Africa/Tripoli)
- Supabase project: `xihsvhhkbaaypmjjtzxa`
- Fresh account reset: 1 old Auth account removed
- Database: corrected core and Community attachment migrations applied successfully
- Edge Functions: quiz generation/submission and attachment finalization/cleanup active with JWT verification
- Admin: `admin@limu.edu.ly` is active; alias `admin` / password `123456` verified
- Formatting: 63 Dart files checked, 0 changes required
- Flutter analysis: 0 issues
- Flutter tests: 57 passed, 0 failed
- Hosted acceptance: 21 passed, 0 failed, 0 blocked
- APK build: passed
- APK package: `ly.edu.limu.peerstudy`, version `1.0.0`, minimum Android API 24
- APK signature: Android v2 signature verified with the local debug test certificate
- APK path: `build/app/outputs/flutter-apk/PeerStudy-phone-test.apk`
- APK size: 80,051,225 bytes
- APK SHA-256: `6AA9695EE4DAFADE28754F810B39D9348BA6F2945CA7ADD075DC2E7316E4DDB0`

## Corrected scope evidence

| Requirement | Evidence |
| --- | --- |
| Student and Admin only | Migration checks, route guards, and hosted profiles passed |
| LIMU Student signup | Hosted valid signup passed; non-LIMU signup was rejected |
| School -> Area -> Department -> Subject | Hosted Student RLS exposed a complete usable hierarchy while preserving owner additions |
| One Community per Subject | Hosted Subject and matching Community IDs were equal |
| Private approved PDFs | Hosted unapproved/approved/removed lifecycle and SHA-256 download passed |
| Posts and comments | Hosted create, versioned edit, author delete, and count flow passed |
| Private Community attachments | Real Post PDF and Comment TXT validation/read/removal passed; forged bytes and cross-user actions were denied |
| Private one-target reports | Two-Student privacy and Admin visibility passed |
| Admin report action | Hosted atomic dismiss passed; remove/restrict also have SQL checks |
| Restricted access denial | Existing Student token lost catalog access immediately and recovered after reactivation |
| Exactly ten AI questions | A real Gemini call from a protected approved PDF returned exactly ten validated questions |
| Server-side quiz scoring | Real hosted submission returned a trusted score and ten corrections without exposing the key before submission |

Full hosted details are recorded in
[hosted-smoke-summary.md](evidence/hosted-smoke-summary.md). The reusable runner
is `supabase/scripts/hosted-smoke.ts`; it prints no keys or tokens and cleans
temporary data in `finally`.

## Clean hosted test state

The acceptance runner removed only its uniquely tracked temporary Students,
profiles, posts, comments, Community attachments, reports, materials, Storage objects, quizzes,
attempts, and audit rows. Existing owner accounts, catalog entries, and data
were preserved.

## Remaining external checks

- Install the final APK on a physical Android phone and repeat the Student and
  Admin flows on normal Wi-Fi or mobile data.
- Password-recovery delivery depends on a real LIMU mailbox and should be
  confirmed with the university mail system.

These are external device/mail checks, not demo replacements. The real hosted
AI generation and scoring path is configured and verified.
